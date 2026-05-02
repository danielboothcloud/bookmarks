import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'folder.dart';

abstract interface class IFolderRepository {
  Stream<List<Folder>> watchAll();
  Future<Result<Folder, AppError>> getById(String id);
  Future<Result<Folder, AppError>> save(Folder folder);

  /// Atomically deletes every folder whose id is in [folderIds] AND every
  /// bookmark whose folderId is in [folderIds]. Wraps both deletes in a
  /// single Drift transaction so a mid-statement failure rolls everything
  /// back -- partial cascade leaves the database in a half-deleted state
  /// that cascade-aware UI cannot detect (Architecture FR9 resolution).
  ///
  /// Returns the count of (folders, bookmarks) deleted on success. Empty
  /// [folderIds] is a defensive no-op returning (0, 0) -- callers should
  /// not depend on this branch but it prevents an empty `IN ()` SQL error
  /// if a caller ever passes an empty descendant set.
  Future<Result<({int folders, int bookmarks}), AppError>> deleteCascade(
    Set<String> folderIds,
  );
}
