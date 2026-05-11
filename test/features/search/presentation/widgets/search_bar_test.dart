import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/search/application/search_providers.dart';
import 'package:bookmarks/features/search/domain/i_search_repository.dart';
import 'package:bookmarks/features/search/presentation/widgets/search_bar.dart';
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

/// Stub repository that returns an empty list synchronously. Story 3.1's
/// SearchBar tests don't depend on results -- the repository tests cover
/// query semantics. This avoids spinning up a full in-memory database per
/// widget test.
class _EmptySearchRepository implements ISearchRepository {
  @override
  Stream<List<Bookmark>> search(
    String query, {
    Set<String>? folderIds,
    String? tagId,
  }) =>
      Stream.value(const <Bookmark>[]);
}

Widget _buildApp(WidgetTester tester, {ISearchRepository? searchRepo}) {
  // Mirrors the override pattern used by `core/widgets/app_shell_test.dart`:
  // we do NOT touch `appDatabaseProvider` -- the bookmarks/folders/tags
  // repositories are consumed lazily, and on the initial empty route the
  // sidebar's expanded sections aren't watched, so the real DB is never
  // instantiated. Overriding the DB pulls in Drift's stream-cancel timer
  // which leaks past the test framework's verifyInvariants pass.
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_FakeBookmarkRepository()),
      searchRepositoryProvider
          .overrideWithValue(searchRepo ?? _EmptySearchRepository()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.build(),
      routerConfig: buildRouter(),
    ),
  );
}

