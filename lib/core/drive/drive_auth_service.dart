import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../error/app_error.dart';
import 'drive_auth_state.dart';
import 'drive_file_service.dart';
import 'oauth_config.dart';

/// Storage keys. Namespaced under `drive.*` so future Drive-only
/// settings have a clear home, separate from any other secure-storage
/// usage (today there is none).
abstract final class DriveStorageKeys {
  static const accessToken = 'drive.access_token';
  static const refreshToken = 'drive.refresh_token';
  static const expiresAt = 'drive.expires_at'; // ISO 8601 string
  static const userEmail = 'drive.user_email';
  static const fileId = 'drive.bookmarks_file_id';
}

/// Thin abstraction over `package:url_launcher`'s top-level
/// [launcher.launchUrl] so tests can inject a recording fake.
abstract class UrlLauncher {
  Future<bool> launchUrl(
    Uri uri, {
    launcher.LaunchMode mode = launcher.LaunchMode.externalApplication,
  });
}

class _DefaultUrlLauncher implements UrlLauncher {
  const _DefaultUrlLauncher();

  @override
  Future<bool> launchUrl(
    Uri uri, {
    launcher.LaunchMode mode = launcher.LaunchMode.externalApplication,
  }) {
    return launcher.launchUrl(uri, mode: mode);
  }
}

/// Default callback timeout. Long enough that a user can step away
/// briefly, short enough that a forgotten flow doesn't hold a port
/// indefinitely.
const Duration kDefaultOAuthCallbackTimeout = Duration(minutes: 5);

/// One-shot OAuth + token-persist + bookmarks-file-ensure flow.
///
/// Mutates a [DriveAuthState] held outside the service (see
/// `DriveAuthNotifier` in `drive_auth_providers.dart`).
class DriveAuthService {
  DriveAuthService({
    required FlutterSecureStorage storage,
    required DriveFileService driveFileService,
    required http.Client httpClient,
    UrlLauncher urlLauncher = const _DefaultUrlLauncher(),
    Random? random,
  })  : _storage = storage,
        _driveFileService = driveFileService,
        _http = httpClient,
        _launcher = urlLauncher,
        _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final DriveFileService _driveFileService;
  final http.Client _http;
  final UrlLauncher _launcher;
  final Random _random;

  /// Resolve current auth state at startup. Returns [DriveAuthConnected]
  /// if all four token keys + the file id are present; otherwise
  /// [DriveAuthDisconnected]. Any read failure (rare keychain hiccup)
  /// is treated as disconnected — the user re-auths, which is safer
  /// than crashing the boot.
  Future<DriveAuthState> resolveInitialState() async {
    try {
      final accessToken = await _storage.read(key: DriveStorageKeys.accessToken);
      final refreshToken =
          await _storage.read(key: DriveStorageKeys.refreshToken);
      final expiresAt = await _storage.read(key: DriveStorageKeys.expiresAt);
      final email = await _storage.read(key: DriveStorageKeys.userEmail);
      final fileId = await _storage.read(key: DriveStorageKeys.fileId);
      if (accessToken == null ||
          refreshToken == null ||
          expiresAt == null ||
          email == null ||
          fileId == null) {
        return const DriveAuthState.disconnected();
      }
      return DriveAuthState.connected(email: email, fileId: fileId);
    } catch (_) {
      return const DriveAuthState.disconnected();
    }
  }

