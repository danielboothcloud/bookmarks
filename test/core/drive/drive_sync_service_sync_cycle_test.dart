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

class _CycleFakeDrive {
  _CycleFakeDrive({this.pullStatus = 200});

  final int pullStatus;
  String? pullBody;
  final int pushStatus = 200;
  int getCount = 0;
  int updateCount = 0;

  String get _defaultEmpty => jsonEncode({
        'version': 1,
        'lastModified': DateTime.utc(2026, 5, 20).toIso8601String(),
        'bookmarks': <Object>[],
        'folders': <Object>[],
        'tags': <Object>[],
      });

  http.Client buildClient() {
    return MockClient.streaming((request, bodyStream) async {
      final url = request.url;
      if (request.method == 'GET' &&
          url.path.startsWith('/drive/v3/files/')) {
        getCount++;
        final body = pullStatus == 200
            ? (pullBody ?? _defaultEmpty)
            : jsonEncode({
                'error': {'code': pullStatus, 'message': 'sim'},
              });
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(body)),
          pullStatus,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (url.path.startsWith('/upload/drive/v3/files/')) {
        updateCount++;
        await bodyStream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        final body = pushStatus == 200
            ? '{"id":"file-1","name":"bookmarks.json"}'
            : jsonEncode({
                'error': {'code': pushStatus, 'message': 'sim'},
              });
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(body)),
          pushStatus,
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

const _fastRetry = DriveRetryPolicy(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 5),
);

DriveSyncService _buildService({
  required AppDatabase db,
  required _InMemorySecureStorage storage,
  required http.Client client,
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
    clock: () => DateTime.utc(2026, 5, 20),
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

  test('sync(): pull-then-push; empty cycle returns Ok', () async {
    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(drive.getCount, 1, reason: 'pull ran');
    // No queue rows → push is a no-op (no files.update).
    expect(drive.updateCount, 0,
        reason: 'empty queue post-merge → no upload');
    // Gate opened from the merge path.
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);
  });

  test('sync(): pull failure short-circuits push', () async {
    final drive = _CycleFakeDrive(pullStatus: 401);
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    expect(drive.getCount, 1);
    expect(drive.updateCount, 0,
        reason: 'pull failed → push must NOT run');
  });

  test('sync(): with pending local queue, pull merges (empty), then push '
      'uploads', () async {
    // Pre-open the gate so push doesn't try the probe.
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    // Seed a local bookmark — fires bookmarks_sync_ai → one queue row
    // PRE-EXISTS before the merge runs.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 1000, 1000],
    );
    final preQueueCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_queue')
        .getSingle();
    expect(preQueueCount.read<int>('c'), 1);

    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(drive.getCount, 1);
    expect(drive.updateCount, 1,
        reason: 'pre-existing user mutation survived merge cursor cleanup '
            '→ push uploads');

    final postQueue = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_queue')
        .getSingle();
    expect(postQueue.read<int>('c'), 0,
        reason: 'push drains the queue after upload');
  });

  test('sync(): concurrent invocations coalesce — second awaits the first',
      () async {
    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final f1 = service.sync(fileId: 'file-1');
    final f2 = service.sync(fileId: 'file-1');
    final results = await Future.wait([f1, f2]);
    expect(results.every((r) => r is Ok<void, AppError>), isTrue);
    expect(drive.getCount, 1,
        reason: 'second sync awaited the first; no extra files.get');
  });

  test('push() concurrent with sync(): push awaits the sync cycle', () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final syncFut = service.sync(fileId: 'file-1');
    final pushFut = service.push(fileId: 'file-1');
    final results = await Future.wait([syncFut, pushFut]);
    expect(results.every((r) => r is Ok<void, AppError>), isTrue);
    // Both calls share one in-flight future → exactly one cycle ran.
    expect(drive.getCount, 1);
  });

  test('sync() arriving while push() is in flight runs its own pull after',
      () async {
    // Regression: a previous implementation collapsed any sync() onto
    // an in-flight push() and silently skipped the pull leg — so
    // lifecycle-resume after a queue-debounce push would never fetch
    // remote changes. The fix: sync() awaits the in-flight push, then
    // runs its own pull-then-push.
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    // Seed a queue row so push() has work and stays in flight long
    // enough for sync() to land.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 1000, 1000],
    );
    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final pushFut = service.push(fileId: 'file-1');
    final syncFut = service.sync(fileId: 'file-1');
    final results = await Future.wait([pushFut, syncFut]);
    expect(results.every((r) => r is Ok<void, AppError>), isTrue);
    expect(drive.getCount, 1,
        reason: 'sync() ran its own pull after push completed');
  });

  test('gate-open storage write failure surfaces as Err', () async {
    final drive = _CycleFakeDrive();
    final failingStorage = _FailingWriteStorage(failKey: kDriveLastPulledAtKey)
      ..store[DriveStorageKeys.accessToken] = 'access-x'
      ..store[DriveStorageKeys.refreshToken] = 'refresh-x'
      ..store[DriveStorageKeys.expiresAt] = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
    final service = DriveSyncService(
      queue: SyncQueueRepository(db),
      snapshotBuilder: DriveSnapshotBuilder(db),
      credentials: DriveCredentialsStore(
        storage: failingStorage,
        clientId: 'test-client-id',
        clientSecret: 'test-client-secret',
      ),
      storage: failingStorage,
      httpClient: drive.buildClient(),
      mergeApplier: MergeApplier(db),
      retryPolicy: _fastRetry,
      clock: () => DateTime.utc(2026, 5, 20),
    );
    addTearDown(service.dispose);

    final result = await service.pull(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>(),
        reason: 'gate-write failure must not be silently swallowed');
    expect(failingStorage.store[kDriveLastPulledAtKey], isNull,
        reason: 'gate stays closed; next pull retries');
  });

  test('sync() suppresses the intermediate synced emit between pull and push',
      () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 1000, 1000],
    );
    final drive = _CycleFakeDrive();
    final service = _buildService(
      db: db,
      storage: storage,
      client: drive.buildClient(),
    );
    addTearDown(service.dispose);

    final statuses = <String>[];
    final sub = service.watchStatus().listen((s) {
      statuses.add(s.runtimeType.toString());
    });

    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    await sub.cancel();

    // Sequence should NOT contain a SyncSynced between SyncMerging and
    // SyncPushing — that intermediate "synced" flash was the bug.
    final mergeIdx = statuses.indexOf('SyncMerging');
    final pushIdx = statuses.indexOf('SyncPushing');
    expect(mergeIdx, isNonNegative);
    expect(pushIdx, greaterThan(mergeIdx));
    final between = statuses.sublist(mergeIdx + 1, pushIdx);
    expect(between.contains('SyncSynced'), isFalse,
        reason: 'no intermediate synced flash; full sequence: $statuses');
  });
}

class _FailingWriteStorage extends _InMemorySecureStorage {
  _FailingWriteStorage({required this.failKey});
  final String failKey;
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (key == failKey) throw StateError('simulated secure-storage failure');
    return super.write(key: key, value: value);
  }
}
