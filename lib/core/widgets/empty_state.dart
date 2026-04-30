import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class EmptyState extends StatelessWidget {
  const EmptyState._({
    required this.semanticsLabel,
    required this.child,
  });

  factory EmptyState.noBookmarks({required VoidCallback onAddBookmark}) {
    return EmptyState._(
      semanticsLabel:
          'No bookmarks yet. Press Cmd+N to save your first bookmark.',
      child: _NoBookmarksContent(onAddBookmark: onAddBookmark),
    );
  }

  factory EmptyState.noResults(String query) {
    return EmptyState._(
      semanticsLabel: "No bookmarks match '$query'",
      child: _NoResultsContent(query: query),
    );
  }

  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      child: child,
    );
  }
}

class _NoBookmarksContent extends StatelessWidget {
  const _NoBookmarksContent({required this.onAddBookmark});

  final VoidCallback onAddBookmark;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bookmark_border,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No bookmarks yet',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Press Cmd+N to save your first.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: onAddBookmark,
              child: const Text('Add bookmark'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResultsContent extends StatelessWidget {
  const _NoResultsContent({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        "No bookmarks match '$query'",
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
