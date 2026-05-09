import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Centered, muted placeholder shown when no sidebar entry is selected (or the
/// selection refers to an entry that no longer exists). Used by both
/// [FoldersScreen] and [TagsScreen].
class SidebarSelectionPlaceholder extends StatelessWidget {
  const SidebarSelectionPlaceholder({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

/// Centered, muted placeholder shown when a content stream errored. Used by
/// both [FoldersScreen] and [TagsScreen]; mirrors the calm-failure UX in the
/// rest of the app (no toast, no modal, no alarm).
class ContentLoadErrorPlaceholder extends StatelessWidget {
  const ContentLoadErrorPlaceholder({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
