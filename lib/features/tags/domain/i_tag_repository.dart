import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import 'tag.dart';
import 'tag_with_count.dart';

abstract interface class ITagRepository {
  /// All tags ordered alphabetically by name (case-insensitive). The alpha
  /// order is for sidebar / picker presentation (FR16, Story 2.6); alphabetical
  /// reads better than createdAt for tags because users mentally search the
  /// tag list, not chronologically scan it.
  Stream<List<Tag>> watchAll();

  /// All tags (alpha order, case-insensitive) joined with their current
  /// bookmark count via LEFT JOIN on the bookmark_tags junction. Tags with
  /// zero linked bookmarks emit with count = 0 (FR16 -- tags survive their
  /// last bookmark; sidebar shows count = 0 cases). Reactive: re-emits on
  /// any change to either `tags` or `bookmark_tags`.
  Stream<List<TagWithCount>> watchAllWithCounts();

  /// Tags currently linked to [bookmarkId] via the junction. Returned in
  /// `BookmarkTags.createdAt asc` order so the chip order matches the order
  /// the user added them -- predictable rather than alphabetical.
  Stream<List<Tag>> watchForBookmark(String bookmarkId);

  Future<Result<Tag, AppError>> getById(String id);

  /// Looks up a tag by name (case-insensitive). Used by the upsert flow:
  /// "find or create". Returns Err(NotFoundError) when no tag with that name
  /// exists OR when the input trims to empty.
  Future<Result<Tag, AppError>> findByName(String name);

  /// Idempotent upsert. If a tag with the same `lower(name)` exists, returns
  /// it unchanged (createdAt preserved). Otherwise creates a new tag with
  /// [name] verbatim and a fresh UUID v4. The functional UNIQUE index makes
  /// this race-safe at the SQL layer: concurrent insert attempts will fail
  /// with a UNIQUE violation, which the implementation catches and re-resolves
  /// via findByName.
  Future<Result<Tag, AppError>> upsertByName(String name);

  /// Inserts a junction row. Idempotent via INSERT OR IGNORE on the composite
  /// PK -- a duplicate add is a calm no-op.
  Future<Result<void, AppError>> linkBookmarkTag(
    String bookmarkId,
    String tagId,
  );

  /// Deletes the junction row. If this was the tag's LAST junction, the Tag
  /// row is also deleted in the same transaction (revised FR16, v5: tags do
  /// NOT survive their last bookmark -- a count = 0 row in the sidebar is
  /// confusing UX, and re-typing the same name later transparently creates a
  /// fresh tag via upsertByName). Idempotent: removing a chip that's already
  /// gone (e.g. via a sync merge) is a calm no-op.
  Future<Result<void, AppError>> unlinkBookmarkTag(
    String bookmarkId,
    String tagId,
  );

  /// Atomic create-bookmark-with-tags helper. Used by the InlineAddForm path
  /// so a partial failure (junction insert fails after tag create succeeds)
  /// leaves NO orphan tag rows -- the whole transaction rolls back. Names
  /// list may contain duplicates; the implementation dedupes case-insensitively
  /// via upsertByName.
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  });
}
