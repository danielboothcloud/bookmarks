// TODO(story-1.2): expand with full CRUD signature returning Result types.
// Interface stub so the data and application layers can depend on this path.

import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'bookmark.dart';

abstract interface class IBookmarkRepository {
  Stream<List<Bookmark>> watchAll();
  Future<Result<Bookmark, AppError>> getById(String id);
}
