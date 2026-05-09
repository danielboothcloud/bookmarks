import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../../tags/presentation/widgets/bookmark_tag_chip_row.dart';
import '../../application/bookmark_providers.dart';
import '../../domain/bookmark.dart';

// Narrow-width (<900px) delete affordance: explicitly accepted gap.
// The keyboard Delete shortcut works at any width (app_shell.dart). The detail
// pane (with its trash button + inline confirmation, bookmark_detail_pane.dart)
// is the wide-width mouse path. At narrow widths mouse users have no visible
// affordance -- accepted because keyboard works and narrow-width usage is rare.
// Revisit if a real user reports the gap.

class BookmarkListItem extends ConsumerStatefulWidget {
  const BookmarkListItem({
    required this.bookmark,
    super.key,
  });

  final Bookmark bookmark;

  @override
  ConsumerState<BookmarkListItem> createState() => _BookmarkListItemState();
}

class _BookmarkListItemState extends ConsumerState<BookmarkListItem> {
  // skipTraversal: keyboard list nav (deferred Story; today the user opens
  // bookmarks via mouse + arrow-on-detail-pane). The node exists solely so a
  // mouse click claims focus inside AppShell's Shortcuts subtree -- without
  // it primary focus drifts outside, and Cmd+N / Esc bonk.
  final _focusNode = FocusNode(
    debugLabel: 'bookmark-list-item',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String _domain(String url) {
    final host = Uri.tryParse(url)?.host;
    return (host != null && host.isNotEmpty) ? host : url;
  }

  @override
  Widget build(BuildContext context) {
    final bookmark = widget.bookmark;
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
            color: isSelected ? AppColors.surfaceSelected : Colors.transparent,
            child: InkWell(
              focusNode: _focusNode,
              onTap: () {
                _focusNode.requestFocus();
                ref
                    .read(selectedBookmarkIdProvider.notifier)
                    .select(bookmark.id);
              },
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
