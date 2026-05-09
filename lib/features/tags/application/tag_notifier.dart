import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import 'tag_providers.dart';

/// Mutation surface for tag operations. Mirrors BookmarkNotifier and
/// FolderNotifier shape: `AsyncNotifier<void>` with loading/data/error lifecycle
/// so a future banner could read `tagNotifierProvider.hasError`. Read state
/// via watchAllTagsProvider / watchTagsForBookmarkProvider.
class TagNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Detail-pane "add a tag" path. Upserts the tag by name (case-insensitive
  /// dedup), then links it to the bookmark. Empty/whitespace names are silent
  /// no-ops (calm-cancel pattern from FolderNotifier renameFolder). Returns
  /// void; the chip appears via the reactive stream from
  /// watchTagsForBookmarkProvider.
  Future<void> addTagToBookmark({
    required String bookmarkId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = const AsyncValue<void>.data(null);
      return;
    }
    state = const AsyncValue<void>.loading();
    final repo = ref.read(tagRepositoryProvider);
    final upsert = await repo.upsertByName(trimmed);
    switch (upsert) {
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
        return;
      case Ok(:final value):
        final link = await repo.linkBookmarkTag(bookmarkId, value.id);
        switch (link) {
          case Ok():
            state = const AsyncValue<void>.data(null);
          case Err(:final error):
            state = AsyncValue<void>.error(error, StackTrace.current);
        }
    }
  }

  /// Detail-pane "remove this chip" path. Idempotent at the repo layer (Ok
  /// regardless of whether the row existed). The Tag itself is NOT deleted
  /// -- FR16 / Story 2.6 needs unused tags visible in the sidebar with
  /// count = 0.
  Future<void> removeTagFromBookmark({
    required String bookmarkId,
    required String tagId,
  }) async {
    state = const AsyncValue<void>.loading();
    final result =
        await ref.read(tagRepositoryProvider).unlinkBookmarkTag(
              bookmarkId,
              tagId,
            );
    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
    }
  }
}

final tagNotifierProvider =
    AsyncNotifierProvider<TagNotifier, void>(TagNotifier.new);
