// TODO(story-1.2): convert to @riverpod StreamProviders once riverpod_generator
// is unblocked (see Story 1.1 Completion Notes). Manual Provider declarations
// are used until then.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bookmark_repository.dart';
import '../domain/bookmark.dart';
import '../domain/i_bookmark_repository.dart';

final bookmarkRepositoryProvider = Provider<IBookmarkRepository>((ref) {
  return const BookmarkRepository();
});

final watchBookmarksProvider = StreamProvider<List<Bookmark>>((ref) {
  return ref.watch(bookmarkRepositoryProvider).watchAll();
});
