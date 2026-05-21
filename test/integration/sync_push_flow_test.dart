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
import 'package:bookmarks/core/drive/models/drive_bookmarks_file.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _decodeUploadedJson(String multipart) {
  final match = RegExp(
    r'Content-Transfer-Encoding: base64\r?\n\r?\n([^\r\n-]+)',
  ).firstMatch(multipart);
  if (match == null) return multipart;
  return utf8.decode(base64.decode(match.group(1)!.trim()));
}

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
  String remoteContent;
  final List<http.Request> updateRequests = [];
  final List<int Function()> updateStatusScript = [];

  _FakeDrive({String? initialRemoteJson})
      : remoteContent = initialRemoteJson ??
            jsonEncode({
              'version': 1,
              'lastModified': DateTime.now().toUtc().toIso8601String(),
              'bookmarks': <Object>[],
              'folders': <Object>[],
              'tags': <Object>[],
            });

  http.Client buildClient() => MockClient.streaming((request, bodyStream) async {
        final url = request.url;
        if (url.path.startsWith('/upload/drive/v3/files/')) {
          final body = await bodyStream
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          final text = utf8.decode(body);
          updateRequests.add(http.Request(request.method, url)..body = text);
          final status =
              updateStatusScript.isNotEmpty ? updateStatusScript.removeAt(0)() : 200;
          if (status == 200) {
            remoteContent = text;
            return http.StreamedResponse(
              Stream<List<int>>.value(
                  utf8.encode('{"id":"file-1","name":"bookmarks.json"}')),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('error')),
            status,
          );
        }
        if (request.method == 'GET' &&
            url.path.startsWith('/drive/v3/files/')) {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(remoteContent)),
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
      // Replace the engine with one configured for fast retry. Other deps
      // (queue, snapshot builder, credentials store) come from the same
      // overrides chain so they reuse the real implementations against
      // the in-memory storage + the test database + the mock client.
      driveSyncServiceProvider.overrideWith((ref) {
        return DriveSyncService(
          queue: ref.watch(syncQueueRepositoryProvider),
          snapshotBuilder: ref.watch(driveSnapshotBuilderProvider),
          credentials: ref.watch(driveCredentialsStoreProvider),
          storage: ref.watch(flutterSecureStorageProvider),
          httpClient: ref.watch(httpClientProvider),
          retryPolicy: _fastRetry,
        );
      }),
    ],
  );
}

