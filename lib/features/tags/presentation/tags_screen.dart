import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sidebar_selection_placeholder.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../../bookmarks/presentation/widgets/bookmark_list_item.dart';
import '../application/tag_providers.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTagId = ref.watch(selectedTagIdProvider);
    if (selectedTagId == null) {
      return const SidebarSelectionPlaceholder(
        message: 'Select a tag from the sidebar',
      );
    }
    // Defensive: selection refers to a tag that no longer exists (deleted by
    // sync merge in Story 4.3, or future tag-mutation UX). Treat identical
    // to "no selection" so the content area stays sensible. Only trust the
    // absence after the tags stream has emitted at least once; otherwise
    // the family stream emits empty and the empty-state path renders
    // correctly.
    final tagsAsync = ref.watch(watchTagsWithCountsProvider);
    final tagsList = tagsAsync.value;
    if (tagsList != null) {
      final tagExists =
          tagsList.any((twc) => twc.tag.id == selectedTagId);
      if (!tagExists) {
        return const SidebarSelectionPlaceholder(
          message: 'Select a tag from the sidebar',
        );
      }
    }
    final bookmarksAsync =
        ref.watch(watchBookmarksForTagProvider(selectedTagId));
    // hasError first: a StreamProvider that emits an error and is then
    // re-read transitions through AsyncLoading(retrying: true) with the
    // error still attached -- .when() routes by runtime subtype and would
    // miss that state, hiding the error UI. Gate explicitly on hasError to
    // surface the inline failure message.
    if (bookmarksAsync.hasError) {
      return const ContentLoadErrorPlaceholder(
        message: 'Could not load bookmarks',
      );
    }
    return bookmarksAsync.when(
      loading: () => const SizedBox.shrink(),
      // Unreachable in practice (hasError gate above), retained as
      // defence-in-depth for future AsyncValue subtypes.
      error: (_, _) => const ContentLoadErrorPlaceholder(
        message: 'Could not load bookmarks',
      ),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return const _EmptyTagPlaceholder();
        }
        return _BookmarkList(bookmarks: bookmarks);
      },
    );
  }
}

class _EmptyTagPlaceholder extends StatelessWidget {
  const _EmptyTagPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No bookmarks with this tag',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({required this.bookmarks});
  final List<Bookmark> bookmarks;
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: bookmarks.length,
      itemBuilder: (context, index) => BookmarkListItem(
        key: ValueKey(bookmarks[index].id),
        bookmark: bookmarks[index],
      ),
    );
  }
}
