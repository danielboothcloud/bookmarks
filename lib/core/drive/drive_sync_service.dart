import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../database/sync_queue_repository.dart';
import '../error/app_error.dart';
import '../error/result.dart';
import 'drive_credentials_store.dart';
import 'drive_file_service.dart' show DriveRetryPolicy;
import 'drive_snapshot_builder.dart';
import 'merge_applier.dart';
import 'models/drive_bookmarks_file.dart';
import 'sync_status.dart';

/// Secure-storage key for the "have we ever pulled from this Drive
/// account" gate. Stored as an ISO 8601 UTC string; null/missing means
/// the gate is closed. Set by the first-connect probe (Story 4.2) or
/// by the first successful merge (Story 4.3).
const String kDriveLastPulledAtKey = 'drive.last_pulled_at';

/// The Drive sync engine (Story 4.2 push half; Story 4.3 pull half).
///
/// Owns:
///  * A broadcast `SyncStatus` stream (`watchStatus()`) that the UI
///    consumes via `syncStatusProvider`.
///  * `push(fileId)` — drains the local queue by uploading a
///    whole-snapshot to `bookmarks.json` via Drive's `files.update`.
///  * `pull(fileId)` — downloads `bookmarks.json` and applies the
///    per-record LWW merge via [MergeApplier]; opens the push gate
///    on first successful merge (Story 4.3).
///  * `sync(fileId)` — unified pull-then-push cycle. Short-circuits
///    push if pull fails.
///  * A first-connect probe that opens the push gate on an empty
///    remote without going through a merge transaction. Story 4.3
///    demotes this from "the gate decision lives here" to "the
///    fast-path optimization for the empty-remote case" — the
///    primary gate-opening path is now [pull] + [MergeApplier.apply].
///    The probe stays because (a) it shields against a degenerate
///    remote-empty case where merge would still run but produce
///    zero writes, and (b) removing it would force a rework of the
///    4.2 tests that exercise it. See `_pushInternal` for the
///    probe's invocation site.
///
/// Does NOT own:
///  * Auto-trigger wiring (Riverpod debounce / lifecycle / auth-state
///    listeners) -- `drive_sync_providers.dart` does that.
///  * Connectivity detection -- Story 4.5.
///
/// Concurrency: a single in-flight future serialises concurrent
/// `pull`, `push`, and `sync` calls — a second concurrent call awaits
/// the first's completion and returns the same Result. This is the
/// "one cycle at a time" semantics the orchestrator relies on.
class DriveSyncService {
  DriveSyncService({
    required SyncQueueRepository queue,
    required DriveSnapshotBuilder snapshotBuilder,
    required DriveCredentialsStore credentials,
    required FlutterSecureStorage storage,
    required http.Client httpClient,
    required MergeApplier mergeApplier,
    DriveRetryPolicy retryPolicy = const DriveRetryPolicy(),
    DateTime Function() clock = _defaultClock,
  })  : _queue = queue,
        _snapshotBuilder = snapshotBuilder,
        _credentials = credentials,
        _storage = storage,
        _httpClient = httpClient,
        _mergeApplier = mergeApplier,
        _retryPolicy = retryPolicy,
        _clock = clock;

  final SyncQueueRepository _queue;
  final DriveSnapshotBuilder _snapshotBuilder;
  final DriveCredentialsStore _credentials;
  final FlutterSecureStorage _storage;
  final http.Client _httpClient;
  final MergeApplier _mergeApplier;
  final DriveRetryPolicy _retryPolicy;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  // sync: true so listeners receive emits synchronously inside _emit(),
  // making the stream observable in tests without explicit microtask
  // draining. Production listeners (UI providers, integration tests) do
  // light work in their handlers; no heavy synchronous work runs on this
  // stream.
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast(sync: true);
  SyncStatus _lastEmitted = const SyncStatus.idle();
  DateTime? _lastSyncedAt;
  Future<Result<void, AppError>>? _inFlight;
  _InFlightKind? _inFlightKind;
  bool _disposed = false;

  /// Status stream that prepends [currentStatus] for late subscribers.
  ///
  /// `StreamController.broadcast(sync: true)` does not replay past emits,
  /// so a subscriber that attaches after the engine's first `_emit()` (or
  /// before any emit has happened) would otherwise observe nothing until
  /// the next status change — the `SyncStatusIndicator` would render
  /// `SizedBox.shrink()` instead of "Synced with Drive" on first paint.
  /// Yielding [currentStatus] as the first event closes that gap without
  /// changing broadcast semantics for follow-on emits.
  Stream<SyncStatus> watchStatus() async* {
    yield _lastEmitted;
    yield* _statusController.stream;
  }

