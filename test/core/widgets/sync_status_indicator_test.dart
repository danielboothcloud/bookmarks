import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/widgets/sync_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  @override
  Future<DriveAuthState> build() async => _initial;
}

Future<void> _pumpWith(
  WidgetTester tester, {
  required DriveAuthState auth,
  required SyncStatus status,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(auth)),
        syncStatusProvider.overrideWith((ref) => Stream.value(status)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SyncStatusIndicator()),
      ),
    ),
  );
}

void main() {
  const connected = DriveAuthState.connected(
    email: 'test@example.com',
    fileId: 'file-1',
  );

  testWidgets('renders SizedBox.shrink when auth is disconnected',
      (tester) async {
    await _pumpWith(
      tester,
      auth: const DriveAuthState.disconnected(),
      status: const SyncStatus.idle(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SyncStatusIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders "Synced with Drive" for SyncStatus.idle',
      (tester) async {
    await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
    await tester.pumpAndSettle();
    expect(find.text('Synced with Drive'), findsOneWidget);
  });

  testWidgets('renders "Synced with Drive" for SyncStatus.synced',
      (tester) async {
    await _pumpWith(
      tester,
      auth: connected,
      status: SyncStatus.synced(at: DateTime.utc(2026, 5, 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synced with Drive'), findsOneWidget);
  });

  testWidgets('renders "Syncing…" for SyncStatus.pushing', (tester) async {
    await _pumpWith(
      tester,
      auth: connected,
      status: const SyncStatus.pushing(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Syncing…'), findsOneWidget);
  });

  testWidgets("renders \"Couldn't sync — will retry\" for SyncStatus.failed",
      (tester) async {
    await _pumpWith(
      tester,
      auth: connected,
      status: const SyncStatus.failed(NetworkError('Drive 500')),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't sync — will retry"), findsOneWidget);
  });

  testWidgets('renders "Awaiting initial sync from Drive" for '
      'SyncStatus.awaitingInitialPull', (tester) async {
    await _pumpWith(
      tester,
      auth: connected,
      status: const SyncStatus.awaitingInitialPull(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Awaiting initial sync from Drive'), findsOneWidget);
  });

  testWidgets('wraps the label in Semantics(liveRegion: true)',
      (tester) async {
    await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
    await tester.pumpAndSettle();
    final semantics = tester.widgetList<Semantics>(
      find.descendant(
        of: find.byType(SyncStatusIndicator),
        matching: find.byType(Semantics),
      ),
    );
    expect(
      semantics.any((s) =>
          s.properties.liveRegion == true &&
          s.properties.label == 'Synced with Drive'),
      isTrue,
    );
  });
}
