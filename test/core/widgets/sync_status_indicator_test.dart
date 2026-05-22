import 'dart:async';

import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/widgets/sync_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  int pendingCount = 0,
  bool hasEverSynced = true,
  bool collapsed = false,
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(auth)),
        syncStatusProvider.overrideWith((ref) => Stream.value(status)),
        syncQueuePendingCountProvider
            .overrideWith((ref) => Stream.value(pendingCount)),
        hasEverSyncedProvider
            .overrideWith((ref) => Stream.value(hasEverSynced)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(body: SyncStatusIndicator(collapsed: collapsed)),
        ),
      ),
    ),
  );
}

Color _dotColorOf(WidgetTester tester) {
  final container = tester.widgetList<Container>(find.byType(Container)).first;
  final decoration = container.decoration as BoxDecoration;
  return decoration.color!;
}

void main() {
  const connected = DriveAuthState.connected(
    email: 'test@example.com',
    fileId: 'file-1',
  );

  group('SyncStatusIndicator visibility', () {
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
      expect(find.byType(Container), findsNothing);
    });
  });

  group('indicatorStateFor truth table', () {
    test('SyncPulling → amber pulse / "Pulling from Drive…"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.pulling(),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Pulling from Drive…',
            pulsing: true,
          ),
        ),
      );
    });

    test('SyncMerging → amber pulse / "Merging changes…"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.merging(),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Merging changes…',
            pulsing: true,
          ),
        ),
      );
    });

    test('SyncPushing → amber pulse / "Syncing…"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.pushing(),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Syncing…',
            pulsing: true,
          ),
        ),
      );
    });

    test('SyncFailed(NetworkError) → grey / "Drive unavailable"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.failed(NetworkError('boom')),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnavailable,
            label: 'Drive unavailable',
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncFailed(AuthError) → grey / "Drive unavailable"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.failed(AuthError('401')),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnavailable,
            label: 'Drive unavailable',
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncFailed(SyncError) → grey / "Couldn\'t sync — will retry"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.failed(SyncError('parse')),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnavailable,
            label: "Couldn't sync — will retry",
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncFailed(StorageError) → grey / "Couldn\'t sync — will retry"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.failed(StorageError('disk')),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnavailable,
            label: "Couldn't sync — will retry",
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncAwaitingInitialPull → amber / awaiting label', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.awaitingInitialPull(),
          pendingCount: 0,
          hasEverSynced: false,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Awaiting initial sync from Drive',
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncIdle + pending=0 + hasEverSynced=true → green / "Synced with Drive"',
        () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.idle(),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncSynced,
            label: 'Synced with Drive',
            pulsing: false,
          ),
        ),
      );
    });

    test(
        'SyncSynced + pending=0 + hasEverSynced=true → green / "Synced with Drive"',
        () {
      expect(
        indicatorStateFor(
          status: SyncStatus.synced(at: DateTime.utc(2026, 5, 20)),
          pendingCount: 0,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncSynced,
            label: 'Synced with Drive',
            pulsing: false,
          ),
        ),
      );
    });

    test(
        'SyncIdle + pending=0 + hasEverSynced=false → amber / awaiting label',
        () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.idle(),
          pendingCount: 0,
          hasEverSynced: false,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Awaiting initial sync from Drive',
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncIdle + pending>0 → amber / "Unsynced changes"', () {
      expect(
        indicatorStateFor(
          status: const SyncStatus.idle(),
          pendingCount: 3,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Unsynced changes',
            pulsing: false,
          ),
        ),
      );
    });

    test('SyncSynced + pending>0 → amber / "Unsynced changes" (precedence)',
        () {
      expect(
        indicatorStateFor(
          status: SyncStatus.synced(at: DateTime.utc(2026, 5, 20)),
          pendingCount: 1,
          hasEverSynced: true,
        ),
        equals(
          (
            dot: AppColors.syncUnsynced,
            label: 'Unsynced changes',
            pulsing: false,
          ),
        ),
      );
    });
  });

  group('SyncStatusIndicator expanded layout', () {
    testWidgets('renders green dot + "Synced with Drive"', (tester) async {
      await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
      await tester.pumpAndSettle();
      expect(find.text('Synced with Drive'), findsOneWidget);
      expect(_dotColorOf(tester), AppColors.syncSynced);
    });

    testWidgets('renders amber dot + "Unsynced changes" when pending > 0',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.idle(),
        pendingCount: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsynced changes'), findsOneWidget);
      expect(_dotColorOf(tester), AppColors.syncUnsynced);
    });

    testWidgets('renders amber dot + "Awaiting initial sync from Drive" '
        'when hasEverSynced is false', (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.idle(),
        hasEverSynced: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Awaiting initial sync from Drive'), findsOneWidget);
      expect(_dotColorOf(tester), AppColors.syncUnsynced);
    });

    testWidgets('renders grey dot + "Drive unavailable" for NetworkError',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.failed(NetworkError('boom')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Drive unavailable'), findsOneWidget);
      expect(_dotColorOf(tester), AppColors.syncUnavailable);
    });

    testWidgets("renders grey dot + \"Couldn't sync — will retry\" for SyncError",
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.failed(SyncError('parse')),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't sync — will retry"), findsOneWidget);
      expect(_dotColorOf(tester), AppColors.syncUnavailable);
    });

    testWidgets('renders amber pulse + "Syncing…" for SyncPushing',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.pushing(),
      );
      // No pumpAndSettle: the pulse animation never settles. Pump a few
      // frames to deliver the StreamProvider's initial value, then
      // assert before the animation runs further.
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Syncing…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      expect(_dotColorOf(tester), AppColors.syncUnsynced);
    });

    testWidgets('renders "Pulling from Drive…" for SyncPulling',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.pulling(),
      );
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Pulling from Drive…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders "Merging changes…" for SyncMerging', (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.merging(),
      );
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Merging changes…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('static states do NOT use FadeTransition', (tester) async {
      await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('padding is EdgeInsets.symmetric(horizontal: md, vertical: sm)',
        (tester) async {
      await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
      await tester.pumpAndSettle();
      final padding = tester.widgetList<Padding>(find.byType(Padding)).first;
      expect(
        padding.padding,
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      );
    });
  });

  group('SyncStatusIndicator reduce-motion', () {
    testWidgets('in-progress states render static dot when '
        'disableAnimations is true', (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.pushing(),
        disableAnimations: true,
      );
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Syncing…'), findsOneWidget);
      // FadeTransition is absent — the dot is static.
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(_dotColorOf(tester), AppColors.syncUnsynced);
    });
  });

  group('SyncStatusIndicator collapsed layout', () {
    testWidgets('renders dot inside Tooltip without label text',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.idle(),
        collapsed: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(Tooltip), findsOneWidget);
      // No label text rendered in collapsed mode.
      expect(find.text('Synced with Drive'), findsNothing);
      // Dot is still painted with the correct colour.
      expect(_dotColorOf(tester), AppColors.syncSynced);
    });

    testWidgets('tooltip message matches the displayed label',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.failed(NetworkError('boom')),
        collapsed: true,
      );
      await tester.pumpAndSettle();
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Drive unavailable');
    });

    testWidgets('collapsed mode preserves Semantics live region',
        (tester) async {
      await _pumpWith(
        tester,
        auth: connected,
        status: const SyncStatus.idle(),
        collapsed: true,
      );
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
  });

  group('SyncStatusIndicator Semantics', () {
    testWidgets('wraps the row in Semantics(liveRegion: true)',
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

    testWidgets('rendered SemanticsNode carries the indicator label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
      await tester.pumpAndSettle();
      // Walk the indicator's semantics subtree and confirm the label
      // is exposed.
      final root = tester.getSemantics(find.byType(SyncStatusIndicator));
      final labels = <String>[];
      void walk(SemanticsNode node) {
        if (node.label.isNotEmpty) labels.add(node.label);
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }
      walk(root);
      expect(
        labels.any((l) => l.contains('Synced with Drive')),
        isTrue,
        reason: 'expected indicator label in semantics subtree, got $labels',
      );
      handle.dispose();
    });

    testWidgets('dot is wrapped in ExcludeSemantics', (tester) async {
      await _pumpWith(tester, auth: connected, status: const SyncStatus.idle());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });

  group('SyncStatusIndicator label updates announce', () {
    testWidgets('label updates when status transitions from idle to pushing',
        (tester) async {
      final controller = StreamController<SyncStatus>.broadcast(sync: true);
      addTearDown(controller.close);
      controller.add(const SyncStatus.idle());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(connected)),
            syncStatusProvider.overrideWith((ref) => controller.stream),
            syncQueuePendingCountProvider
                .overrideWith((ref) => Stream.value(0)),
            hasEverSyncedProvider
                .overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SyncStatusIndicator()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synced with Drive'), findsOneWidget);

      controller.add(const SyncStatus.pushing());
      await tester.pump();
      expect(find.text('Syncing…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );

      controller.add(SyncStatus.synced(at: DateTime.utc(2026, 5, 20)));
      await tester.pump();
      expect(find.text('Synced with Drive'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SyncStatusIndicator),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });
  });
}
