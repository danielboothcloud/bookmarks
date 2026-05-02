import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../../tags/presentation/widgets/bookmark_tag_chip_row.dart';
import '../../application/bookmark_providers.dart';
import '../../domain/bookmark.dart';

/// Card variant of the bookmark row, used by the folder grid view (Story
/// 2.2). Mirrors [BookmarkListItem]'s tap semantics: single-tap selects (and
/// populates the detail pane via [selectedBookmarkIdProvider]); double-tap
/// opens the URL in the system browser. A separate widget (rather than a
/// "grid mode" toggle on BookmarkListItem) per architecture line 519 -- the
/// vertical-stack vs horizontal-row geometry difference is large enough that
/// a single-widget mode would balloon into conditional layout.
class BookmarkCard extends ConsumerWidget {
  const BookmarkCard({required this.bookmark, super.key});
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
            color: AppColors.surfaceContent,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: isSelected ? AppColors.accent : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => ref
                  .read(selectedBookmarkIdProvider.notifier)
                  .select(bookmark.id),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaviconWidget(
                      bookmarkId: bookmark.id,
                      faviconBase64: bookmark.faviconBase64,
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      bookmark.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.textBody,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _domain(bookmark.url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    BookmarkTagChipRow(bookmarkId: bookmark.id),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
