import '../../bookmarks/domain/bookmark.dart';

/// Stream of bookmarks matching [query], ordered by FTS5 BM25 relevance
/// (best first), with `bookmarks.created_at DESC` as the tiebreaker.
///
/// Empty / whitespace-only query returns a stream that emits a single empty
/// list -- callers detect "no search active" via [searchQueryProvider]
/// (or the trim-aware [searchActiveProvider]), not by inspecting the
/// result list shape.
///
/// Optional scoping (Story 3.2):
/// - [folderIds]: when non-null and non-empty, restricts results to
///   bookmarks whose `folder_id` is in this set (typically a folder and
///   its recursive descendants per FR12). Null or empty means no scope.
/// - [tagId]: when non-null, restricts results to bookmarks linked to
///   that tag via `bookmark_tags` (FR15). Null means no scope.
/// In normal operation only one is set; both being set is defensive
/// behaviour (AND-combined) and is not produced by `searchScopeProvider`.
///
/// `Result<T, AppError>` is intentionally NOT used here -- search is a
/// reactive read derivation, not a fallible operation. Errors surface
/// through `StreamProvider`'s built-in `AsyncError` path.
abstract class ISearchRepository {
  Stream<List<Bookmark>> search(
    String query, {
    Set<String>? folderIds,
    String? tagId,
  });
}
