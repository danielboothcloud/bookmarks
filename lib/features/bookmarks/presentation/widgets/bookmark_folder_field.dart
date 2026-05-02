import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../folders/application/folder_providers.dart';
import '../../../folders/domain/folder.dart';
import '../../../folders/presentation/widgets/folder_picker.dart';

/// Tappable folder-assignment field used by both [BookmarkDetailPane] and
/// [InlineAddForm]. Displays the current folder name (or "No folder" in muted
/// italic) with a trailing chevron, and opens [FolderPicker] anchored beneath
/// itself on tap. The parent owns the selection via [currentFolderId] +
/// [onChanged] -- this widget is purely presentational.
class BookmarkFolderField extends ConsumerWidget {
  const BookmarkFolderField({
    required this.currentFolderId,
    required this.onChanged,
    super.key,
  });

  final String? currentFolderId;
  final ValueChanged<String?> onChanged;

  String _resolveLabel(List<Folder> folders) {
    if (currentFolderId == null) return 'No folder';
    for (final f in folders) {
      if (f.id == currentFolderId) return f.name;
    }
    // Selection refers to a folder that no longer exists (cascade-deleted by
    // future Story 2.4 OR sync-driven removal). Fall back to the unfiled
    // label rather than crashing or showing a stale name.
    return 'No folder';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders =
        ref.watch(watchFoldersProvider).value ?? const <Folder>[];
    final label = _resolveLabel(folders);
    final isUnfiled = currentFolderId == null ||
        !folders.any((f) => f.id == currentFolderId);
    return FolderPicker(
      currentFolderId: currentFolderId,
      onSelected: onChanged,
      // Match the field's rounded outline so the tap ripple respects the
      // shape -- otherwise it splashes square inside a rounded container.
      anchorBorderRadius: BorderRadius.circular(4),
      child: Semantics(
        button: true,
        label: 'Folder: $label',
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle:
                        isUnfiled ? FontStyle.italic : FontStyle.normal,
                    color: isUnfiled
                        ? AppColors.textMuted
                        : AppColors.textBody,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