Bookmark _bm(String id) {
  final now = DateTime.now();
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: 'Title $id',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late _InMemoryStorage storage;
  late _FakeDrive drive;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemoryStorage();
    drive = _FakeDrive();
    _seedCreds(storage);
  });

  tearDown(() async {
    await db.close();
  });

  test('A: first write with empty remote -> probe opens gate -> push uploads',
      () async {
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

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));

    // 250ms debounce + slack.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(drive.updateRequests, hasLength(1));
    expect(storage.store.containsKey(kDriveLastPulledAtKey), isTrue);
    final parsed = DriveBookmarksFile.fromJson(
      jsonDecode(_decodeUploadedJson(drive.updateRequests.single.body)) as Map<String, dynamic>,
    );
    expect(parsed.bookmarks.map((b) => b.id).toList(), ['b1']);
  });

  test('B: first write with non-empty remote -> probe leaves gate closed -> '
      'no upload', () async {
    drive = _FakeDrive(
      initialRemoteJson: jsonEncode({
        'version': 1,
        'lastModified': DateTime.now().toUtc().toIso8601String(),
        'bookmarks': [
          {
            'id': 'remote-b',
            'url': 'https://other-device.com',
            'title': 'Other device',
            'tagIds': <String>[],
            'createdAt': '2026-05-15T10:00:00.000Z',
            'updatedAt': '2026-05-15T10:00:00.000Z',
          },
        ],
        'folders': <Object>[],
        'tags': <Object>[],
      }),
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

    final emitted = <SyncStatus>[];
    final sub = container.read(driveSyncServiceProvider).watchStatus().listen(emitted.add);
    addTearDown(sub.cancel);

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(drive.updateRequests, isEmpty,
        reason: 'gate closed -> no upload');
    expect(storage.store.containsKey(kDriveLastPulledAtKey), isFalse);
    expect(emitted.whereType<SyncAwaitingInitialPull>(), isNotEmpty);
  });

  test('C: multiple mutations are eventually reflected in a push snapshot',
      () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();

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

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    final repo = BookmarkRepository(db);
    for (var i = 0; i < 5; i++) {
      await repo.save(_bm('b$i'));
    }

    // Drain any in-flight debounce, then drive a terminal push so the
    // snapshot definitely reflects all 5 saves (regardless of how the
    // orchestrator chose to batch them across the loop).
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await container
        .read(driveSyncServiceProvider)
        .push(fileId: 'file-1');

    expect(drive.updateRequests, isNotEmpty);
    final parsed = DriveBookmarksFile.fromJson(
      jsonDecode(_decodeUploadedJson(drive.updateRequests.last.body))
          as Map<String, dynamic>,
    );
    expect(parsed.bookmarks.map((b) => b.id).toSet(),
        containsAll(<String>['b0', 'b1', 'b2', 'b3', 'b4']));
    // The 5 rapid mutations must not produce 5 separate pushes — the
    // orchestrator's 250ms debounce + the snapshot model collapse a
    // burst into at most a handful of uploads. (Exact count varies with
    // event-loop timing; cap at 3 to catch a regression where each
    // mutation independently fires its own push.)
    expect(drive.updateRequests.length, lessThanOrEqualTo(3),
        reason: 'debounce + snapshot model must collapse the burst');
  });

  test('D + F: 503 once -> retry succeeds; then subsequent write re-pushes',
      () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();

    drive.updateStatusScript.add(() => 503);
    // Subsequent calls default to 200.

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

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // First push: 503 then 200 → at least 2 HTTP attempts; the retry
    // succeeded so the final upload reflects b1.
    expect(drive.updateRequests.length, greaterThanOrEqualTo(2));
    final firstParsed = DriveBookmarksFile.fromJson(
      jsonDecode(_decodeUploadedJson(drive.updateRequests.last.body))
          as Map<String, dynamic>,
    );
    expect(firstParsed.bookmarks.map((b) => b.id).toSet(), {'b1'});

    // A subsequent write should eventually result in an upload that
    // reflects both bookmarks. We tolerate however many uploads land
    // and trigger a terminal push to assert the final state on the
    // wire reflects everything saved.
    final priorRequests = drive.updateRequests.length;
    await repo.save(_bm('b2'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await container
        .read(driveSyncServiceProvider)
        .push(fileId: 'file-1');

    expect(drive.updateRequests.length, greaterThan(priorRequests));
    final secondParsed = DriveBookmarksFile.fromJson(
      jsonDecode(_decodeUploadedJson(drive.updateRequests.last.body))
          as Map<String, dynamic>,
    );
    expect(secondParsed.bookmarks.map((b) => b.id).toSet(), {'b1', 'b2'});
  });

  test('E: 503 thrice -> failed; queue NOT drained', () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();

    drive.updateStatusScript.addAll([
      () => 503,
      () => 503,
      () => 503,
    ]);

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

    final emitted = <SyncStatus>[];
    final sub = container.read(driveSyncServiceProvider).watchStatus().listen(emitted.add);
    addTearDown(sub.cancel);

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(drive.updateRequests, hasLength(3));
    expect(emitted.whereType<SyncFailed>(), isNotEmpty);

    // Queue is NOT drained -- the original mutation's queue row persists.
    final remaining = await container.read(syncQueueRepositoryProvider).drain();
    expect(remaining, isNotEmpty);
  });
}
