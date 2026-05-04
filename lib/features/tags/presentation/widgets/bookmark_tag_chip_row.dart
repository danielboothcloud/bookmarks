import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/tag_providers.dart';
import '../../domain/tag.dart';

/// Read-only horizontal row of tag chips for a bookmark, used by the list-item
/// and card variants. Single-line; chips that do not fit are hidden and
/// represented by a compact "+N" badge (AC4). Not interactive — removal lives
/// in the detail pane (`_TagsRow`).
///
/// Renders nothing (zero height) when the bookmark has no tags.
class BookmarkTagChipRow extends ConsumerWidget {
  const BookmarkTagChipRow({
    required this.bookmarkId,
    super.key,
  });

  final String bookmarkId;

  // Heuristic chip width: 6px horizontal padding on each side + ~7px per
  // character at 11sp. Errs slightly wide so we under-count rather than
  // over-count visible chips (better to show "+1" than to clip mid-glyph).
  static double _chipWidth(String label) => 12.0 + label.length * 7.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(watchTagsForBookmarkProvider(bookmarkId));
    final tags = tagsAsync.value ?? const <Tag>[];
    if (tags.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacerW = 4.0;
        final maxW = constraints.maxWidth;

        // Determine which chips fit. Always shows at least the first chip
        // (safety net for a single very-long tag name; per-chip
        // TextOverflow.ellipsis handles any excess within the bounded box).
        final visible = <Tag>[];
        var used = 0.0;

        for (int i = 0; i < tags.length; i++) {
          final w = _chipWidth(tags[i].name);
          final spacer = visible.isEmpty ? 0.0 : spacerW;
          final remaining = tags.length - visible.length - 1;
          // Reserve space for the "+N" badge if more tags will follow.
          final reserve =
              remaining > 0 ? spacerW + _chipWidth('+$remaining') : 0.0;

          if (visible.isEmpty || used + spacer + w + reserve <= maxW) {
            visible.add(tags[i]);
            used += spacer + w;
          } else {
            break;
          }
        }

        final overflow = tags.length - visible.length;

        return SizedBox(
          height: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(width: spacerW),
                // Constrain each chip to its estimated width so
                // TextOverflow.ellipsis fires when the heuristic
                // underestimates (e.g. wide glyphs, font scaling).
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _chipWidth(visible[i].name).clamp(0.0, maxW),
                  ),
                  child: _Chip(label: visible[i].name),
                ),
              ],
              if (overflow > 0) ...[
                if (visible.isNotEmpty) const SizedBox(width: spacerW),
                _Chip(label: '+$overflow'),
              ],
            ],
          ),
        );
      },
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
