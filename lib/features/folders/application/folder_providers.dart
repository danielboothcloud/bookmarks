import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../data/folder_repository.dart';
import '../domain/folder.dart';
import '../domain/i_folder_repository.dart';

final folderRepositoryProvider = Provider<IFolderRepository>((ref) {
  return FolderRepository(ref.watch(appDatabaseProvider));
});

final watchFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchAll();
});

/// The id of the folder currently in inline edit mode (newly-created or
/// rename). Only ONE folder can be edited at a time -- starting an edit on
/// another folder cancels the prior one. `null` means no edit is open.
/// Mirrors the rationale for [pendingDeleteIdProvider] in
/// bookmark_providers.dart -- a single-id Notifier, not a Set.
class PendingFolderEditIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void start(String id) => state = id;
  void clear() => state = null;
}

final pendingFolderEditIdProvider =
    NotifierProvider<PendingFolderEditIdNotifier, String?>(
        PendingFolderEditIdNotifier.new);

/// The id of the folder currently showing its inline delete confirmation.
/// Only ONE folder confirmation is open at a time -- pressing Delete on
/// a different folder migrates this state to the new id, collapsing the
/// prior confirmation. `null` means no confirmation is open. Mirrors the
/// single-id Notifier shape of [pendingFolderEditIdProvider] and the
/// bookmarks `pendingDeleteIdProvider`; conflating them would force every
/// consumer to disambiguate by intent.
class PendingFolderDeleteIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void prompt(String id) => state = id;
  void clear() => state = null;
}

final pendingFolderDeleteIdProvider =
    NotifierProvider<PendingFolderDeleteIdNotifier, String?>(
        PendingFolderDeleteIdNotifier.new);

/// The id of the folder whose contents are currently displayed in the
/// FoldersScreen content area. `null` when no folder is selected (the content
/// area shows the "Select a folder from the sidebar" placeholder). Kept
/// separate from [pendingFolderEditIdProvider]: edit-mode is per-row,
/// selection is app-wide; conflating them would force consumers to
/// disambiguate by intent.
class SelectedFolderIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
  void clear() => state = null;
}

final selectedFolderIdProvider =
    NotifierProvider<SelectedFolderIdNotifier, String?>(
        SelectedFolderIdNotifier.new);

/// The set of folder ids currently expanded in the sidebar tree. A folder not
/// in this set renders its children as collapsed (skipped). Default empty --
/// new sessions start with all folders collapsed; users open what they need.
/// In-memory only; persistence-of-UI-state is deferred (Story 2.1 set the
/// precedent).
class ExpandedFolderIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String id) {
    final next = {...state};
    if (!next.add(id)) next.remove(id);
    state = next;
  }

  void expand(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
  }

  void collapse(String id) {
    if (!state.contains(id)) return;
    state = state.where((x) => x != id).toSet();
  }

  /// Bulk replacement -- used by [FolderNotifier.deleteFolderCascade] to
  /// drop multiple deleted ids in a single notification. Prefer this over
  /// looping `.collapse(id)` which would emit N notifications. The
  /// `setEquals` short-circuit avoids re-broadcasting on identity-equal
  /// replacements (consumers reading the set via `ref.watch` would
  /// otherwise see a spurious rebuild).
  void replace(Set<String> next) {
    if (setEquals(state, next)) return;
    state = next;
  }
}

final expandedFolderIdsProvider =
    NotifierProvider<ExpandedFolderIdsNotifier, Set<String>>(
        ExpandedFolderIdsNotifier.new);

/// Children-of-folder index, derived from [watchFoldersProvider]. Maps
/// `parentId` (null for roots) to the list of child folders, preserving the
/// repository's `createdAt asc` ordering. Computed once per stream emission
/// so the tree renderer (Story 2.2 Task 4) doesn't rebuild a fresh map on
/// every FolderRow rebuild.
final folderChildrenIndexProvider =
    Provider<Map<String?, List<Folder>>>((ref) {
  final folders = ref.watch(watchFoldersProvider).value ?? const <Folder>[];
  final byParent = <String?, List<Folder>>{};
  for (final folder in folders) {
    byParent.putIfAbsent(folder.parentId, () => <Folder>[]).add(folder);
  }
  return byParent;
});

