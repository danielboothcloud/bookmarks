import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    required this.navigationShell,
    required this.collapsed,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final bool collapsed;

  static const _items = <_SidebarItem>[
    _SidebarItem(icon: Icons.bookmarks_outlined, label: 'All Bookmarks'),
    _SidebarItem(icon: Icons.folder_outlined, label: 'Folders'),
    _SidebarItem(icon: Icons.label_outlined, label: 'Tags'),
    _SidebarItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
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
              ..._items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = index == selected;
                return _SidebarTile(
                  item: item,
                  isSelected: isSelected,
                  collapsed: collapsed,
                  onTap: () => navigationShell.goBranch(
                    index,
                    initialLocation: index == selected,
                  ),
                );
              }),
              const Spacer(),
              if (!collapsed)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Drive: not connected',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSidebar,
                    ),
                  ),
                ),
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
  const _SidebarItem({required this.icon, required this.label});
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
