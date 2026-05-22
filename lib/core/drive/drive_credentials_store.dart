import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'drive_auth_service.dart' show DriveStorageKeys;
import 'oauth_config.dart';

/// Reads / writes the `drive.*` secure-storage keys as a
/// [`googleapis_auth.AccessCredentials`][1] value and produces
/// [AutoRefreshingAuthClient]s that transparently refresh expired access
/// tokens against Google's token endpoint.
///
/// Why this exists separately from `DriveAuthService`: 4.1's auth service
/// runs the one-shot OAuth flow with a hand-rolled `_BearerAuthClient`
/// (no refresh logic needed for a single-call lifetime). 4.2's sync
/// engine is long-lived and WILL see access-token expiry mid-session, so
/// the engine talks to Drive through `googleapis_auth`'s
/// [autoRefreshingClient] which observes 401s, swaps in a fresh access
/// token via the refresh token, and re-issues the original request.
///
/// The refresh side-effect (new access token + possibly new refresh
/// token) is captured via the client's `credentialUpdates` stream and
/// persisted back to secure storage so the next session starts with a
/// still-valid token (and so a forced re-auth dance after every app
/// restart is avoided).
///
/// [1]: https://pub.dev/documentation/googleapis_auth/latest/googleapis_auth/AccessCredentials-class.html
class DriveCredentialsStore {
  DriveCredentialsStore({
    required FlutterSecureStorage storage,
    required String clientId,
    required String clientSecret,
  })  : _storage = storage,
        _clientId = clientId,
        _clientSecret = clientSecret;

  final FlutterSecureStorage _storage;
  final String _clientId;
  final String _clientSecret;

  /// Read current credentials from secure storage, or null if any
  /// required key is missing (the four token-related keys are
  /// all-or-nothing). A missing expiry string is treated as no-creds
  /// rather than as a bad parse; either way the caller falls back to
  /// re-auth.
  Future<AccessCredentials?> read() async {
    final accessToken = await _storage.read(key: DriveStorageKeys.accessToken);
    final refreshToken =
        await _storage.read(key: DriveStorageKeys.refreshToken);
    final expiresAtStr = await _storage.read(key: DriveStorageKeys.expiresAt);
    if (accessToken == null || refreshToken == null || expiresAtStr == null) {
      return null;
    }
    DateTime expiresAt;
    try {
      expiresAt = DateTime.parse(expiresAtStr).toUtc();
    } catch (_) {
      return null;
    }
    return AccessCredentials(
      AccessToken('Bearer', accessToken, expiresAt),
      refreshToken,
      const [kDriveAppDataScope],
    );
  }

  /// Persist refreshed credentials to secure storage. Called once per
  /// successful refresh by [authenticatedClient]'s
  /// `credentialUpdates` subscription. Google occasionally rotates the
  /// refresh token; when it does, [AccessCredentials.refreshToken] is
  /// non-null and we write the new value too.
  Future<void> writeRefreshed(AccessCredentials creds) async {
    await _storage.write(
      key: DriveStorageKeys.accessToken,
      value: creds.accessToken.data,
    );
    await _storage.write(
      key: DriveStorageKeys.expiresAt,
      value: creds.accessToken.expiry.toUtc().toIso8601String(),
    );
    final refresh = creds.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.write(
        key: DriveStorageKeys.refreshToken,
        value: refresh,
      );
    }
  }

  /// Wrap [base] in an [AutoRefreshingAuthClient] using the current
  /// credentials from secure storage. Returns null if there are no
  /// credentials -- the caller should treat this as a re-auth
  /// requirement.
  ///
  /// The returned client owns a subscription to `credentialUpdates`;
  /// closing the client unsubscribes and stops persisting refreshes.
  /// Callers MUST `client.close()` when done.
  ///
  /// [base] is wrapped in a non-closing shim before being handed to
  /// `autoRefreshingClient`. googleapis_auth's `AutoRefreshingClient`
  /// inherits `DelegatingClient`'s default `closeUnderlyingClient: true`
  /// (the convenience `autoRefreshingClient(...)` function doesn't
  /// expose the flag), so `authClient.close()` would otherwise tear
  /// down our singleton `httpClientProvider` instance — every cycle
  /// would burn the shared client and the next OAuth POST / Drive
  /// request would fail with "Client is already closed".
  Future<AutoRefreshingAuthClient?> authenticatedClient(http.Client base) async {
    final creds = await read();
    if (creds == null) return null;
    final client = autoRefreshingClient(
      ClientId(_clientId, _clientSecret),
      creds,
      _NonClosingHttpClient(base),
    );
    // Persist refreshed creds. `credentialUpdates` fires after every
    // successful refresh; the listen runs on the client's lifetime.
    client.credentialUpdates.listen(
      (updated) async {
        try {
          await writeRefreshed(updated);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'DriveCredentialsStore: failed to persist refreshed creds: $e',
            );
          }
          // Best-effort; a failed persist means the next session re-auths.
        }
      },
      onError: (Object _) {
        // Stream itself does not surface refresh failures here -- those
        // throw from `client.send`. Suppress any spurious stream errors.
      },
    );
    return client;
  }
}

/// Forwards every `send` to [_inner] and no-ops `close`. Used to hand a
/// shared singleton [http.Client] to googleapis_auth's
/// `autoRefreshingClient` without letting the auth client claim
/// ownership of its lifetime — see [DriveCredentialsStore.authenticatedClient].
class _NonClosingHttpClient extends http.BaseClient {
  _NonClosingHttpClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    // Intentionally a no-op. The wrapped client is owned by
    // `httpClientProvider` and closed only on container teardown.
  }
}
