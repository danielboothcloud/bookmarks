import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/settings/application/drive_account_controller.dart';
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
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async =>
      store[key];
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
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Auth notifier whose `reset()` flips state to disconnected and wipes
/// the auth storage keys (mirrors what `DriveAuthService.clearTokens()`
/// does in production). We avoid spinning up the real `DriveAuthService`
/// because its OAuth dependencies are heavy and orthogonal to the
/// disconnect choreography being tested here.
class _TestAuthNotifier extends DriveAuthNotifier {
  _TestAuthNotifier({
    required this.initial,
    required this.storage,
  });

  final DriveAuthState initial;
  final _InMemoryStorage storage;
  int resetCalls = 0;

  @override
  Future<DriveAuthState> build() async => initial;

  void connectAs({required String email, required String fileId}) {
    storage.store[DriveStorageKeys.accessToken] = 'access-$fileId';
    storage.store[DriveStorageKeys.refreshToken] = 'refresh-$fileId';
    storage.store[DriveStorageKeys.expiresAt] = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    state = AsyncData(
      DriveAuthState.connected(email: email, fileId: fileId),
    );
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    storage.store.remove(DriveStorageKeys.accessToken);
    storage.store.remove(DriveStorageKeys.refreshToken);
    storage.store.remove(DriveStorageKeys.expiresAt);
    state = const AsyncData(DriveAuthState.disconnected());
  }
}

class _FakeDriveServer {
  _FakeDriveServer({String? initialRemoteJson})
      : remoteContent = initialRemoteJson ??
            jsonEncode({
              'version': 1,
              'lastModified': DateTime.utc(2026, 5, 19).toIso8601String(),
              'bookmarks': <Object>[],
              'folders': <Object>[],
              'tags': <Object>[],
            });

  String remoteContent;
  final List<http.Request> uploads = <http.Request>[];

