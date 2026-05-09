import '../../bookmarks/domain/bookmark.dart';

/// Stream of bookmarks matching [query], ordered by FTS5 BM25 relevance
/// (best first), with `bookmarks.created_at DESC` as the tiebreaker.
///
/// Empty / whitespace-only query returns a stream that emits a single empty
/// list -- callers detect "no search active" via [searchQueryProvider]
/// (or the trim-aware [searchActiveProvider]), not by inspecting the
/// result list shape.
///
/// `Result<T, AppError>` is intentionally NOT used here -- search is a
/// reactive read derivation, not a fallible operation. Errors surface
/// through `StreamProvider`'s built-in `AsyncError` path.
abstract class ISearchRepository {
  Stream<List<Bookmark>> search(String query);
}
