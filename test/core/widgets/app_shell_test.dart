import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_spacing.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildApp() {
  return MaterialApp.router(
    theme: AppTheme.build(),
    routerConfig: buildRouter(),
  );
}

void main() {
  group('AppShell responsive layout', () {
    testWidgets('shows three-pane layout at >= 900px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Select a bookmark'), findsOneWidget);
      expect(find.byType(Sidebar), findsOneWidget);

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      expect(sidebar.collapsed, isFalse);
    });

    testWidgets('hides detail pane at 800px (two-pane)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Select a bookmark'), findsNothing);
      expect(find.byType(Sidebar), findsOneWidget);

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      expect(sidebar.collapsed, isFalse);
    });

    testWidgets('collapses sidebar at < 600px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(560, 600));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      expect(sidebar.collapsed, isTrue);
      expect(find.text('Select a bookmark'), findsNothing);
    });

    testWidgets('renders empty state on initial route', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No bookmarks yet'), findsOneWidget);
    });
  });

  group('AppSpacing constants', () {
    test('uses 8px base unit multiples', () {
      expect(AppSpacing.sm, 8.0);
      expect(AppSpacing.md, 16.0);
      expect(AppSpacing.lg, 24.0);
      expect(AppSpacing.xl, 32.0);
    });

    test('breakpoints match UX spec', () {
      expect(AppSpacing.detailPaneBreakpoint, 900.0);
      expect(AppSpacing.sidebarCollapseBreakpoint, 600.0);
    });

    test('minimum window size is 700x500', () {
      expect(AppSpacing.minWindowWidth, 700.0);
      expect(AppSpacing.minWindowHeight, 500.0);
    });
  });
}
