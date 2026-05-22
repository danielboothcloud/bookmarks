import 'dart:convert';

import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_credentials_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Counts `send` and `close` invocations. Throws on `send` after
/// `close` — mirroring `IOClient`'s "Client is already closed" behaviour
/// that production code would surface.
class _TrackingClient extends http.BaseClient {
  int sendCount = 0;
  int closeCount = 0;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('Client is already closed.', request.url);
    }
    sendCount++;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    closeCount++;
    _closed = true;
    super.close();
  }
}

class _InMemorySecureStorage implements FlutterSecureStorage {
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

void main() {
  late _InMemorySecureStorage storage;
  late DriveCredentialsStore credStore;

  setUp(() {
    storage = _InMemorySecureStorage();
    credStore = DriveCredentialsStore(
      storage: storage,
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
    );
  });

  test('read returns null when any required key is missing', () async {
    // No keys set.
    expect(await credStore.read(), isNull);

    storage.store[DriveStorageKeys.accessToken] = 'a';
    expect(await credStore.read(), isNull,
        reason: 'missing refresh_token + expires_at -> null');

    storage.store[DriveStorageKeys.refreshToken] = 'r';
    expect(await credStore.read(), isNull,
        reason: 'missing expires_at -> null');
  });

  test('read returns valid AccessCredentials when all keys are present',
      () async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
    storage.store[DriveStorageKeys.accessToken] = 'access-1';
    storage.store[DriveStorageKeys.refreshToken] = 'refresh-1';
    storage.store[DriveStorageKeys.expiresAt] = expiresAt.toIso8601String();

    final creds = await credStore.read();
    expect(creds, isNotNull);
    expect(creds!.accessToken.type, 'Bearer');
    expect(creds.accessToken.data, 'access-1');
    expect(creds.refreshToken, 'refresh-1');
    expect(creds.scopes, contains(contains('drive.appdata')));
  });

  test('read returns null when expires_at is unparseable', () async {
    storage.store[DriveStorageKeys.accessToken] = 'a';
    storage.store[DriveStorageKeys.refreshToken] = 'r';
    storage.store[DriveStorageKeys.expiresAt] = 'not-a-date';
    expect(await credStore.read(), isNull);
  });

  test('writeRefreshed persists access token + expiry', () async {
    final newExpiry = DateTime.utc(2026, 6, 1);
    final newCreds = AccessCredentials(
      AccessToken('Bearer', 'access-2', newExpiry),
      'refresh-2',
      const ['https://www.googleapis.com/auth/drive.appdata'],
    );

    await credStore.writeRefreshed(newCreds);

    expect(storage.store[DriveStorageKeys.accessToken], 'access-2');
    expect(storage.store[DriveStorageKeys.expiresAt],
        newExpiry.toUtc().toIso8601String());
    expect(storage.store[DriveStorageKeys.refreshToken], 'refresh-2');
  });

  test('writeRefreshed preserves existing refresh token when new one is null',
      () async {
    storage.store[DriveStorageKeys.refreshToken] = 'original-refresh';

    final newCreds = AccessCredentials(
      AccessToken('Bearer', 'access-3',
          DateTime.now().toUtc().add(const Duration(hours: 1))),
      null,
      const ['https://www.googleapis.com/auth/drive.appdata'],
    );
    await credStore.writeRefreshed(newCreds);

    expect(storage.store[DriveStorageKeys.refreshToken], 'original-refresh');
    expect(storage.store[DriveStorageKeys.accessToken], 'access-3');
  });

  test('authenticatedClient returns null when no credentials are stored',
      () async {
    final base = MockClient((req) async => http.Response('', 200));
    expect(await credStore.authenticatedClient(base), isNull);
    base.close();
  });

  test('authenticatedClient returns a wrapped client when credentials exist',
      () async {
    storage.store[DriveStorageKeys.accessToken] = 'access-x';
    storage.store[DriveStorageKeys.refreshToken] = 'refresh-x';
    storage.store[DriveStorageKeys.expiresAt] = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();

    final base = MockClient((req) async => http.Response('{}', 200));
    final client = await credStore.authenticatedClient(base);
    expect(client, isNotNull);
    expect(client!.credentials.accessToken.data, 'access-x');
    client.close();
  });

