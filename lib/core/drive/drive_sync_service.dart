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
import 'models/drive_bookmarks_file.dart';
import 'sync_status.dart';

/// Secure-storage key for the "have we ever pulled from this Drive
/// account" gate. Stored as an ISO 8601 UTC string; null/missing means
/// the gate is closed. Set by the first-connect probe (Story 4.2) or
/// by the first successful merge (Story 4.3).
const String kDriveLastPulledAtKey = 'drive.last_pulled_at';

/// The push half of the Drive sync engine (Story 4.2).
///
/// Owns:
///  * A broadcast `SyncStatus` stream (`watchStatus()`) that the UI
///    consumes via `syncStatusProvider`.
///  * A `push(fileId)` method that drains the local queue by uploading
///    a whole-snapshot to the remote `bookmarks.json` via Drive's
///    `files.update`.
///  * A one-time per-device-per-session first-connect probe that
///    decides whether to open or leave closed the `drive.last_pulled_at`
///    gate.
///
/// Does NOT own:
///  * Pull / merge / conflict resolution -- Story 4.3.
///  * Auto-trigger wiring (Riverpod debounce / lifecycle / auth-state
///    listeners) -- `drive_sync_providers.dart` does that.
///  * Connectivity detection -- Story 4.5.
///
/// Concurrency: a private in-flight future serialises concurrent
/// `push()` calls -- a second concurrent call awaits the first's
/// completion and returns the same Result, so exactly one upload
/// happens per "push window".
class DriveSyncService {
  DriveSyncService({
    required SyncQueueRepository queue,
    required DriveSnapshotBuilder snapshotBuilder,
    required DriveCredentialsStore credentials,
    required FlutterSecureStorage storage,
    required http.Client httpClient,
    DriveRetryPolicy retryPolicy = const DriveRetryPolicy(),
    DateTime Function() clock = _defaultClock,
  })  : _queue = queue,
        _snapshotBuilder = snapshotBuilder,
        _credentials = credentials,
        _storage = storage,
        _httpClient = httpClient,
        _retryPolicy = retryPolicy,
        _clock = clock;

  final SyncQueueRepository _queue;
  final DriveSnapshotBuilder _snapshotBuilder;
  final DriveCredentialsStore _credentials;
  final FlutterSecureStorage _storage;
  final http.Client _httpClient;
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
  bool _disposed = false;

  Stream<SyncStatus> watchStatus() => _statusController.stream;

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
  ///
  /// Returns:
  ///  * `Ok(null)` on success (or queue empty, or gate already open with
  ///    no work).
  ///  * `Err(SyncError('Initial merge required ...'))` when the push
  ///    gate is closed because the remote file has data and Story 4.3
  ///    has not yet merged it.
  ///  * `Err(NetworkError(...))` on retry-exhausted transient failures
  ///    or HTTP 4xx from Drive.
  ///  * `Err(SyncError(...))` on any other unexpected failure.
  Future<Result<void, AppError>> push({required String fileId}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _pushInternal(fileId);
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
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

  /// First-connect probe (Story 4.2). Reads the remote `bookmarks.json`
  /// once and, if all three arrays are empty, opens the push gate by
  /// writing `drive.last_pulled_at = now`. If the remote has data,
  /// leaves the gate closed (Story 4.3 will open it on first successful
  /// merge).
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

  Future<void> dispose() async {
    _disposed = true;
    await _statusController.close();
  }
}
