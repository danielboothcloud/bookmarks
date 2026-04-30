// TODO(story-1.2): replace with @riverpod AsyncNotifier once codegen unblocked.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/bookmark.dart';

class BookmarkNotifier extends AsyncNotifier<List<Bookmark>> {
  @override
  Future<List<Bookmark>> build() async => const <Bookmark>[];
}

final bookmarkNotifierProvider =
    AsyncNotifierProvider<BookmarkNotifier, List<Bookmark>>(
  BookmarkNotifier.new,
);
