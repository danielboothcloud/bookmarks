// TODO(story-1.2): implement against AppDatabase once Bookmarks table exists.

import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import '../domain/bookmark.dart';
import '../domain/i_bookmark_repository.dart';

class BookmarkRepository implements IBookmarkRepository {
  const BookmarkRepository();

  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(StorageError('not implemented'));
}
