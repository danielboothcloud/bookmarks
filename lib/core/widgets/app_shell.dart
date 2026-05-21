/// The three-pane application shell.
///
/// Hosts the global `Shortcuts` + `Actions` wiring that every keyboard
/// surface in the app depends on -- Cmd+N (add), Cmd+F (focus search),
/// Esc (cascade dismiss), Delete/Backspace (delete selected item). If
/// primary focus ever leaves this subtree, those shortcuts stop firing
/// and the platform beeps.
///
/// The shell is wrapped in a translucent [Listener] -- the
/// `_AppShellFocusReclaimer` below -- whose only job is to put primary
/// focus back inside the shell after a pointer-down lands on an inert
/// surface (Container padding, the SearchBar surround, an empty content
/// area). Without it, clicking anywhere that has no `onTap` would
/// silently break every global shortcut until the user re-clicked a
/// focus-claiming widget. The reclaimer was added in Story 3.1 after
/// macOS smoke surfaced the leak that 480 tests had missed; it is
/// load-bearing infrastructure, not optional polish. Do not strip the
/// Listener wrap during refactors -- see the doc on
/// `_AppShellFocusReclaimer` and `docs/focus-model.md` (Rule 5, gotcha
/// appendix entry on `Focus(autofocus: true)`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/application/bookmark_providers.dart';
import '../../features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
import '../../features/folders/application/folder_providers.dart';
import '../../features/search/application/search_providers.dart';
import '../../features/search/presentation/widgets/search_bar.dart';
import '../../features/search/presentation/widgets/search_results_screen.dart';
import '../drive/drive_auth_providers.dart';
import '../drive/drive_auth_state.dart';
import '../drive/drive_sync_providers.dart';
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

