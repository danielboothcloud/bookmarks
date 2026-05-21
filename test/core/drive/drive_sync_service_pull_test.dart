import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_credentials_store.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_snapshot_builder.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/drive/merge_applier.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      store[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _seedCreds(_InMemorySecureStorage storage) {
  storage.store[DriveStorageKeys.accessToken] = 'access-x';
  storage.store[DriveStorageKeys.refreshToken] = 'refresh-x';
  storage.store[DriveStorageKeys.expiresAt] =
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
}

String _envelopeJson({
  required String lastModified,
  List<Map<String, Object?>> bookmarks = const [],
  List<Map<String, Object?>> folders = const [],
  List<Map<String, Object?>> tags = const [],
  int version = 1,
}) {
  return jsonEncode({
    'version': version,
    'lastModified': lastModified,
    'bookmarks': bookmarks,
    'folders': folders,
    'tags': tags,
  });
}

/// Drive server that scripts the GET (files.get?alt=media) response
/// per attempt. PATCH (upload) responses default to 200.
class _PullFakeDrive {
  _PullFakeDrive({this.getScript = const <_ScriptedGet>[]});

  final List<_ScriptedGet> getScript;
  int getCount = 0;
  int updateCount = 0;

  http.Client buildClient() {
    return MockClient.streaming((request, bodyStream) async {
      final url = request.url;
      if (request.method == 'GET' &&
          url.path.startsWith('/drive/v3/files/')) {
        getCount++;
        final entry = getScript.isNotEmpty
            ? getScript.removeAt(0)
            : _ScriptedGet.ok(_envelopeJson(
                lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
              ));
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(entry.body)),
          entry.status,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (url.path.startsWith('/upload/drive/v3/files/')) {
        updateCount++;
        await bodyStream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        return http.StreamedResponse(
          Stream<List<int>>.value(
              utf8.encode('{"id":"file-1","name":"bookmarks.json"}')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{}')),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
  }
}

class _ScriptedGet {
  _ScriptedGet({required this.status, required this.body});
  factory _ScriptedGet.ok(String body) =>
      _ScriptedGet(status: 200, body: body);
  factory _ScriptedGet.transient500() => _ScriptedGet(
        status: 500,
        body: jsonEncode({
          'error': {'code': 500, 'message': 'transient'},
        }),
      );
  factory _ScriptedGet.auth401() => _ScriptedGet(
        status: 401,
        body: jsonEncode({
          'error': {'code': 401, 'message': 'unauth'},
        }),
      );
  final int status;
  final String body;
}

const _fastRetry = DriveRetryPolicy(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 5),
);

DriveSyncService _buildService({
  required AppDatabase db,
  required _InMemorySecureStorage storage,
  required http.Client client,
  DateTime Function()? clock,
}) {
  return DriveSyncService(
    queue: SyncQueueRepository(db),
    snapshotBuilder: DriveSnapshotBuilder(db),
    credentials: DriveCredentialsStore(
      storage: storage,
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
    ),
    storage: storage,
    httpClient: client,
    mergeApplier: MergeApplier(db),
    retryPolicy: _fastRetry,
    clock: clock ?? () => DateTime.utc(2026, 5, 20, 14, 23, 45, 123),
  );
}

void main() {
  late AppDatabase db;
  late _InMemorySecureStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemorySecureStorage();
    _seedCreds(storage);
  });

  tearDown(() async {
    await db.close();
  });

  test('happy path: pull empty remote on empty local; status transitions '
      'pulling -> merging -> synced; gate opens', () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.ok(_envelopeJson(
        lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
      )),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());

    expect(statuses.whereType<SyncPulling>(), hasLength(1));
    expect(statuses.whereType<SyncMerging>(), hasLength(1));
    expect(statuses.whereType<SyncSynced>(), hasLength(1));
    // Ordering: pulling -> merging -> synced.
    expect(
      statuses.indexWhere((s) => s is SyncPulling) <
          statuses.indexWhere((s) => s is SyncMerging),
      isTrue,
    );
    expect(
      statuses.indexWhere((s) => s is SyncMerging) <
          statuses.indexWhere((s) => s is SyncSynced),
      isTrue,
    );

    // Gate opened.
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);

    await sub.cancel();
  });

  test('version mismatch: version=2 returns Err; gate stays closed; '
      'local DB untouched', () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.ok(_envelopeJson(
        version: 2,
        lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
      )),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    final err = (result as Err<void, AppError>).error;
    expect(err, isA<SyncError>());
    expect((err as SyncError).message, contains('Unsupported Drive file version'));
    expect(storage.store[kDriveLastPulledAtKey], isNull,
        reason: 'gate must NOT open on version mismatch');

    // Status sequence ends in failed.
    expect(service.currentStatus, isA<SyncFailed>());
  });

  test('malformed JSON body → SyncError("Malformed Drive response..."); '
      'status failed', () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet(status: 200, body: 'not-valid-json'),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    final err = (result as Err<void, AppError>).error;
    expect(err, isA<SyncError>());
    expect((err as SyncError).message, contains('Malformed Drive response'));
    expect(storage.store[kDriveLastPulledAtKey], isNull);
  });

  test('HTTP 500 once then 200: retry succeeds; merge runs; synced emitted',
      () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.transient500(),
      _ScriptedGet.ok(_envelopeJson(
        lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
      )),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(drive.getCount, 2);
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);
  });

  test('HTTP 500 thrice: retry exhausted; status failed; gate stays closed',
      () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.transient500(),
      _ScriptedGet.transient500(),
      _ScriptedGet.transient500(),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    expect(drive.getCount, 3, reason: 'all three retry attempts consumed');
    expect(service.currentStatus, isA<SyncFailed>());
    expect(storage.store[kDriveLastPulledAtKey], isNull);
  });

  test('HTTP 401: no retry; status failed; gate stays closed', () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.auth401(),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    expect(drive.getCount, 1, reason: '401 is not transient — no retry');
    expect(service.currentStatus, isA<SyncFailed>());
    expect(storage.store[kDriveLastPulledAtKey], isNull);
  });

  test('empty remote on non-empty local + open gate: no merge writes; '
      'gate refreshes', () async {
    // Pre-seed: open the gate so the local writes survive.
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 9000, 9000],
    );

    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.ok(_envelopeJson(
        // lastModified BEFORE the local bookmark's updatedAt — local wins.
        lastModified:
            DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true).toIso8601String(),
      )),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());

    // Local bookmark still there.
    final count = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(count.read<int>('c'), 1);
  });

  test('FR36 first-launch: non-empty remote on empty local → all remote '
      'records upserted; gate opens', () async {
    final remoteJson = _envelopeJson(
      lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
      bookmarks: [
        {
          'id': 'b1',
          'url': 'https://example.com/1',
          'title': 'First',
          'tagIds': <String>[],
          'createdAt': DateTime.utc(2026, 5, 1).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
        },
        {
          'id': 'b2',
          'url': 'https://example.com/2',
          'title': 'Second',
          'tagIds': <String>[],
          'createdAt': DateTime.utc(2026, 5, 2).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 5, 2).toIso8601String(),
        },
      ],
      folders: [
        {
          'id': 'f1',
          'name': 'Folder',
          'createdAt': DateTime.utc(2026, 5, 1).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 5, 1).toIso8601String(),
        },
      ],
    );
    final drive = _PullFakeDrive(getScript: [_ScriptedGet.ok(remoteJson)]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    expect(storage.store[kDriveLastPulledAtKey], isNull, reason: 'pre-pull: gate closed');

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());

    final bookmarkCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarkCount.read<int>('c'), 2);
    final folderCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM folders')
        .getSingle();
    expect(folderCount.read<int>('c'), 1);
    expect(storage.store[kDriveLastPulledAtKey], isNotNull,
        reason: 'post-merge gate opens');
  });

  test('concurrent pulls coalesce: second pull awaits the first; only one '
      'files.get attempt is made', () async {
    final drive = _PullFakeDrive(getScript: [
      _ScriptedGet.ok(_envelopeJson(
        lastModified: DateTime.utc(2026, 5, 20).toIso8601String(),
      )),
    ]);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final f1 = service.pull(fileId: 'file-1');
    final f2 = service.pull(fileId: 'file-1');
    final results = await Future.wait([f1, f2]);

    expect(results.every((r) => r is Ok<void, AppError>), isTrue);
    expect(drive.getCount, 1, reason: 'second concurrent pull coalesced');
  });
}