  test(
      'authenticatedClient does NOT close the underlying base client when '
      'the auth client is closed (smoke regression — Story 4.5 reconnect)',
      () async {
    // googleapis_auth's autoRefreshingClient(...) doesn't expose
    // closeUnderlyingClient and inherits DelegatingClient's default of
    // `true`. Without the wrapping shim in
    // DriveCredentialsStore.authenticatedClient, this test's second
    // .send() would throw "Client is already closed" — exactly the
    // smoke failure that surfaced on reconnect after Story 4.5.
    storage.store[DriveStorageKeys.accessToken] = 'access-x';
    storage.store[DriveStorageKeys.refreshToken] = 'refresh-x';
    storage.store[DriveStorageKeys.expiresAt] = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();

    // A real http.Client subclass — not MockClient — so .close() is
    // observable and reusing-after-close throws like the production
    // IOClient does. Use a counting BaseClient so we can also verify
    // both send paths landed.
    final base = _TrackingClient();

    // First auth-client lifecycle: get → close.
    final first = await credStore.authenticatedClient(base);
    expect(first, isNotNull);
    await first!.get(Uri.parse('https://example.com/one'));
    first.close();

    expect(base.closeCount, 0,
        reason: 'closing the auth client must NOT close the base client');

    // Second auth-client lifecycle on the SAME base must still succeed.
    final second = await credStore.authenticatedClient(base);
    expect(second, isNotNull);
    await second!.get(Uri.parse('https://example.com/two'));
    second.close();

    expect(base.sendCount, 2,
        reason: 'both .get() calls reached the underlying base client');
    expect(base.closeCount, 0,
        reason: 'base client survived both auth-client lifecycles');

    base.close();
  });

  test('authenticatedClient persists refreshed tokens via the '
      'credentialUpdates subscription', () async {
    // Surprise log entry #3: googleapis_auth ^1.6.0 exposes refresh
    // events through `AutoRefreshingAuthClient.credentialUpdates`, not a
    // constructor callback. This test forces a refresh by seeding an
    // expired credential, stubs the OAuth token endpoint, and asserts
    // secure storage receives the new tokens. If a future package bump
    // renames or removes credentialUpdates, this test fails — instead
    // of silently regressing every session-resume.
    storage.store[DriveStorageKeys.accessToken] = 'old-access';
    storage.store[DriveStorageKeys.refreshToken] = 'old-refresh';
    storage.store[DriveStorageKeys.expiresAt] = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5)) // expired -> forces refresh
        .toIso8601String();

    final base = MockClient((req) async {
      final url = req.url;
      // Token endpoint returns a fresh access token + rotated refresh
      // token (the rare-but-supported Google behaviour).
      if (url.host == 'oauth2.googleapis.com' &&
          url.path.endsWith('/token')) {
        final body = jsonEncode({
          'access_token': 'new-access',
          'refresh_token': 'rotated-refresh',
          'expires_in': 3600,
          'token_type': 'Bearer',
        });
        return http.Response(body, 200,
            headers: const {'content-type': 'application/json'});
      }
      // Any other request returns an OK body so the underlying call
      // resolves cleanly after the refresh-then-retry dance.
      return http.Response('{}', 200,
          headers: const {'content-type': 'application/json'});
    });

    final client = await credStore.authenticatedClient(base);
    expect(client, isNotNull);

    // Make a request that triggers a pre-emptive refresh because
    // credentials are expired.
    await client!.get(Uri.parse('https://www.googleapis.com/drive/v3/about'));

    // Give the credentialUpdates microtask a chance to deliver.
    await Future<void>.delayed(Duration.zero);

    expect(storage.store[DriveStorageKeys.accessToken], 'new-access',
        reason: 'refresh callback must persist new access token');
    // Note: googleapis_auth ^1.6.0 deliberately preserves the original
    // refresh_token even when the OAuth response contains a rotated one
    // (see refreshCredentials in googleapis_auth/src/auth_functions.dart).
    // We assert the stored refresh_token is whatever the AccessCredentials
    // object exposes — which is the original — proving the conditional
    // rotation write in DriveCredentialsStore.writeRefreshed runs.
    expect(storage.store[DriveStorageKeys.refreshToken], 'old-refresh',
        reason: 'googleapis_auth preserves the original refresh token; '
            'writeRefreshed persists whatever AccessCredentials exposes');

    client.close();
  });
}
