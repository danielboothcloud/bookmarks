// TODO(story-1.2): convert to @riverpod once riverpod_generator is unblocked.
// Re-checked 2026-04-30: still blocked by analyzer version conflict between
// drift_dev ^2.32.0 (needs analyzer 10/11/12) and custom_lint (needs analyzer
// 7/8). Track via Story 1.1 deferred follow-up.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../data/bookmark_repository.dart';
import '../domain/bookmark.dart';
import '../domain/i_bookmark_repository.dart';

final bookmarkRepositoryProvider = Provider<IBookmarkRepository>((ref) {
  return BookmarkRepository(ref.watch(appDatabaseProvider));
});

final watchBookmarksProvider = StreamProvider<List<Bookmark>>((ref) {
  return ref.watch(bookmarkRepositoryProvider).watchAll();
});

/// Controls visibility of the inline add form. Flipped by the global
/// `Cmd+N` AddBookmarkIntent in AppShell, watched by BookmarkListScreen.
class AddFormVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
}

final addFormVisibleProvider =
    NotifierProvider<AddFormVisibleNotifier, bool>(AddFormVisibleNotifier.new);
