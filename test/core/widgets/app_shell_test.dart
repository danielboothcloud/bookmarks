import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_spacing.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/app_shell.dart';
import 'package:bookmarks/core/widgets/sidebar.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
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

  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Ok<void, AppError>(null);
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
      expect(find.byType(BookmarkDetailPane), findsNothing);
      expect(find.byType(Sidebar), findsOneWidget);

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      expect(sidebar.collapsed, isFalse);
    });

    testWidgets('detail pane is rendered (not the old placeholder) at >= 900px',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(BookmarkDetailPane), findsOneWidget);
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

    testWidgets('Esc invokes AppDismissIntent action (cascade entry point)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      // AppDismissIntent must be wired in AppShell's Actions. We use a custom
      // intent (not Flutter's DismissIntent) because Scaffold registers a
      // _DismissDrawerAction for DismissIntent that intercepts Esc even when
      // no drawer is open.
      expect(
        () => Actions.invoke(ctx, const AppDismissIntent()),
        returnsNormally,
      );
      final action = Actions.maybeFind<AppDismissIntent>(ctx);
      expect(action, isNotNull,
          reason: 'AppDismissIntent must have an Action handler registered');
    });
  });

  group('AppShell intents', () {
    test('exposes AddBookmark, FocusSearch, DeleteSelected, Dismiss intents',
        () {
      // Compile-time guard: these classes are part of the public surface
      // expected by AppShell's Shortcuts/Actions configuration.
      expect(const AddBookmarkIntent(), isA<Intent>());
      expect(const FocusSearchIntent(), isA<Intent>());
      expect(const DeleteSelectedBookmarkIntent(), isA<Intent>());
    });

    testWidgets(
        'DeleteSelectedBookmarkIntent prompts pendingDelete on the selected id '
        '(Story 1.5)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('chosen-id');

      Actions.invoke(ctx, const DeleteSelectedBookmarkIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), 'chosen-id');
    });

    testWidgets(
        'DeleteSelectedBookmarkIntent is a no-op when nothing is selected',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      expect(container.read(selectedBookmarkIdProvider), isNull);

      Actions.invoke(ctx, const DeleteSelectedBookmarkIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull);
    });

    testWidgets('AppDismissIntent: branch 1 -- clears pendingDelete first',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('id-1');
      container.read(addFormVisibleProvider.notifier).show();
      container.read(pendingDeleteIdProvider.notifier).prompt('id-1');
      await tester.pumpAndSettle();

      Actions.invoke(ctx, const AppDismissIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull);
      expect(container.read(addFormVisibleProvider), isTrue,
          reason: 'cascade stops at pendingDelete -- form untouched');
      expect(container.read(selectedBookmarkIdProvider), 'id-1');
    });

    testWidgets(
        'AppDismissIntent: branch 2 -- hides form when no pendingDelete',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('id-1');
      container.read(addFormVisibleProvider.notifier).show();
      await tester.pumpAndSettle();

      Actions.invoke(ctx, const AppDismissIntent());
      await tester.pumpAndSettle();

      expect(container.read(addFormVisibleProvider), isFalse);
      expect(container.read(selectedBookmarkIdProvider), 'id-1',
          reason: 'cascade stops at form -- selection untouched');
    });

    testWidgets(
        'AppDismissIntent: branch 3 -- clears selection when no form, no pendingDelete',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('id-1');
      await tester.pumpAndSettle();

      Actions.invoke(ctx, const AppDismissIntent());
      await tester.pumpAndSettle();

      expect(container.read(selectedBookmarkIdProvider), isNull);
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
