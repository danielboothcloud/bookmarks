import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/application/bookmark_providers.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'sidebar.dart';

class AddBookmarkIntent extends Intent {
  const AddBookmarkIntent();
}

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            AddBookmarkIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            AddBookmarkIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AddBookmarkIntent: CallbackAction<AddBookmarkIntent>(
            onInvoke: (_) {
              if (GoRouterState.of(context).matchedLocation !=
                  AppRoutes.bookmarks) {
                context.go(AppRoutes.bookmarks);
              }
              ref.read(addFormVisibleProvider.notifier).show();
              return null;
            },
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              // TODO(story-3.1): focus search bar.
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
            backgroundColor: AppColors.surfaceContent,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final showDetailPane =
                    width >= AppSpacing.detailPaneBreakpoint;
                final collapseSidebar =
                    width < AppSpacing.sidebarCollapseBreakpoint;
                return Row(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: Sidebar(
                        navigationShell: navigationShell,
                        collapsed: collapseSidebar,
                      ),
                    ),
                    // Search bar will slot in here as order 2 in Story 3.1.
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: Container(
                          color: AppColors.surfaceContent,
                          child: navigationShell,
                        ),
                      ),
                    ),
                    if (showDetailPane)
                      const FocusTraversalOrder(
                        order: NumericFocusOrder(4),
                        child: _DetailPanePlaceholder(),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPanePlaceholder extends StatelessWidget {
  const _DetailPanePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.detailPaneWidth,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContent,
        border: Border(
          left: BorderSide(color: AppColors.border),
        ),
      ),
      child: const Center(
        child: Text(
          'Select a bookmark',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
