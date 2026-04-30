import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'bookmark.dart';

abstract interface class IBookmarkRepository {
  Stream<List<Bookmark>> watchAll();
  Future<Result<Bookmark, AppError>> getById(String id);
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark);
  Future<Result<void, AppError>> delete(String id);
}
