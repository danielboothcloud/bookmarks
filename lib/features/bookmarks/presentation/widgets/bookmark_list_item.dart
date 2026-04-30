import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../domain/bookmark.dart';

class BookmarkListItem extends StatelessWidget {
  const BookmarkListItem({
    required this.bookmark,
    this.onTap,
    super.key,
  });

  final Bookmark bookmark;
  final VoidCallback? onTap;

  String _domain(String url) {
    final host = Uri.tryParse(url)?.host;
    return (host != null && host.isNotEmpty) ? host : url;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        label: '${bookmark.title}, ${_domain(bookmark.url)}',
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
