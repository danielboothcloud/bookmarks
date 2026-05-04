// TODO(story-2.5): convert to @riverpod once riverpod_generator is unblocked.
// (Same analyzer-version conflict that pins the bookmarks/folders providers --
// see bookmark_providers.dart header.)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../data/tag_repository.dart';
import '../domain/i_tag_repository.dart';
import '../domain/tag.dart';

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
