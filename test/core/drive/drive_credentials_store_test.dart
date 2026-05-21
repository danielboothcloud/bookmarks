import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_credentials_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
