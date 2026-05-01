import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../bookmarks/application/bookmark_providers.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../../bookmarks/presentation/widgets/bookmark_card.dart';
import '../application/folder_providers.dart';
import '../domain/folder.dart';

class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedFolderIdProvider);
    if (selectedId == null) {
      return const _NoFolderSelectedPlaceholder();
    }
    final folders =
        ref.watch(watchFoldersProvider).value ?? const <Folder>[];
    final byParent = ref.watch(folderChildrenIndexProvider);
    // Defensive: selection refers to a folder that no longer exists (deleted
    // by the future Story 2.4 cascade or a sync merge). Treat identical to
    // "no selection" so the content area stays sensible -- calmer than a
    // crash or jumping the user away.
    final folderExists = folders.any((f) => f.id == selectedId);
    if (!folderExists) {
      return const _NoFolderSelectedPlaceholder();
    }
    final descendantIds = collectFolderDescendants(selectedId, byParent);
    final bookmarksAsync = ref.watch(watchBookmarksProvider);
    // Check hasError first: a StreamProvider that emits an error and is
    // then re-read transitions through AsyncLoading(retrying: true) with
    // the error attached. .when() dispatches by runtime subtype and would
    // route that state to the loading branch, hiding the error UI -- so we
    // gate explicitly on hasError to surface the inline failure message.
    if (bookmarksAsync.hasError) {
      return const _BookmarksLoadError();
    }
    return bookmarksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const _BookmarksLoadError(),
      data: (bookmarks) {
        final filtered = bookmarks
            .where((b) =>
                b.folderId != null && descendantIds.contains(b.folderId))
            .toList(growable: false);
        if (filtered.isEmpty) {
          return const _EmptyFolderPlaceholder();
        }
        return _BookmarkGrid(bookmarks: filtered);
      },
    );
  }
}

class _NoFolderSelectedPlaceholder extends StatelessWidget {
  const _NoFolderSelectedPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a folder from the sidebar',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _EmptyFolderPlaceholder extends StatelessWidget {
  const _EmptyFolderPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No bookmarks in this folder',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _BookmarksLoadError extends StatelessWidget {
  const _BookmarksLoadError();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        'Could not load bookmarks',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _BookmarkGrid extends StatelessWidget {
  const _BookmarkGrid({required this.bookmarks});
  final List<Bookmark> bookmarks;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.4,
        ),
        itemCount: bookmarks.length,
        itemBuilder: (context, index) => BookmarkCard(
          key: ValueKey(bookmarks[index].id),
          bookmark: bookmarks[index],
        ),
      ),
    );
  }
}
