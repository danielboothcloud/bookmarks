import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import '../domain/folder.dart';
import '../domain/i_folder_repository.dart';

class FolderRepository implements IFolderRepository {
  FolderRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Folder>> watchAll() {
    final query = _db.select(_db.folders)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
          (rows) => rows.map(Folder.fromDrift).toList(growable: false),
        );
  }

  @override
  Future<Result<Folder, AppError>> getById(String id) async {
    try {
      final row = await (_db.select(_db.folders)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        return const Err<Folder, AppError>(NotFoundError());
      }
      return Ok<Folder, AppError>(Folder.fromDrift(row));
    } catch (e) {
      return Err<Folder, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<Folder, AppError>> save(Folder folder) async {
    try {
      await _db
          .into(_db.folders)
          .insertOnConflictUpdate(_toCompanion(folder));
      return Ok<Folder, AppError>(folder);
    } catch (e) {
      return Err<Folder, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<({int folders, int bookmarks}), AppError>> deleteCascade(
    Set<String> folderIds,
  ) async {
    if (folderIds.isEmpty) {
      return const Ok<({int folders, int bookmarks}), AppError>(
        (folders: 0, bookmarks: 0),
      );
    }
    try {
      final result = await _db.transaction(() async {
        // Junctions first, then bookmarks, then folders. SQLite has no FK
        // enforcement on bookmark_tags (architecture rejects FKs), so the
        // junction rows for the about-to-be-deleted bookmarks must be
        // explicitly cleaned -- otherwise they linger as orphans, inflating
        // the sidebar tag count via TagRepository.watchAllWithCounts'
        // COUNT(bt.bookmark_id) aggregation. The bookmark/folder ordering is
        // preserved so a hypothetical future FK migration with ON DELETE
        // CASCADE doesn't require re-ordering.
        await _db.customUpdate(
          'DELETE FROM bookmark_tags WHERE bookmark_id IN ('
          '  SELECT id FROM bookmarks WHERE folder_id IN ('
          '${List.filled(folderIds.length, '?').join(',')}'
          '  )'
          ')',
          variables: folderIds.map(Variable<String>.new).toList(),
          updates: {_db.bookmarkTags},
        );
        final bookmarksDeleted =
            await (_db.delete(_db.bookmarks)
                  ..where((t) => t.folderId.isIn(folderIds)))
                .go();
        final foldersDeleted =
            await (_db.delete(_db.folders)
                  ..where((t) => t.id.isIn(folderIds)))
                .go();
        // Sweep tags whose last junction was just removed by the cascade
        // (revised FR16, v5). Cheap anti-join; scoped to tags with zero
        // remaining junctions.
        await _db.customUpdate(
          'DELETE FROM tags '
          'WHERE id NOT IN (SELECT DISTINCT tag_id FROM bookmark_tags)',
          updates: {_db.tags},
        );
        return (folders: foldersDeleted, bookmarks: bookmarksDeleted);
      });
      return Ok<({int folders, int bookmarks}), AppError>(result);
    } catch (e) {
      return Err<({int folders, int bookmarks}), AppError>(
        StorageError(e.toString()),
      );
    }
  }

  FoldersCompanion _toCompanion(Folder f) => FoldersCompanion(
        id: Value(f.id),
        name: Value(f.name),
        parentId: Value(f.parentId),
        createdAt: Value(f.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(f.updatedAt.millisecondsSinceEpoch),
      );
}