  /// Snapshot of the most-recent status emitted on the stream. Used by
  /// new subscribers that miss the broadcast.
  SyncStatus get currentStatus => _lastEmitted;

  void _emit(SyncStatus status) {
    if (_disposed) return;
    _lastEmitted = status;
    _statusController.add(status);
  }

  /// Drains the queue by serializing the local state to a v1 envelope
  /// and uploading it to `bookmarks.json` in `appDataFolder`. Idempotent
  /// when there's nothing to push.
  Future<Result<void, AppError>> push({required String fileId}) {
    return _coalesce(_InFlightKind.push, () => _pushInternal(fileId));
  }

  /// Downloads the remote `bookmarks.json`, parses the v1 envelope,
  /// and applies a per-record LWW merge via [MergeApplier]. On success
  /// opens the push gate by writing `drive.last_pulled_at = now()`.
  ///
  /// Returns:
  ///  * `Ok(null)` on a successful merge (including the empty-plan
  ///    no-op case).
  ///  * `Err(AuthError(...))` if no Drive credentials are available
  ///    (no retry; the caller should re-auth).
  ///  * `Err(SyncError('Unsupported Drive file version: ...'))` if
  ///    the remote's `version` field is not 1. The gate is NOT
  ///    opened; the local DB is untouched.
  ///  * `Err(SyncError('Malformed Drive response: ...'))` on a JSON
  ///    parse failure.
  ///  * `Err(NetworkError(...))` on retry-exhausted transient
  ///    failures or HTTP 4xx (other than 429, which is retried).
  ///  * `Err(StorageError(...))` if the merge transaction rolls
  ///    back.
  Future<Result<void, AppError>> pull({required String fileId}) {
    return _coalesce(_InFlightKind.pull, () => _pullInternal(fileId));
  }

  /// Unified pull-then-push cycle. Pulls first (so a merge runs and
  /// the gate decision is settled), then — only on pull success —
  /// drains the queue via push. A failed pull returns immediately
  /// without attempting push, because pushing a local snapshot atop
  /// a remote we couldn't read risks overwriting another device's
  /// data.
  Future<Result<void, AppError>> sync({required String fileId}) {
    return _coalesce(_InFlightKind.sync, () => _syncInternal(fileId));
  }

  // Coalesces concurrent public-method calls.
  //
  // Coalescing rules:
  //   - sync-onto-sync, pull-onto-pull, push-onto-push: second caller
  //     joins the in-flight future.
  //   - pull-onto-sync, push-onto-sync: a sync is the broader cycle;
  //     the narrower caller joins.
  //   - sync-onto-pull or sync-onto-push: the in-flight narrower cycle
  //     does NOT cover the sync's missing leg. Wait for the in-flight
  //     to finish, then run a fresh sync.
  Future<Result<void, AppError>> _coalesce(
    _InFlightKind kind,
    Future<Result<void, AppError>> Function() body,
  ) async {
    while (_inFlight != null) {
      final running = _inFlightKind;
      if (running == _InFlightKind.sync || running == kind) {
        return await _inFlight!;
      }
      // Different narrower cycle is running; wait it out and re-check.
      await _inFlight;
    }
    final future = body();
    _inFlight = future;
    _inFlightKind = kind;
    try {
      return await future;
    } finally {
      _inFlight = null;
      _inFlightKind = null;
    }
  }

  Future<Result<void, AppError>> _syncInternal(String fileId) async {
    final pullResult = await _pullInternal(fileId, emitSyncedOnSuccess: false);
    if (pullResult is Err<void, AppError>) {
      return pullResult;
    }
    return _pushInternal(fileId);
  }

