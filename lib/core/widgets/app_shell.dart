import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/application/bookmark_providers.dart';
import '../../features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
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

class DeleteSelectedBookmarkIntent extends Intent {
  const DeleteSelectedBookmarkIntent();
}

/// App-level dismiss intent that is NOT Flutter's [DismissIntent]. Scaffold
/// registers its own `_DismissDrawerAction` for [DismissIntent] which
/// intercepts the key (even when disabled) and prevents our cascade from
/// running. Using a distinct intent class side-steps the interception while
/// keeping per-feature `DismissIntent` handlers (e.g. inline-add form Esc)
/// working unchanged via child-first shortcut resolution.
class AppDismissIntent extends Intent {
  const AppDismissIntent();
}

/// AppShell-level handler for Backspace/Delete keys. Two `isEnabled` guards:
///   - **No bookmark selected** -> nothing to delete; let the key propagate.
///   - **Focus is inside an EditableText** -> the user is editing text in a
///     TextField (e.g. inline-add URL field, detail-pane title); Backspace
///     and Delete must reach EditableText for character deletion. Returning
///     `false` makes Shortcuts emit `KeyEventResult.ignored` so the platform
///     text-input pipeline processes the key.
class _DeleteSelectedBookmarkAction
    extends Action<DeleteSelectedBookmarkIntent> {
  _DeleteSelectedBookmarkAction(this._ref);

  final WidgetRef _ref;

  bool _focusInEditableText() {
    final focused = FocusManager.instance.primaryFocus;
    final ctx = focused?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool isEnabled(DeleteSelectedBookmarkIntent intent) {
    if (_focusInEditableText()) return false;
    return _ref.read(selectedBookmarkIdProvider) != null;
  }

  @override
  Object? invoke(DeleteSelectedBookmarkIntent intent) {
    final id = _ref.read(selectedBookmarkIdProvider);
    if (id == null) return null;
    _ref.read(pendingDeleteIdProvider.notifier).prompt(id);
    return null;
  }
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
        // Delete / Backspace prompt deletion of the currently-selected
        // bookmark. EditableText (TextField/Notes) consumes these keys
        // first when focus is on a text field, so editing a character
        // never accidentally triggers a delete prompt.
        SingleActivator(LogicalKeyboardKey.delete):
            DeleteSelectedBookmarkIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):
            DeleteSelectedBookmarkIntent(),
        SingleActivator(LogicalKeyboardKey.escape): AppDismissIntent(),
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
          DeleteSelectedBookmarkIntent: _DeleteSelectedBookmarkAction(ref),
          AppDismissIntent: CallbackAction<AppDismissIntent>(
            onInvoke: (_) {
              // Cascade in priority order: each Esc handles ONE level so
              // the user can incrementally back out of any nested state.
              // Per-feature DismissIntent handlers (e.g. inline-add form)
              // win when focus is in their subtree because their Shortcuts
              // bind Esc to DismissIntent at a closer scope -- this cascade
              // only runs when no child handler matched.
              if (ref.read(pendingDeleteIdProvider) != null) {
                ref.read(pendingDeleteIdProvider.notifier).clear();
                return null;
              }
              if (ref.read(addFormVisibleProvider)) {
                ref.read(addFormVisibleProvider.notifier).hide();
                return null;
              }
              if (ref.read(selectedBookmarkIdProvider) != null) {
                // Clear selection only -- do NOT call primaryFocus.unfocus().
                // Unfocusing here moved focus to a dead scope and broke
                // subsequent app-level shortcuts (Cmd+N) until the user
                // re-selected a bookmark. Edits in the detail pane already
                // save on focus loss when the pane unmounts; no further
                // bookkeeping needed.
                ref.read(selectedBookmarkIdProvider.notifier).clear();
                return null;
              }
              // Final branch: nothing to dismiss. Don't unfocus -- same
              // reason as branch 3.
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
                        child: BookmarkDetailPane(),
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