  http.Client buildClient() =>
      MockClient.streaming((request, bodyStream) async {
        final url = request.url;
        if (url.path.startsWith('/upload/drive/v3/files/')) {
          final body = await bodyStream
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          final text = utf8.decode(body);
          uploads.add(http.Request(request.method, url)..body = text);
          // googleapis wraps the payload in a multipart envelope with a
          // base64-encoded media block; decode it so the next GET returns
          // just the JSON snapshot (which is what real Drive serves).
          remoteContent = _extractMediaJson(text) ?? text;
          return http.StreamedResponse(
            Stream<List<int>>.value(
                utf8.encode('{"id":"file-1","name":"bookmarks.json"}')),
            200,
            headers: const {'content-type': 'application/json'},
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

String? _extractMediaJson(String multipart) {
  final match = RegExp(
    r'Content-Transfer-Encoding: base64\r?\n\r?\n([^\r\n-]+)',
  ).firstMatch(multipart);
  if (match == null) return null;
  return utf8.decode(base64.decode(match.group(1)!.trim()));
}

const _fastRetry = DriveRetryPolicy(
  maxAttempts: 2,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 3),
);

ProviderContainer _buildContainer({
  required AppDatabase db,
  required _InMemoryStorage storage,
  required _FakeDriveServer drive,
  required _TestAuthNotifier authNotifier,
}) {
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    flutterSecureStorageProvider.overrideWithValue(storage),
    httpClientProvider.overrideWithValue(drive.buildClient()),
    driveAuthStateProvider.overrideWith(() => authNotifier),
    driveSyncServiceProvider.overrideWith((ref) {
      return DriveSyncService(
        queue: ref.watch(syncQueueRepositoryProvider),
        snapshotBuilder: ref.watch(driveSnapshotBuilderProvider),
        credentials: ref.watch(driveCredentialsStoreProvider),
        storage: ref.watch(flutterSecureStorageProvider),
        httpClient: ref.watch(httpClientProvider),
        mergeApplier: ref.watch(mergeApplierProvider),
        retryPolicy: _fastRetry,
      );
    }),
  ]);
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

Future<void> _waitForStatus(
  ProviderContainer container,
  bool Function(SyncStatus) predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final completer = Completer<void>();
  final sub = container
      .read(driveSyncServiceProvider)
      .watchStatus()
      .listen((s) {
    if (predicate(s) && !completer.isCompleted) completer.complete();
  });
  final current = container.read(syncStatusProvider).value;
  if (current != null && predicate(current) && !completer.isCompleted) {
    completer.complete();
  }
  try {
    await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

void main() {
  late AppDatabase db;
  late _InMemoryStorage storage;
  late _FakeDriveServer drive;
  late _TestAuthNotifier authNotifier;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemoryStorage();
    drive = _FakeDriveServer();
    // Pre-seed credentials and an open gate so the engine starts in the
    // "ready to sync" state for the connect-first tests.
    storage.store[DriveStorageKeys.accessToken] = 'a';
    storage.store[DriveStorageKeys.refreshToken] = 'r';
    storage.store[DriveStorageKeys.expiresAt] = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    authNotifier = _TestAuthNotifier(
      initial: const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-A',
      ),
      storage: storage,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'A: disconnect clears queue + gate + tokens; auth state goes '
      'disconnected; engine resets to idle; local Drift data persists',
      () async {
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {},
        fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    // Seed 3 bookmarks and let the first sync complete.
    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await repo.save(_bm('b2'));
    await repo.save(_bm('b3'));
    await _waitForStatus(container, (s) => s is SyncSynced);
    expect(drive.uploads, isNotEmpty);

    // Pre-disconnect snapshot.
    final bookmarksBefore = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarksBefore.read<int>('c'), 3);
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);

    // Disconnect.
    await container
        .read(driveAccountControllerProvider.notifier)
        .disconnect();
    // Pump the auth-state listener so it tickles the engine reset.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Sync queue: empty.
    expect(await SyncQueueRepository(db).drain(), isEmpty);
    // Gate: cleared.
    expect(storage.store[kDriveLastPulledAtKey], isNull);
    // Auth tokens: wiped.
    expect(storage.store[DriveStorageKeys.accessToken], isNull);
    expect(storage.store[DriveStorageKeys.refreshToken], isNull);
    // Auth state: disconnected.
    expect(container.read(driveAuthStateProvider).value,
        isA<DriveAuthDisconnected>());
    // Engine: idle.
    expect(container.read(driveSyncServiceProvider).currentStatus,
        isA<SyncIdle>());

    // Local Drift data: untouched.
    final bookmarksAfter = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(bookmarksAfter.read<int>('c'), 3,
        reason: 'local bookmarks must survive disconnect');
  });

  test(
      'B: reconnect re-establishes sync (auth-state listener fires '
      'sync()); local data uploads to the new account', () async {
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {},
        fireImmediately: true);

    // Initial sync (auth started connected).
    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await _waitForStatus(container, (s) => s is SyncSynced);

    // Disconnect.
    await container
        .read(driveAccountControllerProvider.notifier)
        .disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Insert another bookmark while disconnected.
    await repo.save(_bm('b2'));
    final uploadCountBefore = drive.uploads.length;

    // Reconnect to a different account (different fileId).
    authNotifier.connectAs(email: 'bob@example.com', fileId: 'file-B');

    // Auth-state listener fires sync().
    await _waitForStatus(container, (s) => s is SyncSynced);

    expect(drive.uploads.length, greaterThan(uploadCountBefore),
        reason: 'reconnect triggered a fresh push');

    // The last upload's snapshot contains both b1 and b2 (local data
    // persisted across the disconnect; the snapshot builder reads the
    // current DB state). The upload body is a multipart envelope with
    // the JSON payload base64-encoded, so decode it before asserting.
    final lastJson = _extractMediaJson(drive.uploads.last.body) ??
        drive.uploads.last.body;
    expect(lastJson.contains('b1'), isTrue,
        reason: 'snapshot must include the pre-disconnect bookmark');
    expect(lastJson.contains('b2'), isTrue,
        reason: 'snapshot must include the disconnect-window bookmark');
  });

  test(
      'C: cross-account safety — disconnect clears the queue so a fresh '
      'reconnect to a different account does NOT push leftover queue '
      'rows from the prior account', () async {
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {},
        fireImmediately: true);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('account-A-bm'));
    await _waitForStatus(container, (s) => s is SyncSynced);

    // Queue should be empty after a successful push.
    expect(await SyncQueueRepository(db).drain(), isEmpty);

    // Insert another bookmark right before disconnect (creates a queue
    // row before the orchestrator's debounce fires).
    await repo.save(_bm('pending-on-disconnect'));
    // Don't wait for sync — disconnect immediately.

    await container
        .read(driveAccountControllerProvider.notifier)
        .disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Queue: cleared by disconnect.
    expect(await SyncQueueRepository(db).drain(), isEmpty,
        reason: 'pre-disconnect queue rows must be cleared');
  });

  test(
      'D: local data persistence — N bookmarks before disconnect = N after',
      () async {
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);

    final repo = BookmarkRepository(db);
    for (var i = 0; i < 5; i++) {
      await repo.save(_bm('b$i'));
    }
    await _waitForStatus(container, (s) => s is SyncSynced);

    final before = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(before.read<int>('c'), 5);

    await container
        .read(driveAccountControllerProvider.notifier)
        .disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final after = await db
        .customSelect('SELECT COUNT(*) AS c FROM bookmarks')
        .getSingle();
    expect(after.read<int>('c'), 5,
        reason: 'all 5 local bookmarks must survive disconnect');
  });

  test(
      'E: hasEverSynced invalidates on disconnect — next read starts '
      'from clean baseline', () async {
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await _waitForStatus(container, (s) => s is SyncSynced);

    // After a successful sync, hasEverSynced should be true.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(hasEverSyncedProvider).value, isTrue);

    await container
        .read(driveAccountControllerProvider.notifier)
        .disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // After disconnect, hasEverSynced was invalidated; a fresh read
    // returns either loading or false but never the prior `true`.
    final value = container.read(hasEverSyncedProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
    expect(value, isNot(isTrue),
        reason:
            'invalidation must clear the prior session\'s true value');
  });
}
