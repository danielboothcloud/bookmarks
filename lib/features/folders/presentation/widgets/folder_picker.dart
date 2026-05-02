import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/folder_providers.dart';

/// Overlay menu listing every folder (depth-indented) plus a "No folder" row
/// at the top. Anchored to a child via [MenuAnchor]; opens on demand and
/// closes on selection / Esc / outside-click. Used by both
/// `BookmarkFolderField` surfaces (detail pane + inline add form).
///
/// **Selection model.** This widget is presentational -- the parent owns the
/// current selection and the change callback. It deliberately does NOT couple
/// to `selectedFolderIdProvider` (the sidebar's content-view selection, a
/// different concern).
class FolderPicker extends ConsumerStatefulWidget {
  const FolderPicker({
    required this.currentFolderId,
    required this.onSelected,
    required this.child,
    this.anchorBorderRadius,
    super.key,
  });

  /// `null` means "No folder" is the current assignment.
  final String? currentFolderId;

  /// Fires with the new folder id (`null` for unfiled). The parent decides
  /// whether to write or no-op.
  final ValueChanged<String?> onSelected;

  /// The anchor child (typically the `BookmarkFolderField`). Wrapped by
  /// [MenuAnchor] so taps on it open the menu beneath the field.
  final Widget child;

  /// Optional radii for the anchor's tap-ripple. When [child] is rendered
  /// with rounded corners (e.g. `BookmarkFolderField`'s outlined container),
  /// pass matching radii so the InkWell splash stays inside the rounded
  /// shape instead of clipping square.
  final BorderRadius? anchorBorderRadius;

  @override
  ConsumerState<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<FolderPicker> {
  // Owned by the picker so onTap can explicitly claim focus -- tap events
  // don't auto-focus an InkWell, and CallbackShortcuts only fires for keys
  // routed to a focused descendant. Without this, Esc would fall through
  // and the menu would never close via keyboard for mouse-opened pickers.
  final _anchorFocus = FocusNode(debugLabel: 'folder-picker-anchor');

  @override
  void dispose() {
    _anchorFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byParent = ref.watch(folderChildrenIndexProvider);
    final flat = flattenFolderTree(byParent);
    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      builder: (context, controller, _) {
        // MenuAnchor's overlay handles Esc only when focus is inside the
        // menu items themselves -- which only happens on keyboard-driven
        // open. Mouse-opened menus would silently miss AC1's "Esc dismisses
        // the picker". Catching Esc on the anchor (which holds focus after
        // tap, see onTap below) closes that gap.
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (controller.isOpen) controller.close();
            },
          },
          child: InkWell(
            focusNode: _anchorFocus,
            borderRadius: widget.anchorBorderRadius,
            onTap: () {
              // Explicit focus request: InkWell.onTap does NOT auto-focus.
              _anchorFocus.requestFocus();
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: widget.child,
          ),
        );
      },
      menuChildren: [
        // "No folder" row -- the explicit unfiled state (AC4). Always at
        // index 0 so the user has a stable target.
        _PickerItem(
          depth: 0,
          label: 'No folder',
          isCurrent: widget.currentFolderId == null,
          isUnfiled: true,
          onTap: () => widget.onSelected(null),
        ),
        for (final entry in flat)
          _PickerItem(
            depth: entry.depth,
            label: entry.folder.name,
            isCurrent: widget.currentFolderId == entry.folder.id,
            isUnfiled: false,
            onTap: () => widget.onSelected(entry.folder.id),
          ),
      ],
    );
  }
}

class _PickerItem extends StatelessWidget {
  const _PickerItem({
    required this.depth,
    required this.label,
    required this.isCurrent,
    required this.isUnfiled,
    required this.onTap,
  });

  final int depth;
  final String label;
  final bool isCurrent;
  final bool isUnfiled;
  final VoidCallback onTap;

  // Match _treeIndentPerDepth in folder_tree.dart so the picker visually
  // mirrors the sidebar tree's indentation cadence.
  static const double _indentPerDepth = 16.0;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      onPressed: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: depth * _indentPerDepth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              child: isCurrent
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: AppColors.accent,
                    )
                  : null,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontStyle:
                    isUnfiled ? FontStyle.italic : FontStyle.normal,
                color: isUnfiled ? AppColors.textMuted : AppColors.textBody,
                fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
