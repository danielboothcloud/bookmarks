import 'package:freezed_annotation/freezed_annotation.dart';

import '../error/app_error.dart';

part 'sync_status.freezed.dart';

/// Runtime state of the Drive sync engine. Emitted on
/// `DriveSyncService.watchStatus()`; surfaced to the UI via
/// `syncStatusProvider`.
///
/// Story 4.2 ships the data side (this sealed type and its five variants)
/// plus the minimum presentation (`SyncStatusIndicator`'s textual labels).
/// Story 4.4 will layer the full green/amber/grey state machine on top
/// without changing this type.
///
/// State semantics:
/// - [SyncIdle]: engine has no pending work and has not run a push this
///   session.
/// - [SyncPushing]: a push is in flight (snapshot + upload).
/// - [SyncSynced]: most-recent push succeeded; `at` is the UTC moment
///   the engine emitted `synced`.
/// - [SyncFailed]: most-recent push failed (retries exhausted or
///   non-transient error). Queue rows persist; the next push trigger
///   will attempt again.
/// - [SyncAwaitingInitialPull]: the first-connect probe found a non-empty
///   remote file on a device whose `drive.last_pulled_at` flag is null.
///   The engine refuses to push (which would overwrite another device's
///   data) until Story 4.3 lands and completes the initial merge.
@freezed
sealed class SyncStatus with _$SyncStatus {
  const factory SyncStatus.idle() = SyncIdle;
  const factory SyncStatus.pushing() = SyncPushing;
  const factory SyncStatus.synced({required DateTime at}) = SyncSynced;
  const factory SyncStatus.failed(AppError error) = SyncFailed;
  const factory SyncStatus.awaitingInitialPull() = SyncAwaitingInitialPull;
}
