import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart';
import 'package:bookmarks/core/drive/oauth_config.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/features/onboarding/presentation/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> store;
  _InMemoryStorage([Map<String, String>? seed]) : store = seed ?? {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map.of(store);

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store.containsKey(key);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DrivenLauncher implements UrlLauncher {
  Future<void> Function(Uri uri)? onLaunch;
  Uri? launched;

  @override
  Future<bool> launchUrl(
    Uri uri, {
    launcher.LaunchMode mode = launcher.LaunchMode.externalApplication,
  }) async {
    launched = uri;
    if (onLaunch != null) {
      unawaited(Future<void>(() => onLaunch!(uri)));
    }
    return true;
  }
}

class _FakeDriveFileService implements DriveFileService {
  final String fileId;
  String? lastToken;
  _FakeDriveFileService({this.fileId = 'integration-file-id'});

  @override
  Future<String> ensureBookmarksFile({required String accessToken}) async {
    lastToken = accessToken;
    return fileId;
  }
}

/// Build a router that mirrors the production redirect-and-welcome
/// structure but replaces post-auth routes with stubs so we don't pull
/// in the full bookmark/folder/tag streams (which require an in-memory
/// Drift database). The integration target here is the auth flow, not
/// the bookmark list.
GoRouter _buildTestRouter(ProviderContainer container) {
  final authRefresh = _AuthRefresh(container);
  return GoRouter(
    initialLocation: '/bookmarks',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final auth = container.read(driveAuthStateProvider);
      if (auth.isLoading) return null;
      final s = auth.value;
      final atWelcome = state.matchedLocation == AppRoutes.welcome;
      if (s is DriveAuthDisconnected ||
          s is DriveAuthConnecting ||
          s is DriveAuthFailed) {
        return atWelcome ? null : AppRoutes.welcome;
      }
      return atWelcome ? '/bookmarks' : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/bookmarks',
        builder: (context, state) => const _BookmarksStub(),
      ),
    ],
  );
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(ProviderContainer container) {
    _sub = container.listen(
      driveAuthStateProvider,
      (_, _) => notifyListeners(),
    );
  }
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

class _BookmarksStub extends StatelessWidget {
  const _BookmarksStub();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('BOOKMARKS_STUB')),
      );
}

Widget _appWith(GoRouter router, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

ProviderContainer _container({
  required _InMemoryStorage storage,
  required _DrivenLauncher launcher,
  required _FakeDriveFileService fileService,
  required http.Client httpClient,
}) {
  return ProviderContainer(overrides: [
    flutterSecureStorageProvider.overrideWithValue(storage),
    httpClientProvider.overrideWithValue(httpClient),
    driveFileServiceProvider.overrideWithValue(fileService),
    driveAuthServiceProvider.overrideWith(
      (ref) => DriveAuthService(
        storage: storage,
        driveFileService: fileService,
        httpClient: httpClient,
        urlLauncher: launcher,
      ),
    ),
  ]);
}

String _idTokenForEmail(String email) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'email': email})))
      .replaceAll('=', '');
  return 'h.$payload.sig';
}

