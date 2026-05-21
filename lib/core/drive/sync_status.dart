import 'package:freezed_annotation/freezed_annotation.dart';

import '../error/app_error.dart';

part 'sync_status.freezed.dart';

/// Runtime state of the Drive sync engine. Emitted on
/// `DriveSyncService.watchStatus()`; surfaced to the UI via
/// `syncStatusProvider`.
///
/// Story 4.2 shipped five variants for the push half; Story 4.3 adds
/// `pulling` and `merging` for the pull-then-merge half. The standard
/// pull cycle progresses: `pulling -> merging -> synced` (or
/// `pulling -> failed` on a transport / parse / version-mismatch
/// failure; `pulling -> merging -> failed` on a merge-transaction
/// rollback). Story 4.4 will layer the full green/amber/grey state
/// machine on top without changing this type.
///
/// State semantics:
/// - [SyncIdle]: engine has no pending work and has not run a cycle
///   this session.
/// - [SyncPulling]: a `files.get` is in flight; remote body is being
///   downloaded.
/// - [SyncMerging]: the pull succeeded; the merge transaction is
///   running. Distinct from [SyncPulling] so the UI can show a
///   different label without overloading "syncing".
/// - [SyncPushing]: a push is in flight (snapshot + upload).
/// - [SyncSynced]: most-recent cycle succeeded; `at` is the UTC moment
///   the engine emitted `synced`.
/// - [SyncFailed]: most-recent cycle failed (retries exhausted, parse
///   failure, version mismatch, or non-transient error). Queue rows
///   persist; the next trigger event will attempt again.
/// - [SyncAwaitingInitialPull]: the first-connect probe found a
///   non-empty remote file on a device whose `drive.last_pulled_at`
///   flag is null AND the merge has not yet opened the gate. Once
///   Story 4.3's merge runs successfully this state is no longer
///   reachable in practice (the merge opens the gate directly).
@freezed
sealed class SyncStatus with _$SyncStatus {
  const factory SyncStatus.idle() = SyncIdle;
  const factory SyncStatus.pulling() = SyncPulling;
  const factory SyncStatus.merging() = SyncMerging;
  const factory SyncStatus.pushing() = SyncPushing;
  const factory SyncStatus.synced({required DateTime at}) = SyncSynced;
  const factory SyncStatus.failed(AppError error) = SyncFailed;
  const factory SyncStatus.awaitingInitialPull() = SyncAwaitingInitialPull;
}