  /// Run the OAuth + ensure-file flow. Yields state transitions as a
  /// Stream so the Notifier can mirror them. Always terminates
  /// (connected | disconnected | failed).
  ///
  /// **Error mapping (Task 12).** Exceptions raised during the flow
  /// are caught at the boundary and mapped to typed [AppError]:
  ///
  /// | Caught                                                | Mapped to       |
  /// |-------------------------------------------------------|-----------------|
  /// | `SocketException`, `HttpException`, `TimeoutException`| `NetworkError`  |
  /// | `FormatException` (token JSON, id_token JWT)          | `AuthError`     |
  /// | `_OAuthHttpError` 401/403                             | `AuthError`     |
  /// | `_OAuthHttpError` 5xx                                 | `NetworkError`  |
  /// | `PlatformException` from `flutter_secure_storage`     | `StorageError`  |
  /// | Any other `Exception` / `Error`                       | `AuthError`     |
  ///
  /// User cancellation (closed tab, `error=access_denied`, timeout)
  /// is NOT an error — yields [DriveAuthDisconnected].
  Stream<DriveAuthState> connect({
    Duration callbackTimeout = kDefaultOAuthCallbackTimeout,
  }) async* {
    yield const DriveAuthState.connecting();

    HttpServer? server;
    final verifier = _generateCodeVerifier();
    final challenge = _computeChallenge(verifier);
    final state = _generateState();

    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri.parse('http://127.0.0.1:${server.port}/');

      final authUri = Uri.parse(kAuthEndpoint).replace(queryParameters: {
        'client_id': kOAuthClientId,
        'response_type': 'code',
        'scope': kDriveAppDataScope,
        'redirect_uri': redirectUri.toString(),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });

      await _launcher.launchUrl(authUri);

      HttpRequest? httpRequest;
      try {
        httpRequest = await server.first.timeout(callbackTimeout);
      } on TimeoutException {
        httpRequest = null;
      }

      if (httpRequest == null) {
        await server.close(force: true);
        server = null;
        yield const DriveAuthState.disconnected();
        return;
      }

      final params = httpRequest.uri.queryParameters;

      // User cancelled or denied consent.
      if (params['error'] != null) {
        await _respondHtml(httpRequest, _errorHtml, status: HttpStatus.ok);
        await server.close(force: true);
        server = null;
        yield const DriveAuthState.disconnected();
        return;
      }

      // CSRF / re-entry: state mismatch.
      if (params['state'] != state) {
        await _respondHtml(
          httpRequest,
          _stateMismatchHtml,
          status: HttpStatus.badRequest,
        );
        await server.close(force: true);
        server = null;
        yield const DriveAuthState.failed(
          AuthError('Invalid OAuth state'),
        );
        return;
      }

      final code = params['code'];
      if (code == null || code.isEmpty) {
        await _respondHtml(httpRequest, _errorHtml, status: HttpStatus.badRequest);
        await server.close(force: true);
        server = null;
        yield const DriveAuthState.failed(
          AuthError('Missing authorization code'),
        );
        return;
      }

      // Acknowledge the browser before doing any network work — keeps
      // the success page snappy even if the token POST is slow.
      await _respondHtml(httpRequest, _successHtml, status: HttpStatus.ok);
      await server.close(force: true);
      server = null;

      final tokenResponse = await _http.post(
        Uri.parse(kTokenEndpoint),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'client_id': kOAuthClientId,
          'client_secret': kOAuthClientSecret,
          'code_verifier': verifier,
        },
      );

      if (tokenResponse.statusCode >= 400) {
        throw _OAuthHttpError(tokenResponse.statusCode, tokenResponse.body);
      }

      final decoded = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final accessToken = decoded['access_token'] as String?;
      final refreshToken = decoded['refresh_token'] as String?;
      final expiresIn = decoded['expires_in'] as int?;
      final idToken = decoded['id_token'] as String?;

      if (accessToken == null || refreshToken == null || expiresIn == null) {
        throw const FormatException('Token response missing required fields');
      }

