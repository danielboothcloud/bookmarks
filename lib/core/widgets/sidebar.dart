import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/folders/application/folder_notifier.dart';
import '../../features/folders/application/folder_providers.dart';
import '../../features/folders/presentation/widgets/folder_tree.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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
                          onWillAcceptWithDetails: (_) => true,
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
                                onAdd: () async {
                                  // Selection-aware create. Null selection
                                  // -> root-level (Story 2.1 behaviour
                                  // preserved). Non-null -> child of the
                                  // selected folder; the notifier auto-
                                  // expands the parent so the new child is
                                  // visible (Story 2.2 Task 3).
                                  final selectedId =
                                      ref.read(selectedFolderIdProvider);
                                  final newId = await ref
                                      .read(folderNotifierProvider.notifier)
                                      .addFolder(parentId: selectedId);
                                  if (newId != null) {
                                    ref
                                        .read(pendingFolderEditIdProvider
                                            .notifier)
                                        .start(newId);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                        const FolderTree(),
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
              _SyncStatusIndicator(
                // TODO(story-4.1): wire to real DriveSyncStatus provider.
                status: SyncStatus.unavailable,
                collapsed: collapsed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SyncStatus { synced, unsynced, unavailable }

class _SyncStatusIndicator extends StatelessWidget {
  const _SyncStatusIndicator({required this.status, required this.collapsed});

  final SyncStatus status;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SyncStatus.synced => (AppColors.syncSynced, 'Drive: synced'),
      SyncStatus.unsynced => (AppColors.syncUnsynced, 'Drive: pending'),
      SyncStatus.unavailable => (AppColors.syncUnavailable, 'Drive: not connected'),
    };
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: dot),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          dot,
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSidebar,
              ),
            ),
          ),
        ],
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

class _SidebarTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.accent : AppColors.textSidebar;
    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(item.icon, color: color, size: 20),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.w400,
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
