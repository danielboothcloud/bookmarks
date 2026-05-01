// TODO(story-2.1): convert to @riverpod once riverpod_generator is unblocked.
// (Same analyzer-version conflict that pins the bookmarks providers --
// see bookmark_providers.dart header.)

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