  Future<Result<void, AppError>> _pullInternal(
    String fileId, {
    bool emitSyncedOnSuccess = true,
  }) async {
    try {
      _emit(const SyncStatus.pulling());

      final authClient = await _credentials.authenticatedClient(_httpClient);
      if (authClient == null) {
        const err = AuthError('No Drive credentials available');
        _emit(const SyncStatus.failed(err));
        return const Err<void, AppError>(err);
      }

      DriveBookmarksFile remote;
      try {
        final media = await _retryPolicy.run(
          'drive.files.get',
          () => drive.DriveApi(authClient).files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              ),
        ) as drive.Media;
        final body = await media.stream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        final text = utf8.decode(body);
        remote = DriveBookmarksFile.fromJson(
            jsonDecode(text) as Map<String, dynamic>);
      } finally {
        authClient.close();
      }

      if (remote.version != 1) {
        final err = SyncError(
          'Unsupported Drive file version: ${remote.version}',
        );
        _emit(SyncStatus.failed(err));
        return Err<void, AppError>(err);
      }

      // Capture the gate state BEFORE the merge so the engine knows
      // whether to treat "missing from remote" as a deletion. Without
      // this, an offline-created local record on a fresh device would
      // be wiped on first sync (we can't distinguish "the other
      // device deleted it" from "we never pushed it").
      //
      // Also capture the timestamp itself (parsed to ms) so the merge
      // engine's symmetric tombstone-less heuristic can tell whether a
      // remote record predates our last pull (meaning we already saw
      // it and deleted it locally — don't resurrect on the next
      // upsert).
      final lastPulledAtRaw =
          await _storage.read(key: kDriveLastPulledAtKey);
      final hasEverSynced = lastPulledAtRaw != null;
      final lastPulledAtMs = lastPulledAtRaw == null
          ? null
          : DateTime.parse(lastPulledAtRaw).toUtc().millisecondsSinceEpoch;

      _emit(const SyncStatus.merging());

      final mergeResult = await _mergeApplier.apply(
        remote,
        hasEverSynced: hasEverSynced,
        lastPulledAtMs: lastPulledAtMs,
      );
      if (mergeResult is Err<void, AppError>) {
        _emit(SyncStatus.failed(mergeResult.error));
        return mergeResult;
      }

      // Gate-opening write happens AFTER the merge commits. A storage
      // write failure leaves the local DB with merged data but
      // `last_pulled_at` still null — surface as Err so the caller
      // (and UI) doesn't believe the cycle succeeded; the next pull
      // will retry the timestamp write idempotently.
      try {
        await _storage.write(
          key: kDriveLastPulledAtKey,
          value: _clock().toIso8601String(),
        );
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint(
            'DriveSyncService.pull: gate-open storage write failed: '
            '$e\n$stack',
          );
        }
        final err = StorageError('Failed to open sync gate: $e');
        _emit(SyncStatus.failed(err));
        return Err<void, AppError>(err);
      }

