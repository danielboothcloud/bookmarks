import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/settings/application/drive_account_controller.dart';
import 'package:bookmarks/features/settings/presentation/settings_screen.dart';
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

  @override
  Future<void> connect() async {
    connectCalls++;
  }
}

class _FakeDriveAccountController extends DriveAccountController {
  int disconnectCalls = 0;

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}

ProviderContainer _makeContainer(
  DriveAuthState initial, {
  _FakeDriveAccountController? controller,
}) {
  return ProviderContainer(overrides: [
    driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(initial)),
    if (controller != null)
      driveAccountControllerProvider.overrideWith(() => controller),
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
      'connected: shows email + subtitle + ENABLED Disconnect (no "later update" caption)',
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
    expect(find.text('Available in a later update'), findsNothing,
        reason: 'Story 4.5 removes the deferred-feature caption');

    final disconnect = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Disconnect'),
    );
    expect(disconnect.onPressed, isNotNull,
        reason: 'Disconnect must be enabled in 4.5');
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

  testWidgets(
      'tapping Disconnect shows the inline confirmation (text + two buttons; '
      'original Disconnect OutlinedButton is gone)', (tester) async {
    final container = _makeContainer(
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(find.text('Disconnect from Drive? Local bookmarks stay.'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Disconnect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsNothing,
        reason: 'OutlinedButton trigger is replaced by the confirmation row');
  });

  testWidgets('tapping Cancel reverts to the default state', (tester) async {
    final container = _makeContainer(
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);
    expect(find.text('Disconnect from Drive? Local bookmarks stay.'),
        findsNothing);
  });

  testWidgets('Esc dismisses the confirmation', (tester) async {
    final container = _makeContainer(
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsOneWidget);
    expect(find.text('Disconnect from Drive? Local bookmarks stay.'),
        findsNothing);
  });

  testWidgets(
      'tapping the confirmation Disconnect invokes '
      'driveAccountControllerProvider.notifier.disconnect()',
      (tester) async {
    final controller = _FakeDriveAccountController();
    final container = _makeContainer(
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
      controller: controller,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(controller.disconnectCalls, 1);
  });
}
