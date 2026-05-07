import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'bookmark.dart';

abstract interface class IBookmarkRepository {
  Stream<List<Bookmark>> watchAll();

  /// Bookmarks linked to [tagId] via the `bookmark_tags` junction. Returned
  /// in the same `createdAt desc` order as [watchAll] so the tag-filter view
  /// list ordering matches the all-bookmarks list ordering -- users carry the
  /// same mental model across views. Reactive: re-emits on changes to either
  /// `bookmarks` or `bookmark_tags`.
  Stream<List<Bookmark>> watchByTagId(String tagId);

  Future<Result<Bookmark, AppError>> getById(String id);
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark);
  Future<Result<void, AppError>> delete(String id);
}
