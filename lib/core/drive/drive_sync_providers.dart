import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show appDatabaseProvider;
import '../database/sync_queue_repository.dart';
import 'drive_auth_providers.dart';
import 'drive_auth_state.dart';
import 'drive_credentials_store.dart';
import 'drive_snapshot_builder.dart';
import 'drive_sync_service.dart';
import 'merge_applier.dart';
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

/// Merge applier — Story 4.3. Owns the transactional pull-side write
/// path: computes a per-record LWW plan via `MergeEngine`, then
/// applies it inside a single Drift transaction with the post-merge
/// `sync_queue` cursor cleanup.
final mergeApplierProvider = Provider<MergeApplier>((ref) {
  return MergeApplier(ref.watch(appDatabaseProvider));
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
    mergeApplier: ref.watch(mergeApplierProvider),
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

/// Whether the engine has ever emitted [SyncSynced] this session.
/// Used by the [SyncStatusIndicator] to distinguish "synced and
/// healthy" (green) from "no sync attempted yet, but no failure
/// either" (amber "Awaiting initial sync"). Starts at `false`;
/// becomes `true` on the first `SyncSynced` emit and stays `true`
/// for the rest of the session — a subsequent `SyncFailed` does not
/// reset the flag (the gate has been opened).
///
/// Cold-start latency trade-off: on a session start where the gate was
/// opened in a prior session, the engine emits `SyncIdle` first; the
/// first real `SyncSynced` arrives after the orchestrator's
/// cold-start `sync()` cycle (~250 ms). The indicator briefly reads
/// amber "Awaiting initial sync from Drive" during this window, then
/// transitions to green. Accepted vs. a per-rebuild secure-storage
/// read of `kDriveLastPulledAtKey`, which is heavier and less reactive.
final hasEverSyncedProvider = StreamProvider<bool>((ref) async* {
  yield false;
  final statusStream = ref.watch(driveSyncServiceProvider).watchStatus();
  await for (final status in statusStream) {
    if (status is SyncSynced) {
      yield true;
      return;
    }
  }
});

/// Side-effect provider that wires three sync trigger events. Story
/// 4.3 widens this from "auto-push" to "auto-sync": each trigger now
/// invokes `sync()` (pull-then-push), so the orchestrator is the
/// single dispatch point for the full sync cycle. The provider name
/// remains `autoPushOrchestratorProvider` to keep the change scoped
/// (rename touches a lot of test scaffolding) — semantically it is the
/// auto-sync orchestrator.
///
/// Triggers:
///   1. Queue non-empty observation (debounced 250ms).
///   2. Drive transitioned `_ -> connected` (cold start / re-connect).
///   3. (Story 4.5 will add connectivity-restored as a fourth trigger.)
///
/// Read for side effects from `AppShell.build()` (lib/core/widgets/
/// app_shell.dart) via `ref.watch(autoPushOrchestratorProvider)`. Scoped
/// to AppShell rather than `lib/app.dart` so the listeners live and die
/// with the sign-in-required surface — the /welcome route mounts no
/// AppShell, so the orchestrator is dormant before connect. The provider
/// has no public value; the side effects are the point.
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
                .sync(fileId: auth.fileId);
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
        // run a full sync cycle. The pull half handles the gate
        // decision (and the FR36 first-launch population path); the
        // push half drains any pre-existing queue rows.
        ref.read(driveSyncServiceProvider).sync(fileId: state.fileId);
      });
    },
  );

  ref.onDispose(() => debounce?.cancel());
});
