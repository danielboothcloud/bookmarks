import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../bookmarks/presentation/widgets/bookmark_list_item.dart';
import '../../application/search_providers.dart';

/// Renders the active-search results in the content area, swapped in by
/// AppShell when `searchActiveProvider` is true. Reuses [BookmarkListItem]
/// so click / double-click / Enter / focus-claim semantics match Stories
/// 1.4 / 1.5 / 2.4 exactly.
///
/// Story 3.1 ships an empty (silent) result list when there are no
/// matches; Story 3.2 layers in the inline "No bookmarks match '[query]'"
/// message + the highlight + Esc-to-clear behaviour.
class SearchResultsScreen extends ConsumerWidget {
  const SearchResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return resultsAsync.when(
      // Loading: hold the layout silent. The first emission lands within
      // a frame at this app's scale, and a spinner would feel like
      // un-calm churn for sub-frame work.
      loading: () => const SizedBox.shrink(),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'Could not load search results',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
      ),
      data: (results) {
        if (results.isEmpty) return const SizedBox.shrink();
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) => BookmarkListItem(
            key: ValueKey(results[index].id),
            bookmark: results[index],
          ),
        );
      },
    );
  }
}
