// TODO(story-2.5): convert to @riverpod once riverpod_generator is unblocked.
// (Same analyzer-version conflict that pins the bookmarks/folders providers --
// see bookmark_providers.dart header.)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../../bookmarks/application/bookmark_providers.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../data/tag_repository.dart';
import '../domain/i_tag_repository.dart';
import '../domain/tag.dart';
import '../domain/tag_with_count.dart';

final tagRepositoryProvider = Provider<ITagRepository>((ref) {
  return TagRepository(ref.watch(appDatabaseProvider));
});

/// Stream of ALL tags, alphabetised case-insensitively. Consumed by the
/// InlineAddForm tag autocomplete (deferred polish) and (Story 2.6) the
/// sidebar tag list.
final watchAllTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});

/// Stream of tags for a single bookmark, in created-order. Family-keyed by
/// bookmark id. Used by BookmarkDetailPane to render the chip row, and by
/// BookmarkListItem / BookmarkCard.
final watchTagsForBookmarkProvider =
    StreamProvider.family<List<Tag>, String>((ref, bookmarkId) {
  return ref.watch(tagRepositoryProvider).watchForBookmark(bookmarkId);
});

// Note: tagInputDraftProvider was removed in the 2.5 code review. The draft
// clearing on bookmark selection change is handled by ValueKey(bookmarkId) on
// _TagsRow, which forces a fresh ConsumerState (and a fresh
// TextEditingController) whenever the selected bookmark changes.

/// Sidebar-facing stream of all tags with their current bookmark counts.
/// Backed by a single Drift query with LEFT JOIN aggregation, so a single
/// emission carries an atomically-consistent (tag, count) pair (no torn
/// reads -- adding a junction row emits ONCE with both the new count and
/// the unchanged tag list).
final watchTagsWithCountsProvider =
    StreamProvider<List<TagWithCount>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAllWithCounts();
});

/// The id of the tag currently filtering the content area in the tags branch.
/// `null` means no tag is selected -- TagsScreen renders the "Select a tag
/// from the sidebar" placeholder. Mirrors the single-id Notifier shape of
/// [selectedFolderIdProvider] (folder_providers.dart) and
/// [selectedBookmarkIdProvider] (bookmark_providers.dart).
class SelectedTagIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
  void clear() => state = null;
}

final selectedTagIdProvider =
    NotifierProvider<SelectedTagIdNotifier, String?>(
        SelectedTagIdNotifier.new);

/// Stream of bookmarks linked to [tagId]. Family-keyed so navigating between
/// tags doesn't disturb the all-bookmarks watch -- and so two consumers
/// reading the same tag id share the same Drift subscription. Re-emits on
/// any change to `bookmarks` or `bookmark_tags`.
///
/// Lives in `tag_providers.dart` (not `bookmark_providers.dart`) because
/// the consumer is the tag-filtering surface (TagsScreen) -- a UI concept
/// that belongs to the tags feature. The repo method
/// (IBookmarkRepository.watchByTagId) is correctly in the bookmarks feature;
/// the StreamProvider that exposes it to a presentation layer is a
/// tags-feature concern. (Same shape as folder_providers.dart's derived
/// views over bookmark filtering downstream.)
final watchBookmarksForTagProvider =
    StreamProvider.family<List<Bookmark>, String>((ref, tagId) {
  return ref.watch(bookmarkRepositoryProvider).watchByTagId(tagId);
});
