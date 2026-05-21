import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/folders/application/folder_notifier.dart';
import '../../features/folders/application/folder_providers.dart';
import '../../features/folders/domain/folder.dart';
import '../../features/folders/presentation/widgets/folder_tree.dart';
import '../../features/tags/application/tag_providers.dart';
import '../../features/tags/presentation/widgets/tag_list.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'sync_status_indicator.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({
    required this.navigationShell,
    required this.collapsed,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final bool collapsed;

  // Branch order matches StatefulShellRoute branches in app_router.dart.
  static const _topItems = <_SidebarItem>[
    _SidebarItem(icon: Icons.bookmarks_outlined, label: 'All Bookmarks', branchIndex: 0),
    _SidebarItem(icon: Icons.folder_outlined, label: 'Folders', branchIndex: 1),
    _SidebarItem(icon: Icons.label_outlined, label: 'Tags', branchIndex: 2),
  ];
  static const _settingsItem = _SidebarItem(
    icon: Icons.settings_outlined,
    label: 'Settings',
    branchIndex: 3,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = navigationShell.currentIndex;
    final width = collapsed ? AppSpacing.sidebarIconWidth : AppSpacing.sidebarWidth;

    return Semantics(
      label: 'Sidebar navigation',
      explicitChildNodes: true,
      child: Container(
        width: width,
        color: AppColors.surfaceSidebar,
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              ..._topItems.map((item) => _SidebarTile(
                    item: item,
                    isSelected: item.branchIndex == selected,
                    collapsed: collapsed,
                    onTap: () {
                      // Folders is the only navrail entry that opens the
                      // folder content view. Clearing the selection on tap
                      // gives the user a fresh "Select a folder" placeholder
                      // (AC5) instead of restoring the last-viewed folder.
                      // Other branches don't render folder content -- their
                      // selection is dormant, so leave it intact.
                      if (item.branchIndex == 1) {
                        ref
                            .read(selectedFolderIdProvider.notifier)
                            .clear();
                      }
                      // Story 2.6 AC3: clicking 'All Bookmarks' is the
                      // exit-the-tag-filter gesture; clear the tag selection
                      // so a subsequent return to the tags branch shows the
                      // placeholder rather than a stale selection. The Tags
                      // tile (branch 2) deliberately does NOT clear --
                      // selection persistence on navrail-only navigation
                      // is desirable (return-via-navrail returns to the
                      // same filtered view).
                      if (item.branchIndex == 0) {
                        ref
                            .read(selectedTagIdProvider.notifier)
                            .clear();
                      }
                      navigationShell.goBranch(
                        item.branchIndex,
                        initialLocation: item.branchIndex == selected,
                      );
                    },
                  )),
              if (!collapsed) ...[
                const SizedBox(height: AppSpacing.md),
                // Flexible + SingleChildScrollView so a tall folder tree
                // (nested via Story 2.2) scrolls within the available
                // space rather than pushing Settings / SyncStatus off the
                // bottom edge. Section header scrolls with the tree -- a
                // sticky header would need an extra layout layer for
                // marginal benefit when the tree is short.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DragTarget<String>(
                          // Validate the dragged id is a known folder. Story
                          // 2.3+ will introduce bookmark Draggable<String> on
                          // the same generic; without this guard the header
                          // would visually accept bookmark drags and the
                          // notifier would Err on the unknown id.
                          onWillAcceptWithDetails: (details) {
                            final folders =
                                ref.read(watchFoldersProvider).value ??
                                    const <Folder>[];
                            return folders
                                .any((f) => f.id == details.data);
                          },
                          onAcceptWithDetails: (details) {
                            ref
                                .read(folderNotifierProvider.notifier)
                                .moveFolder(details.data, null);
                          },
                          builder: (context, candidateData, _) {
                            final isHoverTarget = candidateData.isNotEmpty;
                            return Container(
                              color: isHoverTarget
                                  ? AppColors.accent
                                      .withValues(alpha: 0.15)
                                  : null,
                              child: _SidebarSectionHeader(
                                label: 'FOLDERS',
                                onAdd: () {
                                  // Selection-aware create. Null selection
                                  // -> root-level. Non-null -> child of the
                                  // selected folder (notifier auto-expands
                                  // the parent so the new child is visible).
                                  final selectedId =
                                      ref.read(selectedFolderIdProvider);
                                  ref
                                      .read(folderNotifierProvider.notifier)
                                      .addFolderAndStartRename(
                                          parentId: selectedId);
                                },
                              ),
                            );
                          },
                        ),
                        const FolderTree(),
                        const SizedBox(height: AppSpacing.md),
                        const TagList(),
                      ],
                    ),
                  ),
                ),
              ],
              if (collapsed) const Spacer(),
              _SidebarTile(
                item: _settingsItem,
                isSelected: _settingsItem.branchIndex == selected,
                collapsed: collapsed,
                onTap: () => navigationShell.goBranch(
                  _settingsItem.branchIndex,
                  initialLocation: _settingsItem.branchIndex == selected,
                ),
              ),
              SyncStatusIndicator(collapsed: collapsed),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  final int branchIndex;
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.branchIndex,
  });
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.isSelected,
    required this.collapsed,
    required this.onTap,
  });

  final _SidebarItem item;
  final bool isSelected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  // skipTraversal: this tile is reachable via mouse-click only (the AppShell's
  // arrow-key sidebar navigation handles keyboard traversal of folder rows;
  // navrail tiles aren't part of that traversal). The focus node exists solely
  // to keep primary focus inside AppShell's Shortcuts subtree on mouse click,
  // so Cmd+N / Esc remain reachable.
  final _focusNode = FocusNode(
    debugLabel: 'sidebar-tile',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isSelected ? AppColors.accent : AppColors.textSidebar;
    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.item.label,
      child: InkWell(
        focusNode: _focusNode,
        onTap: () {
          _focusNode.requestFocus();
          widget.onTap();
        },
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 0 : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color:
                    widget.isSelected ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(widget.item.icon, color: color, size: 20),
              if (!widget.collapsed) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: widget.isSelected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({required this.label, required this.onAdd});

  final String label;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                color: AppColors.textSidebar,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            color: AppColors.textSidebar,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'New folder',
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}