/// All descendant folder ids of [rootId] (inclusive of [rootId] itself). Used
/// by FoldersScreen to filter bookmarks to the selected folder AND its nested
/// subfolders (FR12 -- recursive include). Iterative (stack) to bound the
/// call depth on pathological trees from a future browser-import (Story 5.1)
/// and to terminate even on a corrupted cyclic chain via the visited set.
///
/// Top-level function rather than a `family` provider because it's a pure
/// derivation parametrised by root id and the byParent index; a family would
/// force per-id caching with no eviction for cheap microsecond work.
Set<String> collectFolderDescendants(
  String rootId,
  Map<String?, List<Folder>> byParent,
) {
  final result = <String>{rootId};
  final stack = <String>[rootId];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    for (final child in byParent[current] ?? const <Folder>[]) {
      if (result.add(child.id)) stack.add(child.id);
    }
  }
  return result;
}

/// Flat ordered list of folders currently VISIBLE in the sidebar tree.
/// Roots in [folderChildrenIndexProvider] order (the repo's `createdAt asc`),
/// each followed by its descendants ONLY when the parent is in
/// [expandedFolderIdsProvider]. This is the navigation order used by
/// keyboard arrow keys (Up/Down move selection along this list).
///
/// Recursive walk over the byParent index -- depth is bounded in practice
/// (typical folder trees are < 10 deep). The traversal does NOT use a
/// visited set: a corrupted cyclic byParent map would already have been
/// caught by [collectFolderDescendants] / [flattenFolderTree] which DO
/// use one; here we trust the index is well-formed because both producers
/// never emit cycles. If a cycle ever sneaks through (e.g. a future sync
/// merge bug), the resulting infinite recursion would surface immediately
/// in dev rather than silently hiding behind a visited-set sentinel.
final visibleFolderListProvider = Provider<List<Folder>>((ref) {
  final byParent = ref.watch(folderChildrenIndexProvider);
  final expanded = ref.watch(expandedFolderIdsProvider);
  final result = <Folder>[];
  void walk(List<Folder> folders) {
    for (final f in folders) {
      result.add(f);
      if (expanded.contains(f.id)) {
        walk(byParent[f.id] ?? const <Folder>[]);
      }
    }
  }
  walk(byParent[null] ?? const <Folder>[]);
  return result;
});

/// Pre-order traversal of the folder tree producing a depth-tagged flat list.
/// Used by `FolderPicker` (Story 2.3) to render the full tree as a linear
/// pickable list with depth-based indentation.
///
/// Roots come first (in the order [byParent] holds them, which is the repo's
/// `createdAt asc`), each immediately followed by its descendants (recursively,
/// also `createdAt asc`). Depth is 0 for roots, 1 for direct children, etc. --
/// matches `_FolderSubtree`'s rendering depth so the picker mirrors the
/// sidebar tree.
///
/// Iterative (stack) -- bounded even on a corrupted cyclic [byParent] map
/// because the visited set prevents re-enqueuing the same id. Same rationale
/// as [collectFolderDescendants].
List<({Folder folder, int depth})> flattenFolderTree(
  Map<String?, List<Folder>> byParent,
) {
  final result = <({Folder folder, int depth})>[];
  final visited = <String>{};
  final stack = <({Folder folder, int depth})>[];
  final roots = byParent[null] ?? const <Folder>[];
  // Push roots in REVERSE so the first root sits on top of the stack and
  // emerges first via removeLast().
  for (final root in roots.reversed) {
    stack.add((folder: root, depth: 0));
  }
  while (stack.isNotEmpty) {
    final frame = stack.removeLast();
    if (!visited.add(frame.folder.id)) continue;
    result.add(frame);
    final children = byParent[frame.folder.id] ?? const <Folder>[];
    for (final child in children.reversed) {
      stack.add((folder: child, depth: frame.depth + 1));
    }
  }
  return result;
}
