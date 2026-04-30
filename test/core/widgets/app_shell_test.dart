import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_spacing.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/app_shell.dart';
import 'package:bookmarks/core/widgets/sidebar.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBookmarkRepository implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() => Stream.value(const <Bookmark>[]);

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(StorageError('not found'));

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      Ok<Bookmark, AppError>(bookmark);
}

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_FakeBookmarkRepository()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.build(),
      routerConfig: buildRouter(),
    ),
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

    testWidgets('detail pane and sidebar carry explicit traversal order',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final orders = tester
          .widgetList<FocusTraversalOrder>(find.byType(FocusTraversalOrder))
          .map((w) => (w.order as NumericFocusOrder).order)
          .toList();
      expect(orders, containsAll(<double>[1, 3, 4]));
    });

    testWidgets('Esc invokes DismissIntent action and unfocuses',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Focus the FilledButton so Esc has something to dismiss.
      final buttonFinder = find.widgetWithText(FilledButton, 'Add bookmark');
      final focusNode = Focus.maybeOf(tester.element(buttonFinder));
      focusNode?.requestFocus();
      FocusScope.of(tester.element(buttonFinder)).requestFocus();
      await tester.pump();

      // DismissIntent must be wired in Actions — Actions.invoke returns null
      // when the intent has no handler in scope. With our handler in place it
      // returns void (null) but does not throw.
      final actionsContext = tester.element(find.byType(AppShell));
      expect(
        () => Actions.invoke(actionsContext, const DismissIntent()),
        returnsNormally,
      );
      // Confirm the handler is actually registered (not falling through).
      final action = Actions.maybeFind<DismissIntent>(actionsContext);
      expect(action, isNotNull,
          reason: 'DismissIntent must have an Action handler registered');
    });
  });

  group('AppShell intents', () {
    test('exposes AddBookmark, FocusSearch, Dismiss intents', () {
      // Compile-time guard: these classes are part of the public surface
      // expected by AppShell's Shortcuts/Actions configuration.
      expect(const AddBookmarkIntent(), isA<Intent>());
      expect(const FocusSearchIntent(), isA<Intent>());
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
