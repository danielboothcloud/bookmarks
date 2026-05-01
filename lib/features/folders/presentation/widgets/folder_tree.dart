import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/folder_notifier.dart';
import '../../application/folder_providers.dart';
import '../../domain/folder.dart';

/// Tree-indent unit, applied per depth level. Kept as a private constant
/// (NOT [AppSpacing.md] -- the values coincide today but tree indent and the
/// standard md spacing token may diverge in future visual tuning).
const double _treeIndentPerDepth = 16.0;

/// Folders branch index in the [StatefulShellRoute] -- mirrors the order in
/// `app_router.dart`. A miswire here would silently route to the wrong tab.
const int _foldersBranchIndex = 1;

class FolderTree extends ConsumerWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(watchFoldersProvider);
    final byParent = ref.watch(folderChildrenIndexProvider);
    return foldersAsync.when(
      data: (folders) {
        if (folders.isEmpty) {
          return const _FolderTreeEmpty();
        }
        final roots = byParent[null] ?? const <Folder>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final root in roots)
              _FolderSubtree(
                key: ValueKey('subtree-${root.id}'),
                folder: root,
                depth: 0,
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _FolderTreeEmpty extends StatelessWidget {
  const _FolderTreeEmpty();

  @override
  Widget build(BuildContext context) {
    // Wrap in _FolderRowFrame so the empty-state text aligns with where folder
    // names will appear once created -- avoids a ~16px horizontal shift when
    // the first folder is added.
    return const _FolderRowFrame(
      depth: 0,
      hasChildren: false,
      isExpanded: false,
      onChevronTap: null,
      child: Text(
        'No folders yet',
        style: TextStyle(fontSize: 12, color: AppColors.textSidebar),
      ),
    );
  }
}

/// Recursive subtree renderer. Each subtree watches its own dependency set
/// (children index + expansion set) so a mutation rebuilds only the affected
/// branch -- inlining into [FolderTree] would cascade rebuilds across all
/// sibling subtrees on every stream emission.
class _FolderSubtree extends ConsumerWidget {
  const _FolderSubtree({
    required this.folder,
    required this.depth,
    super.key,
  });
  final Folder folder;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byParent = ref.watch(folderChildrenIndexProvider);
    final expanded = ref.watch(expandedFolderIdsProvider);
    final children = byParent[folder.id] ?? const <Folder>[];
    final isExpanded = expanded.contains(folder.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FolderRow(
          key: ValueKey(folder.id),
          folder: folder,
          depth: depth,
          hasChildren: children.isNotEmpty,
          isExpanded: isExpanded,
        ),
        if (isExpanded)
          for (final child in children)
            _FolderSubtree(
              key: ValueKey('subtree-${child.id}'),
              folder: child,
              depth: depth + 1,
            ),
      ],
    );
  }
}

class FolderRow extends ConsumerStatefulWidget {
  const FolderRow({
    required this.folder,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    super.key,
  });
  final Folder folder;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;

