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

  FoldersCompanion _toCompanion(Folder f) => FoldersCompanion(
        id: Value(f.id),
        name: Value(f.name),
        parentId: Value(f.parentId),
        createdAt: Value(f.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(f.updatedAt.millisecondsSinceEpoch),
      );
}
