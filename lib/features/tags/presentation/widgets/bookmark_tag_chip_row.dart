import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/tag_providers.dart';
import '../../domain/tag.dart';

/// Read-only horizontal row of tag chips for a bookmark, used by the list-item
/// and card variants. Single-line; chips overflowing the available width are
/// clipped by the parent. Not interactive -- removal lives in the detail pane
/// (Story 2.5 Task 6's `_TagsRow`).
///
/// Renders nothing (zero height) when the bookmark has no tags --
/// AC4: "the tag row is hidden entirely when the bookmark has no tags".
class BookmarkTagChipRow extends ConsumerWidget {
  const BookmarkTagChipRow({
    required this.bookmarkId,
    super.key,
  });

  final String bookmarkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(watchTagsForBookmarkProvider(bookmarkId));
    final tags = tagsAsync.value ?? const <Tag>[];
    if (tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          for (final tag in tags) ...[
            Flexible(child: _Chip(label: tag.name)),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.accentLink,
        ),
      ),
    );
  }
}
