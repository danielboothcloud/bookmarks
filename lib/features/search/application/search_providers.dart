import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../data/search_repository.dart';
import '../domain/i_search_repository.dart';

final searchRepositoryProvider = Provider<ISearchRepository>((ref) {
  return SearchRepository(ref.watch(appDatabaseProvider));
});

/// The current free-text search query as the user typed it. Updated on
/// every keystroke from the search bar's TextField. The raw value preserves
/// leading / trailing whitespace; the trim-aware [searchActiveProvider]
/// derivation is the canonical "is search active?" predicate.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;

  void clear() => state = '';
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

/// True when the user has entered a non-empty search query (after trim).
/// AppShell's content-area swap watches this; deferred-to-3.2 features
/// (clear button, Esc-to-clear) will gate on it too.
final searchActiveProvider = Provider<bool>((ref) {
  return ref.watch(searchQueryProvider).trim().isNotEmpty;
});

/// Stream of search results for the current query. Re-emits on every
/// underlying-data change via the repository's `readsFrom` set, so the
/// list stays current without explicit invalidation.
final searchResultsProvider = StreamProvider<List<Bookmark>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(searchRepositoryProvider).search(query);
});

/// FocusNode for the SearchBar's TextField. Owned by a Provider so
/// AppShell's `FocusSearchIntent` action can request focus on it from
/// outside the SearchBar widget tree without a brittle GlobalKey.
final searchBarFocusNodeProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search-bar');
  ref.onDispose(node.dispose);
  return node;
});
