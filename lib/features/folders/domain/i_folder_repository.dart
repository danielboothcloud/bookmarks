import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'folder.dart';

abstract interface class IFolderRepository {
  Stream<List<Folder>> watchAll();
  Future<Result<Folder, AppError>> getById(String id);
  Future<Result<Folder, AppError>> save(Folder folder);
}
