import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/result.dart';
import '../domain/folder.dart';
import 'folder_providers.dart';

class FolderNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();
  static const defaultName = 'New folder';

  /// Anti-corruption iteration cap for [_wouldCreateCycle]. Typical real-world
  /// folder depth is < 10; 256 is a paranoid ceiling that still terminates if
  /// a sync merge ever produces a corrupted parent loop.
  static const _cycleWalkLimit = 256;

  @override
  Future<void> build() async {}

  /// Creates a folder with the default name and returns its id. When
  /// [parentId] is non-null the new folder is nested under that parent and
  /// the parent is auto-expanded so the new child row is immediately visible
  /// (Story 2.2 AC1 / AC2 hierarchy-correctness). When [parentId] is null the
  /// folder is created at the root (Story 2.1's behaviour preserved). The
  /// caller (sidebar `+` button) immediately sets [pendingFolderEditIdProvider]
  /// to this id so the row enters inline edit mode on the next reactive
  /// emission.
  Future<String?> addFolder({String? parentId}) async {
    final now = DateTime.now();
    final folder = Folder(
      id: _uuid.v4(),
      name: defaultName,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
    state = const AsyncValue<void>.loading();
    final result = await ref.read(folderRepositoryProvider).save(folder);
    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
        if (parentId != null) {
          // Hierarchy-correctness: a hidden child is a UI bug. Limited to
          // mutations that change parent membership (NOT rename) so collapsed
          // folders don't pop open on every save.
          ref.read(expandedFolderIdsProvider.notifier).expand(parentId);
        }
        return folder.id;
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
        return null;
    }
  }

  /// Persists [newName] (trimmed) onto the folder with [id]. No-ops silently
  /// when the trimmed name is empty OR identical to the existing name -- keeps
  /// the inline-edit flow lean and avoids unnecessary writes (and unnecessary
  /// sync_queue churn once Story 4.2 wires triggers).
  Future<void> renameFolder(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      // Empty/whitespace is a calm cancel-equivalent. Clear any stale error
      // state from a prior call so consumers reading `state.hasError` don't
      // see a phantom failure.
      state = const AsyncValue<void>.data(null);
      return;
    }
    final getResult = await ref.read(folderRepositoryProvider).getById(id);
    switch (getResult) {
      case Err(:final error):
        // Folder vanished mid-edit (theoretical -- Story 2.4/4.3 surface).
        // Surface via the notifier's AsyncValue; this story has no banner for
        // folders, so the failure is silent at the UI level. Acceptable -- the
        // edit is moot if the row is gone.
        state = AsyncValue<void>.error(error, StackTrace.current);
        return;
      case Ok(:final value):
        if (value.name == trimmed) {
          // Identical-name no-op. Reset any stale error so consumers don't
          // see a phantom failure from a prior call.
          state = const AsyncValue<void>.data(null);
          return;
        }
        final updated = value.copyWith(
          name: trimmed,
          updatedAt: DateTime.now(),
        );
        state = const AsyncValue<void>.loading();
        final saveResult =
            await ref.read(folderRepositoryProvider).save(updated);
        switch (saveResult) {
          case Ok():
            state = const AsyncValue<void>.data(null);
          case Err(:final error):
            state = AsyncValue<void>.error(error, StackTrace.current);
        }
    }
  }

  /// Reparents [folderId] under [newParentId] (null = move to root). Silently
  /// rejects self-targets, descendant-targets (would form a cycle) and moves
  /// to the current parent (idempotent). The drag UX surfaces rejection via
  /// the row's snap-back animation -- no banner, no Err -- matching the
  /// renameFolder-empty-name calm-failure pattern.
  Future<void> moveFolder(String folderId, String? newParentId) async {
    // Self-target guard.
    if (folderId == newParentId) {
      state = const AsyncValue<void>.data(null);
      return;
    }
    if (newParentId != null) {
      final wouldLoop = await _wouldCreateCycle(folderId, newParentId);
      if (wouldLoop) {
        state = const AsyncValue<void>.data(null);
        return;
      }
    }
    final getResult =
        await ref.read(folderRepositoryProvider).getById(folderId);
    switch (getResult) {
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
        return;
      case Ok(:final value):
        if (value.parentId == newParentId) {
          // Already at this parent -- idempotent no-op. Reset stale error.
          state = const AsyncValue<void>.data(null);
          return;
        }
        final updated = value.copyWith(
          parentId: newParentId,
          updatedAt: DateTime.now(),
        );
        state = const AsyncValue<void>.loading();
        final saveResult =
            await ref.read(folderRepositoryProvider).save(updated);
        switch (saveResult) {
          case Ok():
            state = const AsyncValue<void>.data(null);
            if (newParentId != null) {
              ref
                  .read(expandedFolderIdsProvider.notifier)
                  .expand(newParentId);
            }
          case Err(:final error):
            state = AsyncValue<void>.error(error, StackTrace.current);
        }
    }
  }

  /// Deletes [rootId] AND every nested subfolder AND every bookmark whose
  /// folderId is in the descendant set. Atomic via the repo's transaction.
  /// Cleans up four pieces of UI state on success so a deleted folder/
  /// bookmark cannot be referenced by a stale provider:
  ///   1. [pendingFolderDeleteIdProvider] -- the prompt that triggered us.
  ///   2. [pendingFolderEditIdProvider] -- in the rare race where the user
  ///      had an inline rename open on a soon-to-be-deleted folder.
  ///   3. [selectedFolderIdProvider] -- if the deleted subtree contained
  ///      it; FoldersScreen renders its calm "select a folder" placeholder
  ///      rather than leaning on the Story 2.3 defensive fallback.
  ///   4. [expandedFolderIdsProvider] -- prune deleted ids so the set
  ///      doesn't accumulate stale members across multiple deletes.
  ///
  /// Does NOT clean [selectedBookmarkIdProvider]: the live
  /// `selectedBookmarkProvider` already returns null for a missing id
  /// (Story 1.5's pattern). Reaching into bookmark providers from a folder
  /// notifier would couple two features unnecessarily.
  Future<void> deleteFolderCascade(String rootId) async {
    // Snapshot byParent BEFORE any state mutation so the descendant set
    // reflects the tree at the moment of the user's confirmation -- a
    // sync-merge or another action between confirmation and this method's
    // await cannot retroactively change what we delete.
    final byParent = ref.read(folderChildrenIndexProvider);
    final descendants = collectFolderDescendants(rootId, byParent);

    state = const AsyncValue<void>.loading();
    final result =
        await ref.read(folderRepositoryProvider).deleteCascade(descendants);

    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
        // Clear prompt FIRST so the confirmation row collapses on the same
        // emission frame as the tree update -- avoids a flicker where the
        // confirmation briefly outlives its folder.
        ref.read(pendingFolderDeleteIdProvider.notifier).clear();

        final pendingEdit = ref.read(pendingFolderEditIdProvider);
        if (pendingEdit != null && descendants.contains(pendingEdit)) {
          ref.read(pendingFolderEditIdProvider.notifier).clear();
        }

        final selected = ref.read(selectedFolderIdProvider);
        if (selected != null && descendants.contains(selected)) {
          ref.read(selectedFolderIdProvider.notifier).clear();
        }

        final expanded = ref.read(expandedFolderIdsProvider);
        final survivingExpanded = expanded.difference(descendants);
        if (survivingExpanded.length != expanded.length) {
          ref
              .read(expandedFolderIdsProvider.notifier)
              .replace(survivingExpanded);
        }

      case Err(:final error):
        // Confirmation row stays open (we did NOT clear the prompt) so the
        // user can retry or cancel. AsyncValue.error is the surface; no
        // banner is wired for folder errors at MVP.
        state = AsyncValue<void>.error(error, StackTrace.current);
    }
  }

  /// Creates a new folder under [parentId] (root if null) and immediately puts
  /// it into inline-rename mode via [pendingFolderEditIdProvider]. Used by both
  /// the sidebar `+` button and the folder context menu's "New subfolder"
  /// item -- the only difference between those call sites is how [parentId]
  /// is sourced (sidebar reads `selectedFolderIdProvider`; menu uses the
  /// closure-captured folder id). Uses the notifier's own [ref] so a
  /// widget-tree unmount mid-await cannot dangle the rename trigger.
  Future<String?> addFolderAndStartRename({String? parentId}) async {
    final newId = await addFolder(parentId: parentId);
    if (newId != null) {
      ref.read(pendingFolderEditIdProvider.notifier).start(newId);
    }
    return newId;
  }

  /// Walks the ancestor chain starting at [candidateAncestorId]. Returns true
  /// iff [movingFolderId] appears anywhere in the chain -- meaning moving
  /// [movingFolderId] under [candidateAncestorId] would close a loop. O(depth)
  /// -- typical depths < 10. Iterations are hard-capped so a corrupted DB
  /// with a parent loop cannot infinite-loop the move handler.
  Future<bool> _wouldCreateCycle(
    String movingFolderId,
    String candidateAncestorId,
  ) async {
    final repo = ref.read(folderRepositoryProvider);
    String? current = candidateAncestorId;
    for (var i = 0; i < _cycleWalkLimit && current != null; i++) {
      if (current == movingFolderId) return true;
      final result = await repo.getById(current);
      switch (result) {
        case Err():
          // Broken chain (parent vanished). Treat as "no cycle"; Drift will
          // accept the move and the stale parentId becomes orphaned at the
          // next sync merge.
          return false;
        case Ok(:final value):
          current = value.parentId;
      }
    }
    return false;
  }
}

final folderNotifierProvider =
    AsyncNotifierProvider<FolderNotifier, void>(FolderNotifier.new);