http.Client _tokenOk(String email) {
  return MockClient((req) async {
    return http.Response(
      jsonEncode({
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'expires_in': 3600,
        'id_token': _idTokenForEmail(email),
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

http.Client _token500() => MockClient(
      (req) async => http.Response('boom', 500),
    );

/// Hit the localhost callback with a raw `Socket`. We can't use
/// `http.get` here because `TestWidgetsFlutterBinding` installs an
/// `HttpOverrides` that intercepts every `HttpClient` and returns
/// HTTP 400 — see the "createHttpClient" warning printed by
/// `flutter test`. `Socket` is dart:io's lower level and is not
/// intercepted, so the GET reaches our real loopback server.
Future<void> _hitCallback(Uri authUri, Map<String, String> params) async {
  final redirect = Uri.parse(authUri.queryParameters['redirect_uri']!);
  final query = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  Socket? socket;
  try {
    socket = await Socket.connect(redirect.host, redirect.port);
    socket.write('GET /?$query HTTP/1.1\r\n'
        'Host: ${redirect.host}:${redirect.port}\r\n'
        'Connection: close\r\n'
        '\r\n');
    await socket.flush();
    // Drain whatever the server sends before closing.
    await socket.drain<void>().timeout(const Duration(seconds: 2),
        onTimeout: () {});
  } catch (_) {
    // Server may have already closed in some test paths — ignore.
  } finally {
    socket?.destroy();
  }
}

void main() {
  testWidgets('Case A — cold-start no tokens lands on /welcome',
      (tester) async {
    final storage = _InMemoryStorage();
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _tokenOk('alice@example.com');

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('BOOKMARKS_STUB'), findsNothing);
  });

  testWidgets(
      'Case B — happy path: connect → land on bookmarks, secure storage '
      'populated', (tester) async {
    final storage = _InMemoryStorage();
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _tokenOk('alice@example.com');

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    launcher.onLaunch = (uri) async {
      await _hitCallback(uri, {
        'code': 'authz-code',
        'state': uri.queryParameters['state']!,
      });
    };

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Connect Google Drive'));
      // Wait for the OAuth + token-exchange + ensureBookmarksFile chain.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('BOOKMARKS_STUB'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(storage.store[DriveStorageKeys.accessToken], 'access-1');
    expect(storage.store[DriveStorageKeys.refreshToken], 'refresh-1');
    expect(storage.store[DriveStorageKeys.userEmail], 'alice@example.com');
    expect(storage.store[DriveStorageKeys.fileId], 'integration-file-id');
    expect(fileService.lastToken, 'access-1');
  });

  testWidgets(
      'Case C — user denies consent: stays on welcome, inline message shows',
      (tester) async {
    final storage = _InMemoryStorage();
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _tokenOk('alice@example.com');

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    launcher.onLaunch = (uri) async {
      await _hitCallback(uri, {'error': 'access_denied'});
    };

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Connect Google Drive'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text('Drive connection needed to sync'), findsOneWidget);
    expect(storage.store, isEmpty);
  });

  testWidgets(
      'Case D — token exchange 500: stays on welcome, "Couldn\'t connect"',
      (tester) async {
    final storage = _InMemoryStorage();
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _token500();

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    launcher.onLaunch = (uri) async {
      await _hitCallback(uri, {
        'code': 'authz',
        'state': uri.queryParameters['state']!,
      });
    };

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Connect Google Drive'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text("Couldn't connect — try again"), findsOneWidget);
    // No half-written tokens.
    expect(storage.store, isEmpty);
  });

  testWidgets(
      'Case E — already-connected cold start skips welcome',
      (tester) async {
    final storage = _InMemoryStorage({
      DriveStorageKeys.accessToken: 'at',
      DriveStorageKeys.refreshToken: 'rt',
      DriveStorageKeys.expiresAt:
          DateTime.now().toUtc().toIso8601String(),
      DriveStorageKeys.userEmail: 'alice@example.com',
      DriveStorageKeys.fileId: 'pre-existing-file-id',
    });
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _tokenOk('alice@example.com');

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();

    expect(find.text('BOOKMARKS_STUB'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets(
      'Case F — after happy-path connect, state holds the email '
      '(Settings can render it)', (tester) async {
    final storage = _InMemoryStorage();
    final launcher = _DrivenLauncher();
    final fileService = _FakeDriveFileService();
    final httpClient = _tokenOk('alice@example.com');

    final container = _container(
      storage: storage,
      launcher: launcher,
      fileService: fileService,
      httpClient: httpClient,
    );
    addTearDown(container.dispose);

    final router = _buildTestRouter(container);
    addTearDown(router.dispose);

    launcher.onLaunch = (uri) async {
      await _hitCallback(uri, {
        'code': 'authz',
        'state': uri.queryParameters['state']!,
      });
    };

    await tester.pumpWidget(_appWith(router, container));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Connect Google Drive'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final auth = container.read(driveAuthStateProvider).value;
    expect(auth, isA<DriveAuthConnected>());
    final connected = auth as DriveAuthConnected;
    expect(connected.email, 'alice@example.com');
    expect(connected.fileId, 'integration-file-id');
  });
}
