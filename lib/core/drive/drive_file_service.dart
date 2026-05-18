import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'oauth_config.dart';

/// Thin wrapper around Drive v3's `files.list` + `files.create` for the
/// `appDataFolder` space. Holds no auth state of its own — the caller
/// (typically [DriveAuthService.connect]) passes in a freshly-issued
/// access token.
///
/// **Why a hand-rolled bearer wrapper instead of `googleapis_auth`'s
/// `AuthClient`.** `AuthClient` requires a fully-built
/// `AccessCredentials` and is designed for the lazy-refresh flow that
/// Story 4.2 will use. For 4.1's one-shot bookmarks-file-ensure, we
/// have a fresh access token in hand from the token exchange — ~1 hour
/// TTL, used within seconds of issuance. Story 4.2 introduces the
/// full `AccessCredentials` + auto-refresh wrapper.
class DriveFileService {
  DriveFileService({
    required http.Client httpClient,
    DriveRetryPolicy retryPolicy = const DriveRetryPolicy(),
  })  : _httpClient = httpClient,
        _retry = retryPolicy;

  final http.Client _httpClient;
  final DriveRetryPolicy _retry;

  /// Returns the Drive file ID of `bookmarks.json` in `appDataFolder`.
  /// Creates an empty file (with the v1 schema envelope) if none
  /// exists. Idempotent: safe to call on every connect.
  Future<String> ensureBookmarksFile({required String accessToken}) async {
    final authClient = _BearerAuthClient(_httpClient, accessToken);
    try {
      final driveApi = drive.DriveApi(authClient);
      final list = await _retry.run(
        'files.list',
        () => driveApi.files.list(
          spaces: kAppDataSpace,
          q: "name = '$kBookmarksFileName'",
          $fields: 'files(id, modifiedTime)',
          orderBy: 'modifiedTime desc',
        ),
      );
      final files = list.files ?? const <drive.File>[];
      if (files.isNotEmpty) {
        if (files.length > 1) {
          // Defensive — should be impossible, but if it ever happens we
          // pick the most-recently-modified (the orderBy above
          // guarantees that's `files.first`) and leave the rest alone.
          // Deletion semantics deferred until we know they exist in
          // the wild.
          if (kDebugMode) {
            debugPrint(
              'DriveFileService: ${files.length} bookmarks.json files in '
              'appDataFolder; using most-recently-modified id=${files.first.id}',
            );
          }
        }
        final id = files.first.id;
        if (id == null) {
          throw const FormatException(
            'Drive returned a file entry with null id',
          );
        }
        return id;
      }

      // No remote file yet — create an empty one with the canonical
      // v1 envelope so Story 4.3's reader doesn't need a special
      // first-launch code path. The body is regenerated on each retry
      // so a fresh `lastModified` timestamp lands on the file Drive
      // ultimately accepts.
      final created = await _retry.run(
        'files.create',
        () {
          final body = utf8.encode(_emptyBookmarksJson());
          final media = drive.Media(
            Stream<List<int>>.value(body),
            body.length,
          );
          return driveApi.files.create(
            drive.File()
              ..name = kBookmarksFileName
              ..parents = const [kAppDataSpace],
            uploadMedia: media,
          );
        },
      );
      final id = created.id;
      if (id == null) {
        throw const FormatException(
          'Drive returned null id for created file',
        );
      }
      return id;
    } finally {
      authClient.close();
    }
  }

  static String _emptyBookmarksJson() => jsonEncode({
        'version': 1,
        'lastModified': DateTime.now().toUtc().toIso8601String(),
        'bookmarks': const <Object>[],
        'folders': const <Object>[],
        'tags': const <Object>[],
      });
}

/// Retry policy for Drive REST calls. Matches the architecture's
/// "exponential backoff, 3 retries, max 30s delay" rule. Retries fire
/// only on transient failures: 5xx, 429, and IO errors. 4xx (other
/// than 429) — including 401/403 — propagate immediately because the
/// caller needs to re-auth, not back off.
class DriveRetryPolicy {
  const DriveRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
  });

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  Future<T> run<T>(String label, Future<T> Function() body) async {
    var attempt = 0;
    var delay = initialDelay;
    final rng = Random();
    while (true) {
      attempt++;
      try {
        return await body();
      } catch (error) {
        if (attempt >= maxAttempts || !_isTransient(error)) rethrow;
        if (kDebugMode) {
          debugPrint(
            'DriveFileService.$label attempt $attempt failed ($error); '
            'retrying after ${delay.inMilliseconds}ms',
          );
        }
        // ±10% jitter so concurrent retries from a future sync engine
        // don't synchronise into a thundering herd.
        final jitterMs = (delay.inMilliseconds * (0.9 + rng.nextDouble() * 0.2))
            .toInt();
        await Future<void>.delayed(Duration(milliseconds: jitterMs));
        final next = delay * 2;
        delay = next > maxDelay ? maxDelay : next;
      }
    }
  }

  bool _isTransient(Object error) {
    if (error is drive.DetailedApiRequestError) {
      final s = error.status;
      return s == 429 || (s != null && s >= 500 && s < 600);
    }
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException;
  }
}

class _BearerAuthClient extends http.BaseClient {
  _BearerAuthClient(this._inner, this._token);
  final http.Client _inner;
  final String _token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() {
    // Do NOT close the inner client — it is owned by httpClientProvider.
  }
}
