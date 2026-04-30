import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/bookmark_notifier.dart';
import '../application/bookmark_providers.dart';
import 'widgets/bookmark_list_item.dart';
import 'widgets/inline_add_form.dart';

class BookmarkListScreen extends ConsumerWidget {
  const BookmarkListScreen({super.key});

  void _showForm(WidgetRef ref) {
    ref.read(addFormVisibleProvider.notifier).show();
  }

  void _closeForm(WidgetRef ref) {
    ref.read(addFormVisibleProvider.notifier).hide();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addFormVisible = ref.watch(addFormVisibleProvider);
    final bookmarksAsync = ref.watch(watchBookmarksProvider);
    final saveAsync = ref.watch(bookmarkNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saveAsync.hasError) const _SaveErrorBanner(),
        if (addFormVisible) InlineAddForm(onClose: () => _closeForm(ref)),
        Expanded(
          child: bookmarksAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Could not load bookmarks',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
            data: (bookmarks) {
              if (bookmarks.isEmpty && !addFormVisible) {
                return EmptyState.noBookmarks(
                  onAddBookmark: () => _showForm(ref),
                );
              }
              return ListView.builder(
                itemCount: bookmarks.length,
                itemBuilder: (context, index) => BookmarkListItem(
                  key: ValueKey(bookmarks[index].id),
                  bookmark: bookmarks[index],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        "Couldn't save changes — try again.",
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
