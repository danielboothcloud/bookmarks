import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show appDatabaseProvider;
import '../database/sync_queue_repository.dart';
import 'drive_auth_providers.dart';
import 'drive_auth_state.dart';
import 'drive_credentials_store.dart';
import 'drive_snapshot_builder.dart';
import 'drive_sync_service.dart';
import 'oauth_config.dart';
import 'sync_status.dart';

/// Repository over `sync_queue`. Single source of truth for both
/// `watchPendingCount` (UI / orchestrator) and `drain` / `deleteByIds`
/// (the engine's push path).
final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return SyncQueueRepository(ref.watch(appDatabaseProvider));
});

/// Snapshot builder. Reads the current local state into a v1 envelope.
final driveSnapshotBuilderProvider = Provider<DriveSnapshotBuilder>((ref) {
  return DriveSnapshotBuilder(ref.watch(appDatabaseProvider));
});

/// Credentials store backed by the same secure-storage provider as the
/// auth service. Owns the `drive.access_token` / `drive.refresh_token`
/// / `drive.expires_at` keys for read; writes refreshes from
/// `autoRefreshingClient` back to the same keys.
final driveCredentialsStoreProvider = Provider<DriveCredentialsStore>((ref) {
  return DriveCredentialsStore(
    storage: ref.watch(flutterSecureStorageProvider),
    clientId: kOAuthClientId,
    clientSecret: kOAuthClientSecret,
  );
});

/// The sync engine itself. Long-lived for the lifetime of the
/// `ProviderContainer`. `ref.onDispose` cleans up its broadcast stream
/// controller.
final driveSyncServiceProvider = Provider<DriveSyncService>((ref) {
  final service = DriveSyncService(
    queue: ref.watch(syncQueueRepositoryProvider),
    snapshotBuilder: ref.watch(driveSnapshotBuilderProvider),
    credentials: ref.watch(driveCredentialsStoreProvider),
    storage: ref.watch(flutterSecureStorageProvider),
    httpClient: ref.watch(httpClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of [SyncStatus] from the engine. UI consumes this via
/// `ref.watch(syncStatusProvider)` in the `SyncStatusIndicator`.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(driveSyncServiceProvider).watchStatus();
});

/// Live count of pending queue rows. The auto-push orchestrator listens
/// to this to decide when to fire `push()`.
final syncQueuePendingCountProvider = StreamProvider<int>((ref) {
  return ref.watch(syncQueueRepositoryProvider).watchPendingCount();
});

/// Side-effect provider that wires three push trigger events:
///   1. Queue non-empty observation (debounced 250ms).
///   2. Drive transitioned `_ -> connected`.
///   3. (Story 4.5 will add connectivity-restored as a fourth trigger.)
///
/// Read for side effects from `AppShell.build()` (lib/core/widgets/
/// app_shell.dart) via `ref.watch(autoPushOrchestratorProvider)`. Scoped
/// to AppShell rather than `lib/app.dart` so the listeners live and die
/// with the sign-in-required surface — the /welcome route mounts no
/// AppShell, so the orchestrator is dormant before connect. The provider
/// has no public value; the side effects are the point.
///
/// The third trigger from the story (explicit API call from tests / a
/// future "Sync now" button) doesn't need a listener -- callers grab
/// `driveSyncServiceProvider` and invoke `push()` directly.
final autoPushOrchestratorProvider = Provider<void>((ref) {
  Timer? debounce;

  ref.listen<AsyncValue<int>>(
    syncQueuePendingCountProvider,
    (_, next) {
      next.whenData((count) {
        if (count <= 0) return;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () {
          final auth = ref.read(driveAuthStateProvider).value;
          if (auth is DriveAuthConnected) {
            ref
                .read(driveSyncServiceProvider)
                .push(fileId: auth.fileId);
          }
        });
      });
    },
  );

  ref.listen<AsyncValue<DriveAuthState>>(
    driveAuthStateProvider,
    (prev, next) {
      next.whenData((state) {
        if (state is! DriveAuthConnected) return;
        // On transition into connected (any prior state, including a
        // re-emit of connected from a tab focus restoring the same id),
        // attempt a push -- the first-connect probe inside push()
        // handles the gate decision.
        ref.read(driveSyncServiceProvider).push(fileId: state.fileId);
      });
    },
  );

  ref.onDispose(() => debounce?.cancel());
});