      final email = extractEmailFromIdToken(idToken) ?? 'Google account';
      final expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(seconds: expiresIn))
          .toIso8601String();

      await _storage.write(
        key: DriveStorageKeys.accessToken,
        value: accessToken,
      );
      await _storage.write(
        key: DriveStorageKeys.refreshToken,
        value: refreshToken,
      );
      await _storage.write(key: DriveStorageKeys.expiresAt, value: expiresAt);
      await _storage.write(key: DriveStorageKeys.userEmail, value: email);

      final fileId = await _driveFileService.ensureBookmarksFile(
        accessToken: accessToken,
      );
      await _storage.write(key: DriveStorageKeys.fileId, value: fileId);

      yield DriveAuthState.connected(email: email, fileId: fileId);
    } catch (error, stack) {
      if (server != null) {
        await server.close(force: true);
      }
      // Defensive cleanup so a half-completed flow can't leave the
      // app in a "tokens exist but no fileId" zombie state.
      await clearTokens();
      final mapped = _mapError(error);
      if (kDebugMode) {
        debugPrint('DriveAuthService.connect failed: $error\n$stack');
      }
      yield DriveAuthState.failed(mapped);
    }
  }

  /// Wipe tokens. Used on cleanup after [DriveAuthFailed] and (4.5)
  /// on user-initiated disconnect.
  Future<void> clearTokens() async {
    // Best-effort deletes; ignore individual failures so one stuck
    // key doesn't block the rest.
    for (final key in const [
      DriveStorageKeys.accessToken,
      DriveStorageKeys.refreshToken,
      DriveStorageKeys.expiresAt,
      DriveStorageKeys.userEmail,
      DriveStorageKeys.fileId,
    ]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // swallow
      }
    }
  }

  String _generateCodeVerifier() {
    const allowed =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List<String>.generate(
      64,
      (_) => allowed[_random.nextInt(allowed.length)],
    ).join();
  }

  String _computeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _generateState() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _respondHtml(
    HttpRequest request,
    String body, {
    required int status,
  }) async {
    final bytes = utf8.encode(body);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await request.response.close();
  }

  AppError _mapError(Object error) {
    if (error is _OAuthHttpError) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return AuthError('Token endpoint ${error.statusCode}');
      }
      if (error.statusCode >= 500 && error.statusCode < 600) {
        return NetworkError('Token endpoint ${error.statusCode}');
      }
      return AuthError('Token endpoint ${error.statusCode}');
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return NetworkError(error.toString());
    }
    if (error is FormatException) {
      return AuthError(error.message);
    }
    // PlatformException ships from flutter_secure_storage; we don't
    // import the package here, so type-test by name to avoid pulling
    // services as a direct dep of this file.
    if (error.runtimeType.toString() == 'PlatformException') {
      return StorageError(error.toString());
    }
    return AuthError(error.toString());
  }
}

/// Decode the `email` claim from an OAuth2 `id_token` (a JWT) without
/// signature verification. We trust the TLS channel to Google's token
/// endpoint; the email is for display only, never used for
/// authorization.
///
/// Returns null on any malformed input — caller falls back to a
/// synthesised display string ("Google account"). We do NOT request
/// the `openid email` scope (calm-utility: don't ask for what you
/// don't need), so id_token may be absent or carry no email claim,
/// and that's a normal path here.
@visibleForTesting
String? extractEmailFromIdToken(String? idToken) {
  if (idToken == null || idToken.isEmpty) return null;
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = parts[1];
    final padded = payload + ('=' * ((4 - payload.length % 4) % 4));
    final decoded = utf8.decode(base64Url.decode(padded));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final email = json['email'];
    if (email is String && email.isNotEmpty) return email;
    return null;
  } catch (_) {
    return null;
  }
}

class _OAuthHttpError implements Exception {
  _OAuthHttpError(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'OAuth HTTP $statusCode: $body';
}

// ---------------------------------------------------------------------------
// Localhost callback HTML (Task 14). Inline-CSS only — the browser
// tab renders this; loading external CSS would require either
// bundling assets or fetching from a CDN (network dependency for an
// offline-first app's auth flow — wrong). Background matches the
// app surface (#F5F4EF) for visual continuity when the user switches
// tabs back to the app.
// ---------------------------------------------------------------------------

const String _successHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Connected</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   Ubuntu, sans-serif;
      background: #F5F4EF;
      color: #2C2C2C;
      margin: 0;
      padding: 4rem 2rem;
      text-align: center;
    }
    p { font-size: 1rem; max-width: 24rem; margin: 0 auto; }
  </style>
</head>
<body>
  <p>Connected. You can close this tab and return to Bookmarks.</p>
</body>
</html>
''';

const String _errorHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Connection error</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   Ubuntu, sans-serif;
      background: #F5F4EF;
      color: #2C2C2C;
      margin: 0;
      padding: 4rem 2rem;
      text-align: center;
    }
    p { font-size: 1rem; max-width: 24rem; margin: 0 auto; }
  </style>
</head>
<body>
  <p>Couldn't complete connection. Return to Bookmarks and try again.</p>
</body>
</html>
''';

const String _stateMismatchHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Invalid state</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   Ubuntu, sans-serif;
      background: #F5F4EF;
      color: #2C2C2C;
      margin: 0;
      padding: 4rem 2rem;
      text-align: center;
    }
    p { font-size: 1rem; max-width: 24rem; margin: 0 auto; }
  </style>
</head>
<body>
  <p>Invalid state — close this window and retry from the app.</p>
</body>
</html>
''';
