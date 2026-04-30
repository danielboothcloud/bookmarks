// TODO(story-1.2): replace with @riverpod AsyncNotifier once codegen unblocked.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/result.dart';
import '../domain/bookmark.dart';
import 'bookmark_providers.dart';

class BookmarkNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> addBookmark({
    required String url,
    String? title,
    String? folderId,
  }) async {
    final trimmedUrl = url.trim();
    final trimmedTitle = (title ?? '').trim();
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: _uuid.v4(),
      url: trimmedUrl,
      title: trimmedTitle.isEmpty ? trimmedUrl : trimmedTitle,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    );

    state = const AsyncValue<void>.loading();
    final result = await ref.read(bookmarkRepositoryProvider).save(bookmark);
    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
    }
  }
}

final bookmarkNotifierProvider =
    AsyncNotifierProvider<BookmarkNotifier, void>(BookmarkNotifier.new);
