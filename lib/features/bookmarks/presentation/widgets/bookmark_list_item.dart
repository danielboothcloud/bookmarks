import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../../tags/presentation/widgets/bookmark_tag_chip_row.dart';
import '../../application/bookmark_providers.dart';
import '../../domain/bookmark.dart';

// TODO(story-1.4-narrow-detail): when the detail pane is hidden (< 900px), the
// UX spec calls for an inline-expansion of the selected item at the bottom of
// the row instead of a separate panel. Deferred until users report it missing.
// At narrow widths the delete trigger (currently in the detail pane) will need
// a separate path -- see bookmark_detail_pane.dart for the trash button + inline
// confirmation. Story 1.5's keyboard Delete shortcut lives at app_shell.dart
// (works regardless of focus, as long as a bookmark is selected).

class BookmarkListItem extends ConsumerWidget {
  const BookmarkListItem({
    required this.bookmark,
    super.key,
  });

  final Bookmark bookmark;

  String _domain(String url) {
    final host = Uri.tryParse(url)?.host;
    return (host != null && host.isNotEmpty) ? host : url;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final selectedId = ref.watch(selectedBookmarkIdProvider);
    final isSelected = selectedId == bookmark.id;

    return MergeSemantics(
      child: Semantics(
        label: '${bookmark.title}, ${_domain(bookmark.url)}',
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onDoubleTap: () => openExternal(bookmark.url),
          child: Material(
            color: isSelected ? AppColors.surfaceHover : Colors.transparent,
            child: InkWell(
              onTap: () => ref
                  .read(selectedBookmarkIdProvider.notifier)
                  .select(bookmark.id),
              hoverColor: AppColors.surfaceHover,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FaviconWidget(
                        bookmarkId: bookmark.id,
                        faviconBase64: bookmark.faviconBase64,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              bookmark.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                color: AppColors.textBody,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bookmark.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            BookmarkTagChipRow(bookmarkId: bookmark.id),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
