import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/search/application/search_providers.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/search/data/search_repository.dart';
import 'package:bookmarks/features/search/domain/i_search_repository.dart';
import 'package:bookmarks/features/search/presentation/widgets/search_bar.dart';
import 'package:bookmarks/features/search/presentation/widgets/search_results_screen.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story 3.1 integration: validates the content-area swap contract
/// (`searchActiveProvider` → SearchBar / SearchResultsScreen / shell) and
/// the reactive bookmark→FTS→search-stream pipeline end-to-end against a
/// real in-memory v6 AppDatabase.
///
/// We pump a stripped-down widget that mirrors AppShell's layout
/// (SearchBar over a content area watching `searchActiveProvider`) rather
/// than the full router, because the full router pulls in the sidebar's
/// folder/tag streams that interact poorly with FakeAsync timers under
/// flutter_test. AppShell-level layout assertions are covered by
/// `core/widgets/app_shell_test.dart`.
///
/// **Why `tester.runAsync`:** Drift's `customSelect.watch()` schedules
/// emissions via `Timer.zero`. Under flutter_test's FakeAsync, those
/// timers don't fire during `pumpAndSettle` -- so the StreamProvider
/// never gets the search results. We bracket stream-dependent operations
/// in `runAsync` so real time elapses, then pump synchronously to make
/// the framework see the rebuilt tree.
void main() {
  /// Mini-AppShell for tests: BookmarkSearchBar at top, content area below
  /// that switches between a placeholder shell and the SearchResultsScreen
  /// based on `searchActiveProvider`. Mirrors AppShell's `_ContentArea`.
  Widget buildMiniShell() {
    return MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BookmarkSearchBar(),
            Expanded(child: _MiniContentArea()),
          ],
        ),
      ),
    );
  }

  Future<void> pumpMini(
    WidgetTester tester,
    AppDatabase db, {
    Map<String?, List<dynamic>>? folderTreeOverride,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            // When folder/tag scope tests want a non-null sidebar selection,
            // override `folderChildrenIndexProvider` with a static map so
            // `searchScopeProvider` doesn't subscribe to Drift's
            // `watchFoldersProvider` (whose Timer.zero emissions don't drain
            // under FakeAsync `pumpAndSettle`).
            if (folderTreeOverride != null)
              folderChildrenIndexProvider.overrideWithValue(
                folderTreeOverride.cast(),
              ),
          ],
          child: buildMiniShell(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester, AppDatabase db) async {
    await tester.runAsync(() async {
      await db.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<void> setQuery(
    WidgetTester tester,
    ProviderContainer container,
    String query,
  ) async {
    container.read(searchQueryProvider.notifier).set(query);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  /// Like [setQuery] but waits until the StreamProvider has actually
  /// emitted data (AsyncData, not AsyncLoading). Necessary for assertions
  /// that depend on the empty-state Padding+Text branch — that only
  /// renders inside the `data: ...` callback of `AsyncValue.when`.
  Future<void> setQueryAndAwaitData(
    WidgetTester tester,
    ProviderContainer container,
    String query,
  ) async {
    container.read(searchQueryProvider.notifier).set(query);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      final state = container.read(searchResultsProvider);
      if (state is AsyncData) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('empty-query state: shell placeholder shows; '
      'SearchResultsScreen NOT in tree', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    expect(find.byType(BookmarkSearchBar), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-shell-placeholder')),
        findsOneWidget);
    expect(find.byType(SearchResultsScreen), findsNothing);

    await teardown(tester, db);
  });

  testWidgets('non-empty query swaps in SearchResultsScreen with '
      'matching BookmarkListItem rows', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final bookmarkRepo = BookmarkRepository(db);
    final now = DateTime.now();
    await bookmarkRepo.save(Bookmark(
      id: 'bm-flutter',
      url: 'https://flutter.dev',
      title: 'Flutter docs',
      createdAt: now,
      updatedAt: now,
    ));
    await bookmarkRepo.save(Bookmark(
      id: 'bm-other',
      url: 'https://example.com',
      title: 'Other thing',
      createdAt: now,
      updatedAt: now,
    ));
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQuery(tester, container, 'flutter');

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-shell-placeholder')), findsNothing);
    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(find.text('Flutter docs'), findsOneWidget);

    await teardown(tester, db);
  });

  testWidgets('adding a matching bookmark while search is active updates '
      'the result list (reactive end-to-end)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final bookmarkRepo = BookmarkRepository(db);
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQuery(tester, container, 'flutter');

    expect(find.byType(BookmarkListItem), findsNothing);

    await tester.runAsync(() async {
      final now = DateTime.now();
      await bookmarkRepo.save(Bookmark(
        id: 'bm-new',
        url: 'https://example.com',
        title: 'Flutter widgets',
        createdAt: now,
        updatedAt: now,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(find.text('Flutter widgets'), findsOneWidget);

    await teardown(tester, db);
  });

  testWidgets('clicking a result row updates selectedBookmarkIdProvider',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final bookmarkRepo = BookmarkRepository(db);
    final now = DateTime.now();
    await bookmarkRepo.save(Bookmark(
      id: 'bm-1',
      url: 'https://flutter.dev',
      title: 'Flutter docs',
      createdAt: now,
      updatedAt: now,
    ));
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQuery(tester, container, 'flutter');

    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(container.read(selectedBookmarkIdProvider), isNull);

    await tester.tap(find.byType(BookmarkListItem).first);
    // BookmarkListItem wraps InkWell in a GestureDetector with onDoubleTap;
    // single-tap firing is deferred past the double-tap window (300ms).
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(container.read(selectedBookmarkIdProvider), 'bm-1');

    await teardown(tester, db);
  });

  // ===== Story 3.2: empty-state inline message (AC2) =====

  testWidgets('empty results render the inline "No bookmarks match" message',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQueryAndAwaitData(tester, container, 'nonexistent');

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.byType(BookmarkListItem), findsNothing);
    expect(find.text('No bookmarks match ‘nonexistent’'),
        findsOneWidget);

    await teardown(tester, db);
  });

  testWidgets('empty-state message uses the trimmed query', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQueryAndAwaitData(tester, container, '  flutter  ');

    expect(find.text('No bookmarks match ‘flutter’'),
        findsOneWidget);
    // Untrimmed variant must NOT appear.
    expect(find.text('No bookmarks match ‘  flutter  ’'),
        findsNothing);

    await teardown(tester, db);
  });

  testWidgets('empty-state message uses typographic single quotes',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQueryAndAwaitData(tester, container, 'xyz');

    final messageFinder = find.textContaining('No bookmarks match');
    final widget = tester.widget<Text>(messageFinder);
    final text = widget.data ?? '';
    expect(text.contains('‘'), isTrue,
        reason: 'expected U+2018 LEFT SINGLE QUOTATION MARK');
    expect(text.contains('’'), isTrue,
        reason: 'expected U+2019 RIGHT SINGLE QUOTATION MARK');
    expect(text.contains("'"), isFalse,
        reason: 'must not use straight apostrophe (U+0027)');

    await teardown(tester, db);
  });

  testWidgets('non-empty results do not render the empty-state message',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final bookmarkRepo = BookmarkRepository(db);
    final now = DateTime.now();
    await bookmarkRepo.save(Bookmark(
      id: 'bm-1',
      url: 'https://flutter.dev',
      title: 'Flutter docs',
      createdAt: now,
      updatedAt: now,
    ));
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQuery(tester, container, 'flutter');

    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(find.textContaining('No bookmarks match'), findsNothing);

    await teardown(tester, db);
  });

  testWidgets(
      'AC1: SearchResultsScreen renders title AND URL highlights for the '
      'active query (terms reach BookmarkListItem -> HighlightedText)',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final bookmarkRepo = BookmarkRepository(db);
    final now = DateTime.now();
    await bookmarkRepo.save(Bookmark(
      id: 'bm-1',
      url: 'https://flutter.dev/docs',
      title: 'Flutter docs',
      createdAt: now,
      updatedAt: now,
    ));
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQuery(tester, container, 'flu');

    expect(find.byType(BookmarkListItem), findsOneWidget);

    // Walk every RichText inside the rendered row and collect every leaf
    // TextSpan that carries the highlight background colour. AC1 says both
    // the title AND the URL must highlight, so we expect at least two
    // distinct highlighted spans (one per HighlightedText surface).
    final richTexts = tester.widgetList<RichText>(find.descendant(
      of: find.byType(BookmarkListItem),
      matching: find.byType(RichText),
    ));
    final highlightedTexts = <String>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor == AppColors.highlightSearch &&
            (span.text?.isNotEmpty ?? false)) {
          highlightedTexts.add(span.text!);
        }
        final children = span.children;
        if (children != null) {
          for (final c in children) {
            walk(c);
          }
        }
      }
    }
    for (final rt in richTexts) {
      walk(rt.text);
    }

    expect(highlightedTexts, contains('Flu'),
        reason: 'title row must highlight "Flu" inside "Flutter docs"');
    expect(highlightedTexts, contains('flu'),
        reason: 'url row must highlight "flu" inside "flutter.dev"');

    await teardown(tester, db);
  });

  // AC4 × button integration: the click path (× → query cleared, controller
  // resync, focus untouched) is covered at widget scope in
  // `test/features/search/presentation/widgets/search_bar_test.dart`
  // ("tapping the clear button clears the query and the controller"). The
  // _ContentArea swap back to the placeholder when `searchQueryProvider`
  // is cleared is covered above in
  // "no selection: clearing returns to the placeholder branch". A combined
  // integration test that performs the actual tap inside the mini-shell
  // leaks a Tooltip-driven SemanticsHandle that survives `ensureSemantics()`
  // teardown; the two halves above transitively validate the parity claim
  // without that infrastructure cost.

  testWidgets('empty-state message uses the muted text colour',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    await setQueryAndAwaitData(tester, container, 'xyz');

    final widget = tester.widget<Text>(
        find.textContaining('No bookmarks match'));
    expect(widget.style?.color, AppColors.textMuted);

    await teardown(tester, db);
  });

  // ===== Story 3.2: clear-with-filter-active (AC7) =====

  /// Programmatic clear under runAsync. With folder/tag scope active,
  /// `searchScopeProvider` watches Drift-backed `watchFoldersProvider`,
  /// which schedules emissions via Timer.zero — those timers don't fire
  /// under FakeAsync (`pumpAndSettle`), so we let real time flow first.
  Future<void> clearAndAwait(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    container.read(searchQueryProvider.notifier).clear();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
      'folder selection survives a search-clear (Esc returns to filter)',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db, folderTreeOverride: const {});

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));

    container.read(selectedFolderIdProvider.notifier).select('folder-a');
    await setQuery(tester, container, 'flutter');

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(container.read(searchActiveProvider), isTrue);

    await clearAndAwait(tester, container);

    expect(container.read(searchActiveProvider), isFalse);
    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(container.read(selectedFolderIdProvider), 'folder-a');

    await teardown(tester, db);
  });

  testWidgets('tag selection survives a search-clear', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db, folderTreeOverride: const {});

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));

    container.read(selectedTagIdProvider.notifier).select('tag-1');
    await setQuery(tester, container, 'flutter');

    expect(container.read(searchActiveProvider), isTrue);

    await clearAndAwait(tester, container);

    expect(container.read(searchActiveProvider), isFalse);
    expect(container.read(selectedTagIdProvider), 'tag-1');

    await teardown(tester, db);
  });

  testWidgets('no selection: clearing returns to the placeholder branch',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));

    expect(container.read(selectedFolderIdProvider), isNull);
    expect(container.read(selectedTagIdProvider), isNull);

    await setQuery(tester, container, 'flutter');
    expect(find.byType(SearchResultsScreen), findsOneWidget);

    await clearAndAwait(tester, container);

    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(find.byKey(const ValueKey('mini-shell-placeholder')),
        findsOneWidget);

    await teardown(tester, db);
  });

  testWidgets('searchRepositoryProvider resolves to a real SearchRepository '
      'when only appDatabaseProvider is overridden', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await pumpMini(tester, db);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BookmarkSearchBar)));
    final repo = container.read(searchRepositoryProvider);
    expect(repo, isA<SearchRepository>());
    expect(repo, isA<ISearchRepository>());

    await teardown(tester, db);
  });
}

/// Mirrors AppShell's `_ContentArea`: switches between a placeholder
/// (the would-be navigationShell) and the SearchResultsScreen based on
/// `searchActiveProvider`. The placeholder carries a ValueKey so the
/// swap is observable in tests.
class _MiniContentArea extends ConsumerWidget {
  const _MiniContentArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchActive = ref.watch(searchActiveProvider);
    if (searchActive) {
      return const SearchResultsScreen();
    }
    return const _MiniShellPlaceholder();
  }
}

class _MiniShellPlaceholder extends StatelessWidget {
  const _MiniShellPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey('mini-shell-placeholder'),
      child: Text('Shell'),
    );
  }
}
