import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import '../domain/bookmark.dart';
import '../domain/i_bookmark_repository.dart';

class BookmarkRepository implements IBookmarkRepository {
  BookmarkRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Bookmark>> watchAll() {
    final query = _db.select(_db.bookmarks)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map(
          (rows) => rows.map(Bookmark.fromDrift).toList(growable: false),
        );
  }

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) {
    // Inner join via custom SQL -- the typed Drift join API works but the
    // shape (SELECT b.* with INNER JOIN) is so direct in raw SQL that the
    // typed builder would obscure rather than clarify. Mirrors the rationale
    // in `TagRepository.watchForBookmark`.
    //
    // INNER JOIN (not LEFT JOIN) is intentional: the contract is "bookmarks
    // WITH this tag". The bookmark-delete and folder-cascade-delete paths
    // both clean junction rows in their own transactions, so under normal
    // operation the join wouldn't drop anything. The INNER JOIN remains as
    // defence-in-depth for a future sync-merge path (Story 4.3) that may
    // briefly receive a tag link before the corresponding bookmark write.
    return _db
        .customSelect(
          'SELECT b.* FROM bookmarks b '
          'INNER JOIN bookmark_tags bt ON bt.bookmark_id = b.id '
          'WHERE bt.tag_id = ? '
          'ORDER BY b.created_at DESC',
          variables: [Variable<String>(tagId)],
          readsFrom: {_db.bookmarks, _db.bookmarkTags},
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
                  faviconBase64:
                      r.readNullable<String>('favicon_base64'),
                  createdAt: r.read<int>('created_at'),
                  updatedAt: r.read<int>('updated_at'),
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async {
    try {
      final row = await (_db.select(_db.bookmarks)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        return const Err<Bookmark, AppError>(NotFoundError());
      }
      return Ok<Bookmark, AppError>(Bookmark.fromDrift(row));
    } catch (e) {
      return Err<Bookmark, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    try {
      await _db
          .into(_db.bookmarks)
          .insertOnConflictUpdate(_toCompanion(bookmark));
      return Ok<Bookmark, AppError>(bookmark);
    } catch (e) {
      return Err<Bookmark, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<void, AppError>> delete(String id) async {
    try {
      final affected = await _db.transaction(() async {
        // Cascade-clean junction rows first. SQLite has no FK enforcement on
        // bookmark_tags (architecture rejects FKs), so an unreferenced
        // junction stays in the table and inflates the sidebar tag count
        // (TagRepository.watchAllWithCounts uses COUNT(bt.bookmark_id), which
        // only joins on tag_id -- it can't tell the bookmark is gone). The
        // user-visible filter list (BookmarkRepository.watchByTagId) hides
        // orphans via INNER JOIN, but the count/list mismatch is a confusing
        // UX we resolve by maintaining referential integrity at the
        // application layer.
        //
        // The third statement enforces revised FR16 (v5): tags whose last
        // junction was just removed are hard-deleted, so a "0 (orphan)" row
        // never appears in the sidebar. Targeted to tags that were actually
        // linked to this bookmark -- not a full sweep.
        await (_db.delete(_db.bookmarkTags)
              ..where((t) => t.bookmarkId.equals(id)))
            .go();
        final deleted = await (_db.delete(_db.bookmarks)
              ..where((t) => t.id.equals(id)))
            .go();
        // Sweep tags whose last junction was just removed. Cheap (PK + indexed
        // anti-join). Scoped to tags that have zero junctions -- tags still
        // linked elsewhere are untouched.
        await _db.customUpdate(
          'DELETE FROM tags '
          'WHERE id NOT IN (SELECT DISTINCT tag_id FROM bookmark_tags)',
          updates: {_db.tags},
        );
        return deleted;
      });
      if (affected == 0) {
        return const Err<void, AppError>(NotFoundError());
      }
      return const Ok<void, AppError>(null);
    } catch (e) {
      return Err<void, AppError>(StorageError(e.toString()));
    }
  }

  BookmarksCompanion _toCompanion(Bookmark b) => BookmarksCompanion(
        id: Value(b.id),
        url: Value(b.url),
        title: Value(b.title),
        notes: Value(b.notes),
        folderId: Value(b.folderId),
        faviconBase64: Value(b.faviconBase64),
        createdAt: Value(b.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(b.updatedAt.millisecondsSinceEpoch),
      );
}
