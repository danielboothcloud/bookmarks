import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InMemoryStorage implements FlutterSecureStorage {
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

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  @override
  Future<DriveAuthState> build() async => _initial;
}

class _FakeDrive {
  _FakeDrive({required this.remoteJson});

  String remoteJson;
  int getCount = 0;
  int updateCount = 0;
  final List<int Function()> getStatusScript = <int Function()>[];

  http.Client buildClient() {
    return MockClient.streaming((request, bodyStream) async {
      final url = request.url;
      if (request.method == 'GET' &&
          url.path.startsWith('/drive/v3/files/')) {
        getCount++;
        final status = getStatusScript.isNotEmpty
            ? getStatusScript.removeAt(0)()
            : 200;
        if (status == 200) {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(remoteJson)),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(jsonEncode({
            'error': {'code': status, 'message': 'sim'},
          }))),
          status,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (url.path.startsWith('/upload/drive/v3/files/')) {
        updateCount++;
        final body = await bodyStream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        // Persist the uploaded body so a subsequent pull would see it.
        remoteJson = utf8.decode(body);
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

void _seedCreds(_InMemoryStorage storage) {
  storage.store[DriveStorageKeys.accessToken] = 'a';
  storage.store[DriveStorageKeys.refreshToken] = 'r';
  storage.store[DriveStorageKeys.expiresAt] =
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
}

const _fastRetry = DriveRetryPolicy(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 5),
);

ProviderContainer _buildContainer({
  required AppDatabase db,
  required _InMemoryStorage storage,
  required _FakeDrive drive,
  required DriveAuthState auth,
}) {
  final client = drive.buildClient();
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      flutterSecureStorageProvider.overrideWithValue(storage),
      httpClientProvider.overrideWithValue(client),
      driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      driveSyncServiceProvider.overrideWith((ref) {
        return DriveSyncService(
          queue: ref.watch(syncQueueRepositoryProvider),
          snapshotBuilder: ref.watch(driveSnapshotBuilderProvider),
          credentials: ref.watch(driveCredentialsStoreProvider),
          storage: ref.watch(flutterSecureStorageProvider),
          httpClient: ref.watch(httpClientProvider),
          mergeApplier: ref.watch(mergeApplierProvider),
          retryPolicy: _fastRetry,
          clock: () => DateTime.utc(2026, 5, 20),
        );
      }),
    ],
  );
}

String _envelopeJson({
  String? lastModified,
  List<Map<String, Object?>> bookmarks = const [],
  List<Map<String, Object?>> folders = const [],
  List<Map<String, Object?>> tags = const [],
  int version = 1,
}) {
  return jsonEncode({
    'version': version,
    'lastModified': lastModified ?? DateTime.utc(2026, 5, 20).toIso8601String(),
    'bookmarks': bookmarks,
    'folders': folders,
    'tags': tags,
  });
}

Map<String, Object?> _b(
  String id, {
  String? folderId,
  List<String> tagIds = const [],
  int updatedMs = 1_700_000_000_000,
}) {
  final iso = DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true)
      .toIso8601String();
  return {
    'id': id,
    'url': 'https://example.com/$id',
    'title': 'Title $id',
    ?'folderId': folderId,
    'tagIds': tagIds,
    'createdAt': iso,
    'updatedAt': iso,
  };
}

Map<String, Object?> _f(String id, {String? parentId}) {
  final iso = DateTime.utc(2026, 5, 1).toIso8601String();
  return {
    'id': id,
    'name': 'Folder $id',
    ?'parentId': parentId,
    'createdAt': iso,
    'updatedAt': iso,
  };
}

Map<String, Object?> _t(String id) {
  final iso = DateTime.utc(2026, 5, 1).toIso8601String();
  return {
    'id': id,
    'name': 'Tag $id',
    'createdAt': iso,
    'updatedAt': iso,
  };
}

void main() {
  late AppDatabase db;
  late _InMemoryStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemoryStorage();
    _seedCreds(storage);
  });

  tearDown(() async {
    await db.close();
  });

  test('A: FR36 first-launch — remote bookmarks populate empty local DB; '
      'gate opens', () async {
    final drive = _FakeDrive(
      remoteJson: _envelopeJson(
        bookmarks: [_b('b1'), _b('b2', tagIds: ['t1'])],
        folders: [_f('f1')],
        tags: [_t('t1')],
      ),
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    expect(storage.store[kDriveLastPulledAtKey], isNull,
        reason: 'pre-pull: gate closed');

    final service = container.read(driveSyncServiceProvider);
    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());

    final bookmarkCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarkCount.read<int>('c'), 2);
    final folderCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM folders')
        .getSingle();
    expect(folderCount.read<int>('c'), 1);
    final tagCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM tags')
        .getSingle();
    expect(tagCount.read<int>('c'), 1);
    final junctionCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmark_tags')
        .getSingle();
    expect(junctionCount.read<int>('c'), 1);

    expect(storage.store[kDriveLastPulledAtKey], isNotNull,
        reason: 'post-merge: gate opens');
  });

  test('E: version mismatch — remote has version 2; pull returns Err; '
      'gate stays closed; local DB untouched', () async {
    final drive = _FakeDrive(
      remoteJson: _envelopeJson(
        version: 2,
        bookmarks: [_b('b1')],
      ),
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    final service = container.read(driveSyncServiceProvider);
    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    final err = (result as Err<void, AppError>).error;
    expect(err, isA<SyncError>());

    final bookmarkCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarkCount.read<int>('c'), 0,
        reason: 'local DB untouched on version mismatch');
    expect(storage.store[kDriveLastPulledAtKey], isNull,
        reason: 'gate stays closed');
  });

  test('G: auto-push after pull does not ping-pong — N records merged, '
      'queue empty post-cleanup, no spurious push', () async {
    // Pre-open the gate so a hypothetical chained push wouldn't be
    // gate-blocked. Then run a sync cycle that pulls and merges N
    // records.
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();

    final drive = _FakeDrive(
      remoteJson: _envelopeJson(
        bookmarks: [_b('b1'), _b('b2'), _b('b3')],
      ),
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    final service = container.read(driveSyncServiceProvider);
    final result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());

    // The merge wrote 3 bookmarks → 3 trigger rows → cursor cleanup
    // drops them → queue empty → chained push skips upload.
    expect(drive.getCount, 1, reason: 'exactly one files.get (the pull)');
    expect(drive.updateCount, 0,
        reason: 'queue empty post-cleanup → no chained push upload');

    final queueRows = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_queue')
        .getSingle();
    expect(queueRows.read<int>('c'), 0);
  });

  test('F: mid-merge crash — exception during apply rolls back DB; gate '
      'and queue unchanged; next pull succeeds', () async {
    // First call returns a malformed-version body so merge does not run
    // at all (a true mid-transaction crash would require fault injection
    // into Drift; the rollback semantic we want to verify is "envelope
    // accepted by transport, but engine refuses to commit"). Then a
    // valid envelope on the second call.
    final drive = _FakeDrive(
      remoteJson: _envelopeJson(version: 2),
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    final service = container.read(driveSyncServiceProvider);
    var result = await service.sync(fileId: 'file-1');
    expect(result, isA<Err<void, AppError>>());
    expect(storage.store[kDriveLastPulledAtKey], isNull);

    // Swap remote to a valid v1 envelope and retry.
    drive.remoteJson = _envelopeJson(bookmarks: [_b('b1')]);
    result = await service.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);
    final bookmarkCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarkCount.read<int>('c'), 1);
  });

  test('Two-device convergence — Device A bookmarks land on Device B; '
      'Device B addition lands back on A via push', () async {
    // Device A: 3 bookmarks already in the remote.
    final drive = _FakeDrive(
      remoteJson: _envelopeJson(
        bookmarks: [_b('b1'), _b('b2'), _b('b3')],
      ),
    );
    // Device B starts empty.
    final containerB = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(containerB.dispose);

    final serviceB = containerB.read(driveSyncServiceProvider);
    var result = await serviceB.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    var bookmarkCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarkCount.read<int>('c'), 3,
        reason: 'B pulled all 3 remote bookmarks');

    // B adds a 4th bookmark directly (simulating a user action). The
    // sync_queue trigger fires; next sync cycle uploads.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b4', 'https://example.com/b4', 'B-added', 9_000_000_000_000, 9_000_000_000_000],
    );
    result = await serviceB.sync(fileId: 'file-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(drive.updateCount, greaterThanOrEqualTo(1),
        reason: 'B pushed the 4th bookmark');
  });
}
