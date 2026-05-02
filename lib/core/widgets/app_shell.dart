import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/application/bookmark_providers.dart';
import '../../features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
import '../../features/folders/application/folder_providers.dart';
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

/// Triggered by Delete / Backspace at the app-shell level. The handler
/// dispatches by selection priority -- selected bookmark wins over selected
/// folder so the user's last item-level action determines what gets
/// prompted. (Story 1.5 + Story 2.4.)
class DeleteSelectedItemIntent extends Intent {
  const DeleteSelectedItemIntent();
}

/// Triggered by ArrowUp / ArrowDown at the app-shell level. Moves
/// [selectedFolderIdProvider] along [visibleFolderListProvider] -- the flat
/// list of currently-visible sidebar rows. (Story 2.4 keyboard nav.)
class MoveFolderSelectionIntent extends Intent {
  const MoveFolderSelectionIntent.up() : delta = -1;
  const MoveFolderSelectionIntent.down() : delta = 1;
  final int delta;
}

/// Triggered by ArrowRight at the app-shell level. On a folder with
/// children: expand if collapsed, otherwise move selection to first child.
/// On a leaf: no-op. Mirrors the Finder / VS Code tree-nav idiom.
class ExpandOrDescendFolderIntent extends Intent {
  const ExpandOrDescendFolderIntent();
}

/// Triggered by ArrowLeft at the app-shell level. On an expanded folder:
/// collapse. On a collapsed folder or leaf: move selection to the parent
/// (when one exists). At root with no expansion: no-op.
class CollapseOrAscendFolderIntent extends Intent {
  const CollapseOrAscendFolderIntent();
}

/// Triggered by Enter at the app-shell level. On a folder with children:
/// toggle expansion. On a leaf: no-op. Open-and-close is the most common
/// keyboard tree action; no separate "activate" semantic in this app.
class ToggleSelectedFolderIntent extends Intent {
  const ToggleSelectedFolderIntent();
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

/// AppShell-level handler for Backspace/Delete keys. Dispatches by selection
/// priority: a selected bookmark wins over a selected folder (a user who
/// just clicked a bookmark expects the bookmark prompt even if a folder is
/// also selected -- `selectedFolderIdProvider` tracks the sidebar's
/// content-view selection, which can be non-null while a bookmark inside it
/// is selected). Two `isEnabled` guards:
///   - **No selection at all** -> nothing to delete; let the key propagate.
///   - **Focus is inside an EditableText** -> the user is editing text in
///     a TextField (e.g. inline-add URL field, detail-pane title, folder
///     rename); Backspace and Delete must reach EditableText for character
///     deletion. Returning `false` makes Shortcuts emit
///     `KeyEventResult.ignored` so the platform text-input pipeline
///     processes the key.
class _DeleteSelectedItemAction extends Action<DeleteSelectedItemIntent> {
  _DeleteSelectedItemAction(this._ref);

  final WidgetRef _ref;

  bool _focusInEditableText() {
    final focused = FocusManager.instance.primaryFocus;
    final ctx = focused?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool isEnabled(DeleteSelectedItemIntent intent) {
    if (_focusInEditableText()) return false;
    if (_ref.read(selectedBookmarkIdProvider) != null) return true;
    if (_ref.read(selectedFolderIdProvider) != null) return true;
    return false;
  }

  @override
  Object? invoke(DeleteSelectedItemIntent intent) {
    final bookmarkId = _ref.read(selectedBookmarkIdProvider);
    if (bookmarkId != null) {
      _ref.read(pendingDeleteIdProvider.notifier).prompt(bookmarkId);
      return null;
    }
    final folderId = _ref.read(selectedFolderIdProvider);
    if (folderId != null) {
      _ref.read(pendingFolderDeleteIdProvider.notifier).prompt(folderId);
      return null;
    }
    return null;
  }
}

/// Shared base for sidebar keyboard-nav actions. Centralises the
/// EditableText carve-out and the "selection required" guard so each
/// arrow / enter handler stays single-purpose. Returns null silently
/// when the guards reject the intent so the key event simply propagates.
abstract class _FolderNavActionBase<T extends Intent> extends Action<T> {
  _FolderNavActionBase(this.ref);
  final WidgetRef ref;

