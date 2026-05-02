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

/// Holds the current text in the BookmarkDetailPane's tag input for the
/// CURRENTLY-SELECTED bookmark. Form-local state stored in a Notifier rather
/// than `StatefulWidget._textController` because:
///   1. The detail pane is reused for whichever bookmark is selected;
///      switching selection should clear the input draft (selecting bookmark
///      B should not inherit the half-typed tag from bookmark A). A
///      provider-driven controller seeded by the bookmark id makes this
///      explicit.
///   2. Tests can drive the input without hooking into the widget's internal
///      TextEditingController.
/// Unrelated to the InlineAddForm's pending tags -- THAT list lives in the
/// form's own State (it's discarded on Esc/Save without ever touching this
/// provider).
class TagInputDraftNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String next) => state = next;
  void clear() => state = '';
}

final tagInputDraftProvider =
    NotifierProvider<TagInputDraftNotifier, String>(TagInputDraftNotifier.new);
