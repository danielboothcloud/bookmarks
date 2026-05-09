import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
import 'package:bookmarks/features/search/application/search_providers.dart';
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

  Future<void> pumpMini(WidgetTester tester, AppDatabase db) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
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
