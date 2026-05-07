import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/tag_providers.dart';
import '../../domain/tag_with_count.dart';

class TagList extends ConsumerWidget {
  const TagList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(watchTagsWithCountsProvider);
    return tagsAsync.when(
      loading: () => const SizedBox.shrink(),
      // Sidebar surface -- swallow stream errors quietly. The TagList is a
      // browse affordance; surfacing a loud error in the sidebar would be
      // disproportionate (the all-bookmarks list still works). A future
      // observability story can hook a logger in here.
      error: (_, _) => const SizedBox.shrink(),
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TagSectionHeader(),
            for (final tagWithCount in tags)
              _TagRow(
                key: ValueKey(tagWithCount.tag.id),
                tagWithCount: tagWithCount,
              ),
          ],
        );
      },
    );
  }
}

class _TagSectionHeader extends StatelessWidget {
  const _TagSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        'TAGS',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          color: AppColors.textSidebar,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TagRow extends ConsumerStatefulWidget {
  const _TagRow({required this.tagWithCount, super.key});
  final TagWithCount tagWithCount;

  @override
  ConsumerState<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends ConsumerState<_TagRow> {
  // skipTraversal: tag rows are mouse-click only for MVP (keyboard sidebar
  // nav today only walks the folder tree -- arrow-key intents in
  // app_shell.dart are folder-scoped). The focus node exists solely to keep
  // primary focus inside AppShell's Shortcuts subtree on mouse click,
  // mirroring the rationale on `_SidebarTileState._focusNode` and
  // `_FolderRowState._rowFocusNode`.
  final _focusNode = FocusNode(
    debugLabel: 'tag-row',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTagId = ref.watch(selectedTagIdProvider);
    final isSelected = selectedTagId == widget.tagWithCount.tag.id;
    final color = isSelected ? AppColors.accent : AppColors.textSidebar;
    final count = widget.tagWithCount.count;
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${widget.tagWithCount.tag.name}, $count ${count == 1 ? 'bookmark' : 'bookmarks'}',
      child: InkWell(
        focusNode: _focusNode,
        onTap: () {
          _focusNode.requestFocus();
          ref
              .read(selectedTagIdProvider.notifier)
              .select(widget.tagWithCount.tag.id);
          // Navigate to the tags branch. The TagList lives inside Sidebar,
          // which is a SIBLING of the navigation shell (not a descendant),
          // so `StatefulNavigationShell.maybeOf(context)` returns null --
          // we route through GoRouter instead. Mirrors the fallback path
          // in folder_tree.dart's row InkWell onTap. Selection is the
          // load-bearing AC; navigation is best-effort if the router is
          // absent (test-time outside an app harness).
          GoRouter.maybeOf(context)?.go(AppRoutes.tags);
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.12)
                : null,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.tagWithCount.tag.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${widget.tagWithCount.count}',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