  bool _focusInEditableText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool isEnabled(T intent) {
    if (_focusInEditableText()) return false;
    return ref.read(selectedFolderIdProvider) != null;
  }
}

class _MoveFolderSelectionAction
    extends _FolderNavActionBase<MoveFolderSelectionIntent> {
  _MoveFolderSelectionAction(super.ref);

  @override
  Object? invoke(MoveFolderSelectionIntent intent) {
    final selectedId = ref.read(selectedFolderIdProvider);
    if (selectedId == null) return null;
    final visible = ref.read(visibleFolderListProvider);
    final idx = visible.indexWhere((f) => f.id == selectedId);
    if (idx == -1) return null;
    final nextIdx = idx + intent.delta;
    // No wrap-around: at the edges, the key is consumed by the action
    // (returns null) but the selection stays put. Wrapping in a small list
    // would feel like a bug.
    if (nextIdx < 0 || nextIdx >= visible.length) return null;
    ref.read(selectedFolderIdProvider.notifier).select(visible[nextIdx].id);
    return null;
  }
}

class _ExpandOrDescendFolderAction
    extends _FolderNavActionBase<ExpandOrDescendFolderIntent> {
  _ExpandOrDescendFolderAction(super.ref);

  @override
  Object? invoke(ExpandOrDescendFolderIntent intent) {
    final selectedId = ref.read(selectedFolderIdProvider);
    if (selectedId == null) return null;
    final byParent = ref.read(folderChildrenIndexProvider);
    final children = byParent[selectedId] ?? const [];
    if (children.isEmpty) return null;
    final isExpanded = ref.read(expandedFolderIdsProvider).contains(selectedId);
    if (!isExpanded) {
      ref.read(expandedFolderIdsProvider.notifier).expand(selectedId);
      return null;
    }
    // Already expanded: descend to first child.
    ref.read(selectedFolderIdProvider.notifier).select(children.first.id);
    return null;
  }
}

class _CollapseOrAscendFolderAction
    extends _FolderNavActionBase<CollapseOrAscendFolderIntent> {
  _CollapseOrAscendFolderAction(super.ref);

  @override
  Object? invoke(CollapseOrAscendFolderIntent intent) {
    final selectedId = ref.read(selectedFolderIdProvider);
    if (selectedId == null) return null;
    final isExpanded = ref.read(expandedFolderIdsProvider).contains(selectedId);
    if (isExpanded) {
      ref.read(expandedFolderIdsProvider.notifier).collapse(selectedId);
      return null;
    }
    // Already collapsed (or leaf): ascend to parent if any. Look up the
    // selected folder's parentId via the byParent index by reverse-search;
    // simpler than carrying an inverse map for one call.
    final byParent = ref.read(folderChildrenIndexProvider);
    String? parentId;
    for (final entry in byParent.entries) {
      if (entry.value.any((f) => f.id == selectedId)) {
        parentId = entry.key;
        break;
      }
    }
    if (parentId == null) return null; // root-level collapsed -- no-op
    ref.read(selectedFolderIdProvider.notifier).select(parentId);
    return null;
  }
}

class _ToggleSelectedFolderAction
    extends _FolderNavActionBase<ToggleSelectedFolderIntent> {
  _ToggleSelectedFolderAction(super.ref);

  @override
  Object? invoke(ToggleSelectedFolderIntent intent) {
    final selectedId = ref.read(selectedFolderIdProvider);
    if (selectedId == null) return null;
    final byParent = ref.read(folderChildrenIndexProvider);
    final children = byParent[selectedId] ?? const [];
    if (children.isEmpty) return null; // leaf -- nothing to toggle
    ref.read(expandedFolderIdsProvider.notifier).toggle(selectedId);
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
        // item -- bookmark when one is selected, folder otherwise (Story 2.4
        // unified the dispatch via DeleteSelectedItemIntent). EditableText
        // (TextField/Notes) consumes these keys first when focus is on a
        // text field, so editing a character never accidentally triggers a
        // delete prompt.
        SingleActivator(LogicalKeyboardKey.delete):
            DeleteSelectedItemIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):
            DeleteSelectedItemIntent(),
        // Sidebar keyboard navigation (Story 2.4 follow-up). Each action's
        // isEnabled gates on selection + EditableText carve-out, so these
        // bindings are inert unless the user has actively chosen a folder
        // and is not editing text.
        SingleActivator(LogicalKeyboardKey.arrowUp):
            MoveFolderSelectionIntent.up(),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            MoveFolderSelectionIntent.down(),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            ExpandOrDescendFolderIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            CollapseOrAscendFolderIntent(),
        SingleActivator(LogicalKeyboardKey.enter):
            ToggleSelectedFolderIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter):
            ToggleSelectedFolderIntent(),
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
          DeleteSelectedItemIntent: _DeleteSelectedItemAction(ref),
          MoveFolderSelectionIntent: _MoveFolderSelectionAction(ref),
          ExpandOrDescendFolderIntent: _ExpandOrDescendFolderAction(ref),
          CollapseOrAscendFolderIntent: _CollapseOrAscendFolderAction(ref),
          ToggleSelectedFolderIntent: _ToggleSelectedFolderAction(ref),
          AppDismissIntent: CallbackAction<AppDismissIntent>(
            onInvoke: (_) {
              // Cascade in priority order: each Esc handles ONE level so
              // the user can incrementally back out of any nested state.
              // Per-feature DismissIntent handlers (e.g. inline-add form)
              // win when focus is in their subtree because their Shortcuts
              // bind Esc to DismissIntent at a closer scope -- this cascade
              // only runs when no child handler matched.
              //
              // Folder pending delete sits ABOVE bookmark pending delete:
              // both are topmost-ephemeral surfaces, but a folder
              // confirmation is the most-recently-opened in any flow that
              // has both, so dismissing it first matches the user's mental
              // stack.
              if (ref.read(pendingFolderDeleteIdProvider) != null) {
                ref.read(pendingFolderDeleteIdProvider.notifier).clear();
                return null;
              }
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
        // Fallback focus inside the Shortcuts subtree so app-level shortcuts
        // (Delete/Backspace, Cmd+N, Esc, etc.) work even when no row, button,
        // or text field has explicitly claimed focus. Material `InkWell`
        // doesn't request focus on pointer taps -- only on Tab navigation --
        // so clicking a folder or bookmark in the sidebar leaves
        // `FocusManager.instance.primaryFocus` outside this widget's
        // ancestry. Without this Focus node, key events would propagate to
        // the platform (macOS error beep) instead of the Shortcuts handler.
        // `autofocus: true` is one-shot at mount; subsequent foci (e.g. an
        // inline-add TextField) claim focus normally and return here on
        // disposal via the standard FocusScope walk.
        child: Focus(
          autofocus: true,
          debugLabel: 'app-shell-shortcut-scope',
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
      ),
    );
  }
}
