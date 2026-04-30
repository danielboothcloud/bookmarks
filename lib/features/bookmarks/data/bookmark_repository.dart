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