  @override
  ConsumerState<FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends ConsumerState<FolderRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _wasEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.folder.name);
    _focusNode = FocusNode(debugLabel: 'folder-row-${widget.folder.id}');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingEditId = ref.watch(pendingFolderEditIdProvider);
    final isEditing = pendingEditId == widget.folder.id;

    // Edge: the displayed name may have been updated externally (e.g. a
    // remote sync in a future story); resync the controller text on entering
    // edit mode so the user sees the freshest value. Done in the postframe
    // callback so build() stays pure -- in-build controller mutations notify
    // listeners during build and surface as widget-test instability.
    if (isEditing && !_wasEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.text = widget.folder.name;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        _focusNode.requestFocus();
      });
    }
    _wasEditing = isEditing;

    // DragTarget wraps both modes so a row mid-rename can still accept drops
    // (otherwise a paused edit silently rejects all drags).
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final draggedId = details.data;
        if (draggedId == widget.folder.id) return false;
        // Cycle precheck for visual feedback only -- the notifier defensively
        // re-checks on drop because byParent here may be 1-frame stale.
        final byParent = ref.read(folderChildrenIndexProvider);
        final descendants = collectFolderDescendants(draggedId, byParent);
        return !descendants.contains(widget.folder.id);
      },
      onAcceptWithDetails: (details) {
        ref
            .read(folderNotifierProvider.notifier)
            .moveFolder(details.data, widget.folder.id);
      },
      builder: (context, candidateData, _) {
        final isHoverTarget = candidateData.isNotEmpty;
        if (isEditing) {
          return _buildEditRow(context, isHoverTarget);
        }
        return _buildDisplayRow(context, isHoverTarget);
      },
    );
  }

  Widget _buildDisplayRow(BuildContext context, bool isHoverTarget) {
    // Plain Draggable uses ImmediateMultiDragGestureRecognizer: drag activates
    // only after the pointer travels past kTouchSlop (~18px). A static click
    // never triggers it, so the tap reaches the wrapping InkWell.onTap.
    // (Story 2.2 originally specified LongPressDraggable(delay: zero) -- that
    // misuses the long-press recognizer: every pointerdown classifies as a
    // drag start, which breaks tap-to-select entirely. Plain Draggable is the
    // correct desktop "click-to-select, drag-to-move" idiom.)
    return Draggable<String>(
      data: widget.folder.id,
      feedback: _DragFeedback(name: widget.folder.name),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildDisplayRowBody(context, isHoverTarget),
      ),
      child: _buildDisplayRowBody(context, isHoverTarget),
    );
  }

  Widget _buildDisplayRowBody(BuildContext context, bool isHoverTarget) {
    final selectedFolderId = ref.watch(selectedFolderIdProvider);
    final isSelected = selectedFolderId == widget.folder.id;
    return GestureDetector(
      onDoubleTap: () => ref
          .read(pendingFolderEditIdProvider.notifier)
          .start(widget.folder.id),
      // TODO(post-2.2): right-click context menu for Rename/Delete/Move-to.
      child: InkWell(
        onTap: () {
          // Navigate to the Folders branch of the StatefulShellRoute. The
          // navrail will reflect the active branch automatically.
          final shell = StatefulNavigationShell.maybeOf(context);
          final alreadyOnFolders =
              shell?.currentIndex == _foldersBranchIndex;
          // Idempotent ONLY when already on /folders viewing this folder
          // (AC4 "no scroll reset, no re-fetch flicker"). If the user is on
          // another branch -- All Bookmarks/Tags/Settings, which don't clear
          // selection per Task 6 -- a re-tap must still navigate back.
          if (isSelected && alreadyOnFolders) return;
          if (!isSelected) {
            ref
                .read(selectedFolderIdProvider.notifier)
                .select(widget.folder.id);
          }
          if (shell != null) {
            shell.goBranch(
              _foldersBranchIndex,
              initialLocation: alreadyOnFolders,
            );
          } else {
            // maybeOf rather than of: in tests (and theoretically outside a
            // shell route) the GoRouter inherited widget may be absent.
            // Selection is the load-bearing AC; navigation is best-effort.
            GoRouter.maybeOf(context)?.go(AppRoutes.folders);
          }
        },
        child: Container(
          color: _rowBackground(isSelected, isHoverTarget),
          child: _FolderRowFrame(
            depth: widget.depth,
            hasChildren: widget.hasChildren,
            isExpanded: widget.isExpanded,
            onChevronTap: () => ref
                .read(expandedFolderIdsProvider.notifier)
                .toggle(widget.folder.id),
            child: Text(
              widget.folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isSelected
                    ? AppColors.accent
                    : AppColors.textSidebar,
                fontWeight:
                    isSelected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color? _rowBackground(bool isSelected, bool isHoverTarget) {
    if (isHoverTarget) {
      return AppColors.accent.withValues(alpha: 0.15);
    }
    if (isSelected) {
      return AppColors.accent.withValues(alpha: 0.08);
    }
    return null;
  }

  Widget _buildEditRow(BuildContext context, bool isHoverTarget) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              // Cancel edit -- do NOT save the buffer. Restore the controller
              // text to the on-disk name so the next edit starts clean.
              _controller.text = widget.folder.name;
              ref.read(pendingFolderEditIdProvider.notifier).clear();
              return null;
            },
          ),
        },
        child: Container(
          color: isHoverTarget
              ? AppColors.accent.withValues(alpha: 0.15)
              : null,
          child: _FolderRowFrame(
            depth: widget.depth,
            hasChildren: widget.hasChildren,
            isExpanded: widget.isExpanded,
            onChevronTap: widget.hasChildren
                ? () => ref
                    .read(expandedFolderIdsProvider.notifier)
                    .toggle(widget.folder.id)
                : null,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSidebar,
              ),
              cursorColor: AppColors.accent,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: _commit,
              onTapOutside: (_) => _commit(_controller.text),
            ),
          ),
        ),
      ),
    );
  }

  void _commit(String value) {
    // Snapshot pending state synchronously so a tap-outside arriving after Esc
    // (via DismissIntent) doesn't double-fire the save.
    if (ref.read(pendingFolderEditIdProvider) != widget.folder.id) return;
    ref.read(pendingFolderEditIdProvider.notifier).clear();
    // Empty/identical name short-circuits inside renameFolder -- safe to call
    // unconditionally.
    ref
        .read(folderNotifierProvider.notifier)
        .renameFolder(widget.folder.id, value);
  }
}

/// Shared layout shell so the row height and chevron-slot reservation stay
/// identical between display and edit states (no layout shift). Indents the
/// row by [depth] * [_treeIndentPerDepth] inside the existing horizontal
/// padding so the chevron-slot offset reasoning from Story 2.1 still holds
/// at every depth.
class _FolderRowFrame extends StatelessWidget {
  const _FolderRowFrame({
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.onChevronTap,
    required this.child,
  });
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onChevronTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: EdgeInsets.only(
        left: AppSpacing.md + (depth * _treeIndentPerDepth),
        right: AppSpacing.md,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // 12px chevron slot. Tappable when hasChildren so chevron toggles
          // expansion without selecting the folder. GestureDetector(opaque)
          // consumes the tap before it reaches the parent InkWell.onTap --
          // a nested InkWell would split the splash but still let the parent
          // gesture fire under Material's overlapping-ink resolution.
          SizedBox(
            width: 12,
            height: 12,
            child: hasChildren
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onChevronTap,
                    child: AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 120),
                      child: const Icon(
                        Icons.chevron_right,
                        size: 12,
                        color: AppColors.textSidebar,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// Calm chip-shaped drag preview. Not a clone of the row -- under the cursor
/// a depth-indented row with a chevron looks like a misplaced UI artifact.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSidebar,
          borderRadius: BorderRadius.circular(4),
          border:
              Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_outlined,
              size: 14,
              color: AppColors.textSidebar,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSidebar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
