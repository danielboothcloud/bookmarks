import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../domain/i_search_repository.dart';

class SearchRepository implements ISearchRepository {
  SearchRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Bookmark>> search(String query) {
    final matchString = _toMatchQuery(query);
    if (matchString.isEmpty) {
      return Stream.value(const <Bookmark>[]);
    }

    // BM25 ranks results: lower scores = better match (FTS5 idiom).
    // ORDER BY bm25(...) ASC gives best-first. created_at DESC breaks
    // relevance ties so equal-scored results have a predictable order.
    //
    // readsFrom: the FTS table is a virtual table that doesn't appear in
    // Drift's table set, so Drift can't auto-track changes to it. Listing
    // the SOURCE tables (bookmarks, bookmark_tags, tags) tells the stream
    // to invalidate on any underlying mutation -- the FTS5 sync triggers
    // ensure those mutations have already propagated to the index by the
    // time the stream re-runs the query.
    return _db
        .customSelect(
          'SELECT b.* FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ? '
          'ORDER BY bm25(bookmarks_fts), b.created_at DESC',
          variables: [Variable<String>(matchString)],
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
  /// reduce to zero usable tokens (empty / whitespace-only / FTS5
  /// special-character-only).
  ///
  /// We do NOT expose FTS5's query language to the user -- the search bar
  /// is a free-text input. Operator characters are stripped so a user
  /// typing `c++` or `(quick)` doesn't trigger an FTS5 syntax error.
  static String _toMatchQuery(String userQuery) {
    final cleaned = userQuery.replaceAll(_ftsSpecialChars, ' ');
    final tokens = cleaned
        .split(_whitespace)
        .where((t) => t.isNotEmpty)
        .map((t) => '$t*')
        .toList();
    return tokens.join(' ');
  }

  // FTS5 query-language operator characters; stripped before tokenisation.
  static final RegExp _ftsSpecialChars = RegExp(r'["*:()^+\-~]');
  static final RegExp _whitespace = RegExp(r'\s+');
}
