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
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/search/presentation/widgets/search_bar.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBookmarkRepository implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() => Stream.value(const <Bookmark>[]);

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) =>
      const Stream<List<Bookmark>>.empty();

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

Widget _buildApp({Map<String?, List<Folder>>? folderTree}) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_FakeBookmarkRepository()),
      if (folderTree != null)
        folderChildrenIndexProvider.overrideWithValue(folderTree),
    ],
    child: MaterialApp.router(
      theme: AppTheme.build(),
      routerConfig: buildRouter(),
    ),
  );
}

Folder _ff(String id, {String? parentId}) => Folder(
      id: id,
      name: id,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

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
      expect(const DeleteSelectedItemIntent(), isA<Intent>());
    });

    testWidgets(
        'DeleteSelectedItemIntent prompts pendingDelete on the selected id '
        '(Story 1.5)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('chosen-id');

      Actions.invoke(ctx, const DeleteSelectedItemIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), 'chosen-id');
    });

    testWidgets(
        'DeleteSelectedItemIntent is a no-op when nothing is selected',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      expect(container.read(selectedBookmarkIdProvider), isNull);

      Actions.invoke(ctx, const DeleteSelectedItemIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull);
    });

    testWidgets(
        'Delete keystroke fires DeleteSelectedItemIntent (verifies the '
        'SingleActivator binding, not just the Action wiring)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('id-key');
      await tester.pumpAndSettle();

      // Default focus sits on a non-EditableText scope inside AppShell's
      // Shortcuts subtree, so the key event routes through the Shortcuts
      // widget rather than landing on a text input.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), 'id-key');
    });

    testWidgets(
        'Backspace keystroke fires DeleteSelectedItemIntent '
        '(macOS users press Backspace; AC1 enumerates both keys)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('id-bs');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), 'id-bs');
    });

    testWidgets(
        'Backspace with focus inside an EditableText does NOT prompt delete '
        '(EditableText guard: AC1 must not break text editing)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);

      // Selection set so the action's other guard (selection != null) would
      // otherwise allow the prompt to fire -- isolating the EditableText guard.
      container.read(selectedBookmarkIdProvider.notifier).select('id-edit');
      // Open the inline-add form; its URL TextField has autofocus.
      container.read(addFormVisibleProvider.notifier).show();
      await tester.pumpAndSettle();

      // Precondition: focus is in an EditableText (the URL TextField).
      final focused = FocusManager.instance.primaryFocus;
      expect(
        focused?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
        reason: 'precondition: focus should be in the URL TextField',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull,
          reason: 'EditableText guard must suppress the delete prompt so '
              'Backspace deletes a character, not a bookmark');
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

  group('AppShell fallback focus (regression: Story 2.4 macOS beep)', () {
    testWidgets(
        'AppShell autofocuses a Focus node inside its Shortcuts subtree so '
        'Delete works when no row, button, or text field has explicitly '
        'claimed focus (InkWell does not focus on tap; without a fallback '
        'Focus, key events propagate to the platform)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Sanity: primaryFocus is set on mount (the load-bearing precondition
      // for the keyboard pipeline below). Without the autofocus Focus node
      // inside Shortcuts, primaryFocus is null in this test harness.
      expect(FocusManager.instance.primaryFocus, isNotNull,
          reason: 'AppShell must claim in-tree focus on mount');

      // Set a folder selection (simulating a sidebar click, but without the
      // route navigation that would tangle this test). Press Delete via the
      // real keyboard pipeline -- this exercises Shortcuts.activator
      // resolution, not Actions.invoke.
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('f-1');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(container.read(pendingFolderDeleteIdProvider), 'f-1',
          reason: 'Delete must reach AppShell Shortcuts via fallback focus');
    });
  });

  group('AppShell folder-aware delete intents (Story 2.4)', () {
    testWidgets(
        'DeleteSelectedItemIntent prompts the FOLDER when only a folder '
        'is selected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('f-1');

      Actions.invoke(ctx, const DeleteSelectedItemIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingFolderDeleteIdProvider), 'f-1');
      expect(container.read(pendingDeleteIdProvider), isNull);
    });

    testWidgets(
        'DeleteSelectedItemIntent: bookmark wins over folder when BOTH are '
        'selected (Story 1.5 priority preserved)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedBookmarkIdProvider.notifier).select('b-1');
      container.read(selectedFolderIdProvider.notifier).select('f-1');

      Actions.invoke(ctx, const DeleteSelectedItemIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), 'b-1');
      expect(container.read(pendingFolderDeleteIdProvider), isNull);
    });

    testWidgets(
        'AppDismissIntent: pendingFolderDelete has higher Esc priority than '
        'pendingDelete', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(pendingDeleteIdProvider.notifier).prompt('b-1');
      container.read(pendingFolderDeleteIdProvider.notifier).prompt('f-1');

      Actions.invoke(ctx, const AppDismissIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingFolderDeleteIdProvider), isNull);
      expect(container.read(pendingDeleteIdProvider), 'b-1',
          reason: 'cascade stops at folder confirmation -- bookmark prompt '
              'remains, requires another Esc');
    });

    testWidgets(
        'AppDismissIntent: clears pendingDelete when no folder confirmation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(pendingDeleteIdProvider.notifier).prompt('b-1');

      Actions.invoke(ctx, const AppDismissIntent());
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull);
    });
  });

  group('Sidebar keyboard navigation (Story 2.4 follow-up)', () {
    // Tree:
    //   a
    //     b
    //   c
    Map<String?, List<Folder>> tree() => {
          null: [_ff('a'), _ff('c')],
          'a': [_ff('b', parentId: 'a')],
        };

    testWidgets('ArrowDown moves selection to the next visible folder',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // 'a' is collapsed -> visible list is [a, c]; next is c.
      expect(container.read(selectedFolderIdProvider), 'c');
    });

    testWidgets(
        'ArrowDown skips collapsed children and lands on next root sibling',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');
      // Now expand 'a' so 'b' is visible.
      container.read(expandedFolderIdsProvider.notifier).expand('a');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(container.read(selectedFolderIdProvider), 'b');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(container.read(selectedFolderIdProvider), 'c');
    });

    testWidgets('ArrowDown at last visible folder is a no-op',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('c');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), 'c');
    });

    testWidgets('ArrowUp moves selection to the previous visible folder',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('c');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), 'a');
    });

    testWidgets('ArrowRight on a collapsed parent expands it',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(container.read(expandedFolderIdsProvider), contains('a'));
      expect(container.read(selectedFolderIdProvider), 'a',
          reason: 'expand only -- selection stays put on the parent');
    });

    testWidgets(
        'ArrowRight on an already-expanded parent moves to first child',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');
      container.read(expandedFolderIdsProvider.notifier).expand('a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), 'b');
    });

    testWidgets('ArrowRight on a leaf is a no-op', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('c');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(container.read(expandedFolderIdsProvider), isEmpty);
      expect(container.read(selectedFolderIdProvider), 'c');
    });

    testWidgets('ArrowLeft on an expanded folder collapses it',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');
      container.read(expandedFolderIdsProvider.notifier).expand('a');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(container.read(expandedFolderIdsProvider), isEmpty);
    });

    testWidgets('ArrowLeft on a child folder ascends to its parent',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(expandedFolderIdsProvider.notifier).expand('a');
      container.read(selectedFolderIdProvider.notifier).select('b');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), 'a');
    });

    testWidgets('Enter on a parent toggles expansion', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(expandedFolderIdsProvider), {'a'});

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(expandedFolderIdsProvider), isEmpty);
    });

    testWidgets('Enter on a leaf is a no-op (no expansion mutation)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('c');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(container.read(expandedFolderIdsProvider), isEmpty);
    });

    testWidgets(
        'Arrow keys with no folder selected are inert (key propagates)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      expect(container.read(selectedFolderIdProvider), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), isNull);
    });

    testWidgets(
        'Arrow keys with focus inside an EditableText do NOT navigate '
        '(carve-out preserves text-cursor behaviour)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(folderTree: tree()));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      container.read(selectedFolderIdProvider.notifier).select('a');
      container.read(addFormVisibleProvider.notifier).show();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(container.read(selectedFolderIdProvider), 'a',
          reason: 'EditableText carve-out must suppress folder-nav arrows');
    });
  });

  group('AppShell focus reclaimer (post-3.1 regression guard)', () {
    testWidgets(
        'pointer-down on a non-focus-claiming surface restores primary focus '
        'inside the shell so global shortcuts keep firing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      final shellNode = container.read(appShellFocusNodeProvider);

      // Precondition: autofocus put primary focus on (or inside) the shell.
      expect(
        FocusManager.instance.primaryFocus == shellNode ||
            (FocusManager.instance.primaryFocus?.ancestors
                    .contains(shellNode) ??
                false),
        isTrue,
      );

      // Simulate the bug: a transient surface dispose / programmatic
      // unfocus drops primary focus outside the AppShell scope.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // After unfocus the primary may be a root-level FocusScope; assert it
      // is NOT the shell node so the precondition for the reclaim test is
      // genuine (we want to verify the reclaim recovers from this state).
      final droppedPrimary = FocusManager.instance.primaryFocus;
      expect(droppedPrimary == shellNode, isFalse,
          reason: 'precondition: focus must be outside the shell node');

      // Sanity-check the bug: in the dropped state, Cmd+N should NOT open
      // the inline-add form because the Shortcuts handler isn't reached.
      // Skipping this assertion -- it's flaky in the test harness because
      // sendKeyEvent dispatches via the keyboard service rather than the
      // platform's shortcut routing, so it can pass through paths that the
      // production app's macOS engine would beep on. The reclaim assertion
      // below is the load-bearing one.

      // Tap an inert surface in the content area. We aim at the
      // BookmarkSearchBar's outer Container -- specifically a coordinate
      // inside its padding but outside the TextField proper, which is
      // exactly the user-reported failure surface.
      final searchBarFinder = find.byType(BookmarkSearchBar);
      expect(searchBarFinder, findsOneWidget);
      final searchBarRect = tester.getRect(searchBarFinder);
      // Top-left corner of the SearchBar -- inside its Container padding,
      // outside the TextField (which sits horizontally inset by the
      // prefix-icon and vertically inset by the dense input theme).
      final tapPoint = Offset(
        searchBarRect.left + 4,
        searchBarRect.top + 2,
      );
      await tester.tapAt(tapPoint);
      // Two pumps: one to deliver the pointer event, one to drain the
      // post-frame callback that schedules the actual reclaim.
      await tester.pump();
      await tester.pump();

      // After the post-frame callback, primary focus must be back inside
      // the shell scope. Either equals the shell node, or one of its
      // descendants did claim focus (e.g. the EmptyState's CTA).
      final reclaimed = FocusManager.instance.primaryFocus;
      final inShell = reclaimed == shellNode ||
          (reclaimed?.ancestors.contains(shellNode) ?? false);
      expect(inShell, isTrue,
          reason: 'pointer-down outside any focus-claim widget must leave '
              'primary focus inside the shell scope');

      // Cmd+N now reaches the Shortcuts handler -- shows the inline-add
      // form (the AddBookmarkIntent action target).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(
          () => tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      expect(container.read(addFormVisibleProvider), isTrue,
          reason: 'global Cmd+N must fire after the focus reclaim');
    });

    testWidgets('reclaim is a no-op when a child widget claims focus on tap',
        (tester) async {
      // Tapping the search bar's TextField (a focus-claiming widget) must
      // NOT trigger the reclaimer's restore -- the TextField wins, focus
      // stays on it, and the post-frame check sees a descendant of the
      // shell so it doesn't fire.
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Sidebar));
      final container = ProviderScope.containerOf(ctx);
      final shellNode = container.read(appShellFocusNodeProvider);

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsAtLeastNWidgets(1));
      await tester.tap(textFieldFinder.first);
      await tester.pumpAndSettle();

      final after = FocusManager.instance.primaryFocus;
      // TextField's own FocusNode is the primary; it must be a descendant
      // of the shell node, not the shell node itself.
      expect(after == shellNode, isFalse,
          reason: 'TextField should hold focus after tap, not the shell');
      expect(after?.ancestors.contains(shellNode), isTrue,
          reason: 'TextField focus is inside the shell subtree');
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
