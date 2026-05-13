import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/onboarding/presentation/welcome_screen.dart';
import 'package:bookmarks/features/onboarding/presentation/widgets/drive_connect_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  int connectCalls = 0;

  @override
  Future<DriveAuthState> build() async => _initial;

  void setState(DriveAuthState s) {
    state = AsyncData(s);
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    ref.read(hasAttemptedConnectProvider.notifier).markAttempted();
    state = const AsyncData(DriveAuthState.connecting());
  }
}

ProviderContainer _makeContainer(DriveAuthState initial) {
  return ProviderContainer(overrides: [
    driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(initial)),
  ]);
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const WelcomeScreen(),
    ),
  );
}

void main() {
  testWidgets(
      'disconnected initial: shows heading + Connect button, no status message',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.text('Drive connection needed to sync'), findsNothing);
    expect(find.text("We've opened your browser. Complete sign-in to continue."),
        findsNothing);
    expect(find.text("Couldn't connect — try again"), findsNothing);
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'disconnected after attempt: shows "Drive connection needed to sync"',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    // Simulate the user having attempted once.
    container.read(hasAttemptedConnectProvider.notifier).markAttempted();

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Drive connection needed to sync'), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsOneWidget);
  });

  testWidgets('connecting: button shows "Waiting for browser…" and disabled',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.connecting());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for browser…'), findsOneWidget);
    expect(
      find.text("We've opened your browser. Complete sign-in to continue."),
      findsOneWidget,
    );
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNull);
  });

  testWidgets('failed: shows "Couldn\'t connect — try again", button enabled',
      (tester) async {
    final container = _makeContainer(
      const DriveAuthState.failed(NetworkError('boom')),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't connect — try again"), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('tapping Connect button when disconnected invokes notifier',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    expect(notifier.connectCalls, 1);
  });

  testWidgets('tapping Connect when connecting is a no-op (disabled)',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.connecting());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    expect(notifier.connectCalls, 0);
  });

  testWidgets('Connect button is the sole focusable widget on the screen',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    // Two assertions: exactly one FilledButton, and no TextField /
    // other interactive surfaces. Combined with Material's built-in
    // keyboard activation, this establishes the keyboard contract:
    // tab traversal can only land here.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('minimum window size (700x500) renders without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.byType(DriveConnectButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
