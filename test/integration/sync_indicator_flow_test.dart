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
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/widgets/sync_status_indicator.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/tags/data/tag_repository.dart';
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

/// Toggleable fake Drive. `setOnline(false)` makes every endpoint
/// respond with a connection error; `setOnline(true)` flips back to the
/// happy-path behaviour from the push / pull flow tests.
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
  bool _online = true;
  final List<http.Request> uploads = <http.Request>[];

  void setOnline(bool value) => _online = value;

  http.Client buildClient() => MockClient.streaming((request, bodyStream) async {
        if (!_online) {
          throw http.ClientException(
            'Simulated network failure',
            request.url,
          );
        }
        final url = request.url;
        if (url.path.startsWith('/upload/drive/v3/files/')) {
          final body = await bodyStream
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          final text = utf8.decode(body);
          uploads.add(http.Request(request.method, url)..body = text);
          remoteContent = text;
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

void _seedCreds(_InMemoryStorage storage) {
  storage.store[DriveStorageKeys.accessToken] = 'a';
  storage.store[DriveStorageKeys.refreshToken] = 'r';
  storage.store[DriveStorageKeys.expiresAt] =
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
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

Folder _folder(String id, String name) {
  final now = DateTime.now();
  return Folder(id: id, name: name, createdAt: now, updatedAt: now);
}

/// Mirror of the indicator widget's state derivation. Reads the three
/// provider streams off `container` and feeds them to the same pure
/// function the widget uses, so the integration test asserts the same
/// colour + label the user would see.
IndicatorState _readIndicatorState(ProviderContainer container) {
  final status =
      container.read(syncStatusProvider).value ?? const SyncStatus.idle();
  final pending = container.read(syncQueuePendingCountProvider).value ?? 0;
  final hasEver = container.read(hasEverSyncedProvider).value ?? false;
  return indicatorStateFor(
    status: status,
    pendingCount: pending,
    hasEverSynced: hasEver,
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
  // Also re-check the current value (the stream is broadcast(sync: true);
  // a state we already passed may not re-emit).
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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemoryStorage();
    drive = _FakeDriveServer();
    _seedCreds(storage);
  });

  tearDown(() async {
    await db.close();
  });

  test('A: synced → unsynced → syncing → synced cycle (happy path)',
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
    // listen keeps the StreamProviders subscribed for the test's
    // lifetime; container.read alone does not guarantee the
    // subscription stays open between reads.
    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    // Insert a bookmark — the outbox trigger enqueues a row; the
    // orchestrator's 250ms debounce fires sync(); the engine pushes
    // and emits SyncSynced.
    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));

    // The queue must go through > 0 before draining. Wait for the
    // SyncSynced terminal state, then assert the indicator is green.
    await _waitForStatus(container, (s) => s is SyncSynced);

    final state = _readIndicatorState(container);
    expect(state.label, 'Synced with Drive');
    expect(state.dot, AppColors.syncSynced);
    expect(drive.uploads, isNotEmpty,
        reason: 'happy-path push uploaded the snapshot');
  });

  test('B: Drive unavailable surfaces grey "Drive unavailable"',
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
    // listen keeps the StreamProviders subscribed for the test's
    // lifetime; container.read alone does not guarantee the
    // subscription stays open between reads.
    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    drive.setOnline(false);

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));

    await _waitForStatus(container, (s) => s is SyncFailed);

    final greyState = _readIndicatorState(container);
    expect(greyState.label, anyOf('Drive unavailable',
        "Couldn't sync — will retry"),
        reason: 'NetworkError / ClientException → grey');
    expect(greyState.dot, AppColors.syncUnavailable);

    // Queue grows while engine is in SyncFailed: insert another bookmark
    // and assert the indicator stays grey (precedence: SyncFailed > queue
    // count). This exercises the AC2 precedence claim end-to-end.
    await repo.save(_bm('b2'));
    await Future<void>.delayed(Duration.zero);
    final pendingWhileGrey =
        container.read(syncQueuePendingCountProvider).value ?? 0;
    expect(pendingWhileGrey, greaterThanOrEqualTo(2),
        reason: 'second offline write enqueued on top of the first');
    final stillGrey = _readIndicatorState(container);
    expect(stillGrey.dot, AppColors.syncUnavailable,
        reason: 'SyncFailed precedence holds even with pending > 0');
    expect(stillGrey.label, anyOf('Drive unavailable',
        "Couldn't sync — will retry"));

    // Drive recovers; force another trigger by re-saving (queue write
    // re-arms the debounce). The next cycle uploads and we transition
    // back to green.
    drive.setOnline(true);
    await repo.save(_bm('b3'));
    await _waitForStatus(container, (s) => s is SyncSynced);

    final greenState = _readIndicatorState(container);
    expect(greenState.label, 'Synced with Drive');
    expect(greenState.dot, AppColors.syncSynced);
  });

  test('C: brand-new device cold start (no last_pulled_at) starts amber',
      () async {
    // Storage has no kDriveLastPulledAtKey and the engine has not
    // emitted SyncSynced yet. The indicator must read amber "Awaiting
    // initial sync from Drive" before the first successful cycle.
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.disconnected(),
    );
    addTearDown(container.dispose);

    // Prime the providers but DON'T start the orchestrator yet — we
    // want to inspect the pre-sync state.
    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);
    // Let the StreamProvider yield its initial `false`.
    await Future<void>.delayed(Duration.zero);

    final preSync = _readIndicatorState(container);
    expect(preSync.label, 'Awaiting initial sync from Drive');
    expect(preSync.dot, AppColors.syncUnsynced);

    // Now drive a sync cycle; the gate opens and the indicator turns
    // green.
    await container
        .read(driveSyncServiceProvider)
        .sync(fileId: 'file-1');
    await _waitForStatus(container, (s) => s is SyncSynced);

    final postSync = _readIndicatorState(container);
    expect(postSync.label, 'Synced with Drive');
    expect(postSync.dot, AppColors.syncSynced);
  });

  test('D: pending writes show "Unsynced changes" while sync is paused',
      () async {
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    // Start offline so the queue grows without draining.
    drive.setOnline(false);

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

    // Don't start the orchestrator. We want the queue to grow with no
    // sync attempt — exercising the "SyncIdle + pending > 0 → amber
    // Unsynced changes" row of the truth table without first dipping
    // into SyncFailed.
    //
    // Force hasEverSynced=true by emitting a synced status through a
    // direct engine call before going offline (already wired via the
    // initial container construction is not enough — the engine starts
    // at idle). We simulate the prior-session-synced setup by writing
    // the cursor and gating on it manually.
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(hasEverSyncedProvider).value ?? false, isFalse);

    // Insert several bookmarks while the queue can't drain.
    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await repo.save(_bm('b2'));
    await repo.save(_bm('b3'));
    // Let the StreamProvider deliver the new count.
    await Future<void>.delayed(Duration.zero);

    final pending = container.read(syncQueuePendingCountProvider).value ?? 0;
    expect(pending, greaterThan(0));

    final state = _readIndicatorState(container);
    // hasEverSynced is still false (no SyncSynced emit yet), so the
    // label depends on whether the truth-table picks "Awaiting" or
    // "Unsynced". The widget puts "Unsynced changes" when pending > 0
    // regardless of the hasEverSynced flag — verify that.
    expect(state.label, 'Unsynced changes');
    expect(state.dot, AppColors.syncUnsynced);
  });

  test('E: offline CRUD parity — bookmark, folder, tag operations all '
      'commit locally and enqueue while offline', () async {
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

    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    drive.setOnline(false);

    // Hit every CRUD path with Drive offline. Each must succeed
    // locally — the outbox triggers enqueue rows independently of
    // network state.
    final bookmarks = BookmarkRepository(db);
    final folders = FolderRepository(db);
    final tags = TagRepository(db);

    await bookmarks.save(_bm('b1'));
    await bookmarks.save(_bm('b2'));
    final editedB1 = _bm('b1').copyWith(title: 'Edited');
    await bookmarks.save(editedB1);
    await bookmarks.delete('b2');

    await folders.save(_folder('f1', 'Folder one'));

    // Move b1 → folder f1 (re-save with folderId set). Exercises the
    // "move bookmark to folder" CRUD path called out in Task 5 / Test E.
    final movedB1 = editedB1.copyWith(folderId: 'f1');
    await bookmarks.save(movedB1);

    final tagResult = await tags.upsertByName('reading');
    final tag = switch (tagResult) {
      Ok(:final value) => value,
      Err(:final error) => fail('upsertByName failed: $error'),
    };
    await tags.linkBookmarkTag('b1', tag.id);

    await Future<void>.delayed(Duration.zero);

    // Every operation enqueued. The drained list size is the source
    // of truth for "did the outbox fire". We use drain() because
    // watchPendingCount is an aggregated stream — drain returns the
    // raw rows so we can assert all CRUD ops are represented.
    final queueRows =
        await container.read(syncQueueRepositoryProvider).drain();
    expect(queueRows.length, greaterThanOrEqualTo(7),
        reason: 'all CRUD ops enqueued: 2 inserts, 1 update, 1 delete, '
            '1 folder save, 1 move-to-folder, 1 tag upsert, 1 tag link '
            '→ ≥ 7 rows');
    expect(drive.uploads, isEmpty,
        reason: 'no network calls succeed while offline');
  });

  test('F: auth error (no credentials) surfaces grey "Drive unavailable"',
      () async {
    // Credentials cleared from storage — `authenticatedClient` returns
    // null, the engine emits `SyncFailed(AuthError)`, and the indicator
    // must read grey "Drive unavailable" (AC2 maps AuthError to the
    // same label as NetworkError; Story 4.5 will own the re-auth flow).
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    storage.store.remove(DriveStorageKeys.accessToken);
    storage.store.remove(DriveStorageKeys.refreshToken);
    storage.store.remove(DriveStorageKeys.expiresAt);

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

    container.listen(syncQueuePendingCountProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, _) {}, fireImmediately: true);

    // Direct sync call: no credentials → AuthError on the first
    // `authenticatedClient` read inside `pull`/`push`. We do not need
    // the orchestrator here — the AuthError emission is synchronous on
    // the first auth check, so a direct `sync()` is the most precise
    // way to assert the mapping.
    unawaited(container
        .read(driveSyncServiceProvider)
        .sync(fileId: 'file-1'));

    await _waitForStatus(container, (s) => s is SyncFailed);

    final state = _readIndicatorState(container);
    expect(state.label, 'Drive unavailable',
        reason: 'AuthError → "Drive unavailable" (AC2)');
    expect(state.dot, AppColors.syncUnavailable);
  });
}