      _lastSyncedAt = _clock();
      if (emitSyncedOnSuccess) {
        _emit(SyncStatus.synced(at: _lastSyncedAt!));
      }
      return const Ok<void, AppError>(null);
    } catch (error, stack) {
      final mapped = _mapError(error);
      if (kDebugMode) {
        debugPrint('DriveSyncService.pull failed: $error\n$stack');
      }
      _emit(SyncStatus.failed(mapped));
      return Err<void, AppError>(mapped);
    }
  }

  Future<Result<void, AppError>> _pushInternal(String fileId) async {
    try {
      // Push gate: closed unless `drive.last_pulled_at` is non-null.
      final lastPulled = await _storage.read(key: kDriveLastPulledAtKey);
      if (lastPulled == null) {
        final gateOpened = await _firstConnectProbe(fileId);
        if (!gateOpened) {
          _emit(const SyncStatus.awaitingInitialPull());
          return const Err<void, AppError>(
            SyncError('Initial merge required — pending Story 4.3'),
          );
        }
      }

      // Drain queue snapshot. If nothing pending, no-op.
      final rows = await _queue.drain();
      if (rows.isEmpty) {
        // Preserve "synced(at:)" if we have one; otherwise emit idle.
        if (_lastSyncedAt != null) {
          _emit(SyncStatus.synced(at: _lastSyncedAt!));
        } else {
          _emit(const SyncStatus.idle());
        }
        return const Ok<void, AppError>(null);
      }

      _emit(const SyncStatus.pushing());

      final file = await _snapshotBuilder.build();
      final jsonBytes = utf8.encode(jsonEncode(file.toJson()));

      // Each `authenticatedClient` call subscribes to its own
      // `credentialUpdates` stream and closes it on `client.close()`. If
      // the gate-opening first-connect probe ran above, this is the
      // second such subscription within the same `push()` call. Both are
      // short-lived (built + closed inside try/finally) so they never
      // overlap a token-refresh window for the same call site; the only
      // risk is a Google-side refresh-token rotation happening between
      // the probe's GET and this PATCH, in which case `writeRefreshed`
      // would persist whichever subscription's update lands last (a no-
      // op equivalence at the wire level — both subs persist identical
      // values).
      final authClient = await _credentials.authenticatedClient(_httpClient);
      if (authClient == null) {
        const err = AuthError('No Drive credentials available');
        _emit(const SyncStatus.failed(err));
        return const Err<void, AppError>(err);
      }

      try {
        await _retryPolicy.run('drive.files.update', () async {
          final api = drive.DriveApi(authClient);
          final media = drive.Media(
            Stream<List<int>>.value(jsonBytes),
            jsonBytes.length,
          );
          return api.files
              .update(drive.File(), fileId, uploadMedia: media);
        });
      } finally {
        authClient.close();
      }

      await _queue.deleteByIds(rows.map((r) => r.id).toList());
      _lastSyncedAt = _clock();
      _emit(SyncStatus.synced(at: _lastSyncedAt!));
      return const Ok<void, AppError>(null);
    } catch (error, stack) {
      final mapped = _mapError(error);
      if (kDebugMode) {
        debugPrint('DriveSyncService.push failed: $error\n$stack');
      }
      _emit(SyncStatus.failed(mapped));
      return Err<void, AppError>(mapped);
    }
  }

  /// First-connect probe (Story 4.2, demoted in Story 4.3). Reads the
  /// remote `bookmarks.json` once and, if all three arrays are empty,
  /// opens the push gate by writing `drive.last_pulled_at = now`. If
  /// the remote has data, leaves the gate closed (Story 4.3's merge
  /// path opens it on the first successful merge).
  ///
  /// Now only reachable via direct `push()` calls; `sync()` uses the
  /// merge path which opens the gate from `_pullInternal` on success.
  /// Kept as a fast-path optimization for the empty-remote case and
  /// to preserve 4.2's test invariants.
  ///
  /// Returns true if the gate is now open; false otherwise.
  Future<bool> _firstConnectProbe(String fileId) async {
    final authClient = await _credentials.authenticatedClient(_httpClient);
    if (authClient == null) {
      throw const AuthError('No Drive credentials available for probe');
    }
    try {
      final api = drive.DriveApi(authClient);
      final media = await _retryPolicy.run(
        'drive.files.get',
        () => api.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ),
      ) as drive.Media;
      final body = await media.stream
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      final text = utf8.decode(body);
      final remote =
          DriveBookmarksFile.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (remote.bookmarks.isEmpty &&
          remote.folders.isEmpty &&
          remote.tags.isEmpty) {
        await _storage.write(
          key: kDriveLastPulledAtKey,
          value: _clock().toIso8601String(),
        );
        return true;
      }
      return false;
    } finally {
      authClient.close();
    }
  }

  AppError _mapError(Object error) {
    if (error is AuthError) return error;
    if (error is drive.DetailedApiRequestError) {
      final status = error.status ?? 0;
      if (status == 401 || status == 403) {
        return AuthError('Drive $status');
      }
      return NetworkError('Drive $status');
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return NetworkError(error.runtimeType.toString());
    }
    if (error is FormatException) {
      return SyncError('Malformed Drive response: ${error.message}');
    }
    return SyncError(error.toString());
  }

  /// Clears in-memory state without closing the broadcast stream.
  /// Used by Story 4.5's disconnect flow so a future reconnect starts
  /// from a clean baseline (no zombie `SyncSynced(at: ...)`).
  ///
  /// If a cycle is in-flight, awaits its natural completion before
  /// emitting `SyncIdle` (so the reset's terminal emit isn't a target
  /// for a subsequent terminal emit from the in-flight cycle).
  /// Cancelling mid-flight would require threading a `CancelToken`
  /// through the engine — out of scope for 4.5; the disconnect path is
  /// rare and the overlap is bounded by the in-flight HTTP request.
  ///
  /// Does NOT close `_statusController` — subscribers stay live across
  /// disconnect/reconnect cycles. Distinct from [dispose] in that
  /// regard.
  Future<void> reset() async {
    final inFlight = _inFlight;
    if (inFlight != null) {
      await inFlight;
    }
    _lastSyncedAt = null;
    _emit(const SyncStatus.idle());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _statusController.close();
  }
}

/// Marks which kind of cycle currently owns the `_inFlight` slot.
/// Used by [DriveSyncService._coalesce] to decide whether a newly
/// arriving call should join the running cycle or wait it out.
enum _InFlightKind { pull, push, sync }
