import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  int connectCalls = 0;

  @override
  Future<DriveAuthState> build() async => _initial;

  @override
  Future<void> connect() async {
    connectCalls++;
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
      home: const Scaffold(body: SettingsScreen()),
    ),
  );
}

void main() {
  testWidgets(
      'connected: shows email + subtitle + disabled Disconnect + inline note',
      (tester) async {
    final container = _makeContainer(
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text("Bookmarks sync to this account's Drive"), findsOneWidget);
    expect(find.text('Available in a later update'), findsOneWidget);

    final disconnect = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Disconnect'),
    );
    expect(disconnect.onPressed, isNull,
        reason: 'Disconnect must be disabled in 4.1');
  });

  testWidgets(
      'disconnected (defensive): shows Not connected + Connect button',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsOneWidget);
  });

  testWidgets('disconnected: tapping Connect invokes notifier.connect',
      (tester) async {
    final container = _makeContainer(const DriveAuthState.disconnected());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Connect Google Drive'));
    await tester.pumpAndSettle();

    final notifier =
        container.read(driveAuthStateProvider.notifier) as _FakeAuthNotifier;
    expect(notifier.connectCalls, 1);
  });
}
