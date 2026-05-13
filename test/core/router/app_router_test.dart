import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/features/onboarding/presentation/welcome_screen.dart';
import 'package:bookmarks/features/onboarding/presentation/widgets/drive_connect_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Test-only [DriveAuthNotifier] that lets the test drive `state`
/// directly. We never invoke the real OAuth flow from router tests.
class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;

  @override
  Future<DriveAuthState> build() async => _initial;

  void setState(DriveAuthState s) {
    state = AsyncData(s);
  }
}

GoRouter _routerWith(ProviderContainer container) => buildRouter(container);

Widget _wrap(GoRouter router, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('cold-start disconnected redirects to /welcome', (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(const DriveAuthState.disconnected()),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(DriveConnectButton), findsOneWidget);
  });

  testWidgets('cold-start connected lands on /bookmarks', (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(
          const DriveAuthState.connected(email: 'a@b', fileId: 'f1'),
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets(
      'state transition disconnected → connecting stays on /welcome',
      (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(const DriveAuthState.disconnected()),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    notifier.setState(const DriveAuthState.connecting());
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets(
      'state transition connecting → connected hops to /bookmarks via '
      'refreshListenable', (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(const DriveAuthState.disconnected()),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    notifier.setState(const DriveAuthState.connecting());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);

    notifier.setState(
      const DriveAuthState.connected(email: 'a@b', fileId: 'f1'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets(
      'state transition connected → disconnected sends user back to /welcome',
      (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(
          const DriveAuthState.connected(email: 'a@b', fileId: 'f1'),
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    notifier.setState(const DriveAuthState.disconnected());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets(
      'failed state still routes to /welcome (user retries from there)',
      (tester) async {
    final container = ProviderContainer(overrides: [
      driveAuthStateProvider.overrideWith(
        () => _FakeAuthNotifier(
          const DriveAuthState.failed(NetworkError('boom')),
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final router = _routerWith(container);
    addTearDown(router.dispose);

    await tester.pumpWidget(_wrap(router, container));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
