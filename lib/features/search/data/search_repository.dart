import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../domain/i_search_repository.dart';
import '../domain/search_tokenizer.dart';

class SearchRepository implements ISearchRepository {
  SearchRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Bookmark>> search(
    String query, {
    Set<String>? folderIds,
    String? tagId,
  }) {
    final matchString = _toMatchQuery(query);
    if (matchString.isEmpty) {
      return Stream.value(const <Bookmark>[]);
    }

    // BM25 ranks results: lower scores = better match (FTS5 idiom).
    // ORDER BY bm25(...) ASC gives best-first. created_at DESC breaks
    // relevance ties so equal-scored results have a predictable order.
    //
    // readsFrom: the FTS table is a virtual table that doesn't appear in
    // Drift's table set (and Drift can't observe virtual tables anyway),
    // so it deliberately is NOT included here. Listing the SOURCE tables
    // (bookmarks, bookmark_tags, tags) tells the stream to invalidate on
    // any underlying mutation -- the FTS5 sync triggers ensure those
    // mutations have already propagated to the index by the time the
    // stream re-runs the query. Do not "fix" this by adding `bookmarks_fts`
    // to readsFrom; it has no effect and is misleading.
    final whereClauses = <String>['bookmarks_fts MATCH ?'];
    final variables = <Variable<Object>>[Variable<String>(matchString)];

    // Folder scope (Story 3.2 AC5): empty/null is no-op; non-empty restricts
    // to bookmarks whose folder_id is in the provided descendant set.
    if (folderIds != null && folderIds.isNotEmpty) {
      final placeholders = List.filled(folderIds.length, '?').join(', ');
      whereClauses.add('b.folder_id IN ($placeholders)');
      variables.addAll(folderIds.map(Variable<String>.new));
    }

    // Tag scope (Story 3.2 AC6): EXISTS subquery returns each `b.*` row at
    // most once even if a future schema change permitted multi-row matches.
    if (tagId != null) {
      whereClauses.add(
        'EXISTS (SELECT 1 FROM bookmark_tags bt '
        'WHERE bt.bookmark_id = b.id AND bt.tag_id = ?)',
      );
      variables.add(Variable<String>(tagId));
    }

    final whereSql = whereClauses.join(' AND ');

    return _db
        .customSelect(
          'SELECT b.* FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE $whereSql '
          'ORDER BY bm25(bookmarks_fts), b.created_at DESC',
          variables: variables,
          readsFrom: {_db.bookmarks, _db.bookmarkTags, _db.tags},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => Bookmark.fromDriftRow(
                  id: r.read<String>('id'),
                  url: r.read<String>('url'),
                  title: r.read<String>('title'),
                  notes: r.readNullable<String>('notes'),
                  folderId: r.readNullable<String>('folder_id'),
                  faviconBase64: r.readNullable<String>('favicon_base64'),
                  createdAt: r.read<int>('created_at'),
                  updatedAt: r.read<int>('updated_at'),
                ),
              )
              .toList(growable: false),
        );
  }

  /// Sanitises [userQuery] into an FTS5 MATCH expression with prefix
  /// matching on every token. Returns the empty string for queries that
  /// reduce to zero usable tokens (empty / whitespace-only / a query
  /// composed only of non-token characters).
  ///
  /// Tokenisation is delegated to [searchTokens] in `search_tokenizer.dart`
  /// so the visible highlight spans (which read the same tokens via
  /// `searchQueryTokensProvider`) cannot drift from what BM25 matches.
  static String _toMatchQuery(String userQuery) {
    return searchTokens(userQuery).map((t) => '$t*').join(' ');
  }
}