/// Holds the FocusNode that backs AppShell's `Focus(autofocus: true)` shell
/// scope. Lives on a Provider so the `_AppShellFocusReclaimer` can compare
/// `FocusManager.instance.primaryFocus` against this node by identity (see
/// `docs/focus-model.md` Hard Rule 5 + the framework-gotcha appendix entry
/// on pointer-down focus reclaim).
final appShellFocusNodeProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(
    debugLabel: 'app-shell-shortcut-scope',
    skipTraversal: true,
  );
  ref.onDispose(node.dispose);
  return node;
});

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Story 4.2: activate the sync auto-push orchestrator and the app
    // lifecycle observer. Both pieces are side-effect-only -- the
    // orchestrator's Provider<void> sets up internal listeners on first
    // read; the lifecycle observer hooks `AppLifecycleState.resumed` so
    // a foregrounded app drains any pending queue. Read here (rather
    // than in app.dart) so both pieces live and die with the
    // sign-in-required surface -- when the user is on /welcome (auth
    // disconnected), AppShell isn't mounted and neither is needed.
    ref.watch(autoPushOrchestratorProvider);

    return _SyncLifecycleObserver(
      child: Shortcuts(
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
              // Story 3.1: Cmd+F / Ctrl+F focuses the search bar's TextField.
              // The SearchBar's State listens for focus-gain on this node
              // and positions the cursor at end-of-text in the next frame
              // (per AC1). Keeping the action body to a single requestFocus
              // call avoids reaching into another widget's controller.
              ref.read(searchBarFocusNodeProvider).requestFocus();
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
              // Story 3.2: active search clears before selection. A query
              // is the user's current intent; a residual selection is
              // incidental. The reverse-binding in BookmarkSearchBar
              // resyncs the visible TextField; the _ContentArea swap
              // reverts to navigationShell automatically.
              //
              // AC3 requires focus to STAY on the search field after Esc so
              // the next keystroke types a new query. Some part of Flutter's
              // default key pipeline (WidgetsApp DismissAction / EditableText
              // internals) unfocuses on Esc even after our cascade consumes
              // the event; re-requesting focus post-frame restores the
              // user-facing contract regardless of root cause.
              if (ref.read(searchActiveProvider)) {
                ref.read(searchQueryProvider.notifier).clear();
                final searchNode = ref.read(searchBarFocusNodeProvider);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (searchNode.canRequestFocus) searchNode.requestFocus();
                });
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
        // (Delete/Backspace, Cmd+N, Cmd+F, Esc, etc.) work even when no row,
        // button, or text field has explicitly claimed focus. Material
        // `InkWell` doesn't request focus on pointer taps -- only on Tab
        // navigation -- so clicking a folder or bookmark in the sidebar
        // leaves `FocusManager.instance.primaryFocus` outside this widget's
        // ancestry. Without this Focus node, key events would propagate to
        // the platform (macOS error beep) instead of the Shortcuts handler.
        // `autofocus: true` is one-shot at mount; the `_AppShellFocusReclaimer`
        // below reclaims this node on any pointer-down whose target chain
        // didn't end up claiming focus inside the shell subtree.
        child: Focus(
          focusNode: ref.watch(appShellFocusNodeProvider),
          autofocus: true,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Scaffold(
            backgroundColor: AppColors.surfaceContent,
            body: _AppShellFocusReclaimer(
              child: LayoutBuilder(
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
                    Expanded(
                      child: Container(
                        color: AppColors.surfaceContent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FocusTraversalOrder(
                              order: NumericFocusOrder(2),
                              child: BookmarkSearchBar(),
                            ),
                            Expanded(
                              child: FocusTraversalOrder(
                                order: const NumericFocusOrder(3),
                                child: _ContentArea(
                                  navigationShell: navigationShell,
                                ),
                              ),
                            ),
                          ],
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
      ),
      ),
    );
  }
}

/// Story 4.2: app-lifecycle observer that triggers a sync push when the
/// app is foregrounded. A `WidgetsBindingObserver` is the canonical
/// Flutter idiom; wrapping it in this small widget keeps `AppShell`
/// stateless and lets us keep the observer scoped to the connected
/// surface (the /welcome route mounts no AppShell, so no observer is
/// registered there). Connectivity-restored will become the fourth
/// trigger in Story 4.5 -- this observer is intentionally narrow.
class _SyncLifecycleObserver extends ConsumerStatefulWidget {
  const _SyncLifecycleObserver({required this.child});

  final Widget child;

  @override
  ConsumerState<_SyncLifecycleObserver> createState() =>
      _SyncLifecycleObserverState();
}

class _SyncLifecycleObserverState extends ConsumerState<_SyncLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final authState = ref.read(driveAuthStateProvider).value;
    if (authState is! DriveAuthConnected) return;
    // Story 4.3: resume now triggers a full sync cycle (pull-then-push)
    // rather than push only, so foregrounding the app surfaces remote
    // changes from other devices without an explicit user action.
    ref.read(driveSyncServiceProvider).sync(fileId: authState.fileId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Pointer-down focus reclaimer for AppShell's shortcut subtree.
///
/// **Problem.** Per `docs/focus-model.md` Hard Rule 5, mouse clicks must
/// claim focus on widgets that participate in shortcuts. The convention
/// is per-widget (each focus-claiming widget calls `requestFocus()` in
/// its `onTap`), but it leaks: clicks on widgets that have no focus
/// handler -- Container backgrounds, padding, the SearchBar's bordered
/// surround, an empty content area -- leave primary focus wherever it
/// last was, which after a transient surface dispose may be outside the
/// AppShell's `Shortcuts` subtree. Result: subsequent Cmd+N / Cmd+F /
/// Backspace / Esc keystrokes don't reach the Shortcuts handler and the
/// platform beeps.
///
/// **Fix.** A translucent [Listener] observes pointer-down events on the
/// AppShell body without competing in the gesture arena (children's
/// own gesture recognisers and InkWell taps win normally). After the
/// frame in which the click was processed, if primary focus is NOT
/// inside the AppShell shell-scope FocusNode (`appShellFocusNodeProvider`)
/// or one of its descendants, focus is reclaimed onto the shell node.
/// This means: focus-claiming widgets keep working unchanged; clicks
/// on inert surfaces fall through to the reclaimer; key shortcuts keep
/// working in either case.
///
/// The post-frame deferral is critical -- it lets a child's `onTap`
/// (e.g. an InkWell or a TextField requesting focus) win when the click
/// did land on a focus-claiming widget. We only reclaim if no widget
/// claimed focus during the frame.
class _AppShellFocusReclaimer extends ConsumerWidget {
  const _AppShellFocusReclaimer({required this.child});

  final Widget child;

  bool _isInsideShell(FocusNode? node, FocusNode shell) {
    if (node == null) return false;
    if (identical(node, shell)) return true;
    return node.ancestors.contains(shell);
  }

  void _onPointerDown(WidgetRef ref) {
    final shell = ref.read(appShellFocusNodeProvider);
    // Fast-path: focus is already inside the shell -- nothing to do.
    if (_isInsideShell(FocusManager.instance.primaryFocus, shell)) {
      return;
    }
    // Defer the reclaim until the gesture has fully resolved, so any
    // child widget that claims focus on this tap (InkWell.onTap,
    // TextField gesture recogniser, sidebar row click-to-claim) wins.
    // The post-frame callback runs at the end of the next frame; we
    // explicitly schedule a frame because pointer events don't auto-
    // schedule one when the handler doesn't trigger a rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isInsideShell(FocusManager.instance.primaryFocus, shell)) {
        return;
      }
      shell.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onPointerDown(ref),
      child: child,
    );
  }
}

/// Story 3.1: swaps between the navigation shell and the search-results
/// screen based on `searchActiveProvider`. Pulled out into its own
/// ConsumerWidget so the rebuild on every search keystroke is scoped to
/// the content area only -- AppShell's outer layout doesn't churn.
class _ContentArea extends ConsumerWidget {
  const _ContentArea({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchActive = ref.watch(searchActiveProvider);
    if (searchActive) {
      return const SearchResultsScreen();
    }
    return navigationShell;
  }
}