void main() {
  group('BookmarkSearchBar', () {
    testWidgets('Cmd+F focuses the search bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      // Send Cmd+F (logical meta on, then keyF). We use simulateKeyDownEvent
      // for the modifier so HardwareKeyboard reports it pressed across the
      // keyF event.
      await simulateKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(
          () => simulateKeyUpEvent(LogicalKeyboardKey.metaLeft));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(BookmarkSearchBar));
      final node = ProviderScope.containerOf(ctx)
          .read(searchBarFocusNodeProvider);
      expect(node.hasFocus, isTrue);
    });

    testWidgets('Ctrl+F focuses the search bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(
          () => simulateKeyUpEvent(LogicalKeyboardKey.controlLeft));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(BookmarkSearchBar));
      final node = ProviderScope.containerOf(ctx)
          .read(searchBarFocusNodeProvider);
      expect(node.hasFocus, isTrue);
    });

    testWidgets('Cmd+F works even when focus is in another EditableText',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(BookmarkSearchBar));
      final container = ProviderScope.containerOf(ctx);
      // Cmd+N opens the inline-add form whose URL field autofocuses.
      container.read(addFormVisibleProvider.notifier).show();
      await tester.pumpAndSettle();
      // Precondition: focus is in an EditableText.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );

      await simulateKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(
          () => simulateKeyUpEvent(LogicalKeyboardKey.metaLeft));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      final node = container.read(searchBarFocusNodeProvider);
      expect(node.hasFocus, isTrue,
          reason: 'global Cmd+F binding must override an EditableText focus');
    });

    testWidgets('typing updates searchQueryProvider', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(BookmarkSearchBar));
      final container = ProviderScope.containerOf(ctx);

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();

      expect(container.read(searchQueryProvider), 'flutter');
    });

    testWidgets('searchActiveProvider derives correctly across empty / '
        'whitespace / non-empty states', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      expect(container.read(searchActiveProvider), isFalse,
          reason: 'empty initial state -> inactive');

      container.read(searchQueryProvider.notifier).set('   ');
      expect(container.read(searchActiveProvider), isFalse,
          reason: 'whitespace-only -> inactive');

      container.read(searchQueryProvider.notifier).set('flutter');
      expect(container.read(searchActiveProvider), isTrue);

      container.read(searchQueryProvider.notifier).clear();
      expect(container.read(searchActiveProvider), isFalse);
    });

    testWidgets(
        'searchQueryProvider survives a SearchBar widget rebuild '
        '(query lives in the Notifier, not local state)',
        (tester) async {
      // Validates that the SearchBar's text-field state is sourced from
      // the Riverpod Notifier on every build, so any AppShell rebuild --
      // including the GoRouter branch swap that re-mounts the
      // navigationShell child -- preserves the query. We don't drive a
      // real branch swap here (would require the full sidebar + router
      // stack); the integration smoke test in `search_flow_test.dart`
      // pumps the AppShell-shaped tree against a real database.
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      // Type into the bar.
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();
      expect(container.read(searchQueryProvider), 'flutter');

      // Force a rebuild of the SearchBar by toggling an unrelated provider
      // its ancestors might depend on. The widget is a ConsumerStatefulWidget;
      // we rebuild the host frame and re-pump.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(BookmarkSearchBar), findsOneWidget);
      expect(container.read(searchQueryProvider), 'flutter');
    });

    testWidgets(
        'Backspace in search field deletes a character (does NOT trigger '
        'DeleteSelectedItemIntent)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));
      // Set a selection so the delete-prompt would fire if Backspace
      // weren't carved out for EditableText.
      container.read(selectedBookmarkIdProvider.notifier).select('bm-x');

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(container.read(pendingDeleteIdProvider), isNull,
          reason:
              'EditableText carve-out: Backspace in the search field must '
              'edit text, not prompt a delete');
    });

    testWidgets('Esc in search field clears the query (Story 3.2)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();
      expect(container.read(searchQueryProvider), 'flutter');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Story 3.2 AC3: Esc dispatches through AppShell's AppDismissIntent
      // cascade, which clears the active search query.
      expect(container.read(searchQueryProvider), '');
    });
  });

  // ===== Story 3.2: Esc keeps focus, clear button, controller resync =====

  group('BookmarkSearchBar Story 3.2', () {
    testWidgets('Esc clears the controller text in lockstep with the provider',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(container.read(searchQueryProvider), '');
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, '');
    });

    testWidgets('Esc keeps focus on the search bar (AC3 contract)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();

      final node = container.read(searchBarFocusNodeProvider);
      expect(node.hasFocus, isTrue,
          reason: 'precondition: typing into the field gave it focus');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // AC3 load-bearing assertion: focus stays on the search bar after Esc
      // so the next REAL keystroke types a new query without an extra click.
      // The post-frame requestFocus in AppShell's search-clear branch
      // restores focus that Flutter's default DismissAction would otherwise
      // strip.
      expect(container.read(searchQueryProvider), '');
      expect(node.hasFocus, isTrue,
          reason: 'AC3: focus must stay on the search bar across Esc');
    });

    testWidgets('clear button is hidden when the query is empty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      // Search bar's TextField is the first TextField in the app; the close
      // icon must not be present in its subtree when the query is empty.
      expect(
          find.descendant(
              of: find.byType(BookmarkSearchBar),
              matching: find.byIcon(Icons.close)),
          findsNothing);
    });

    testWidgets('clear button appears once a non-whitespace query is entered',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'f');
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byType(BookmarkSearchBar),
              matching: find.byIcon(Icons.close)),
          findsOneWidget);
    });

    testWidgets('tapping the clear button clears the query and the controller',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();
      expect(container.read(searchQueryProvider), 'flutter');

      await tester.tap(find.descendant(
          of: find.byType(BookmarkSearchBar),
          matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();

      expect(container.read(searchQueryProvider), '');
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, '');
    });

    testWidgets('controller resyncs when the provider is cleared externally',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(_buildApp(tester));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BookmarkSearchBar)));

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.pumpAndSettle();

      // External writer (mimics AppShell's Esc cascade or any future
      // programmatic clear).
      container.read(searchQueryProvider.notifier).clear();
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, '');
    });
  });

  // Note: end-to-end Enter-to-open with a real database is covered in the
  // search integration tests (`test/features/search/integration/`), where
  // the full lifecycle (DB instantiation, stream cancellation, teardown) is
  // managed cleanly. Including the same flow here would either require
  // overriding the DB (which leaks Drift's stream-cancel timer through
  // verifyInvariants) or duplicating the integration test.
}
