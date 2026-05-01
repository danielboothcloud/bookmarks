// TODO(story-2.1): convert to @riverpod once riverpod_generator is unblocked.
// (Same analyzer-version conflict that pins the bookmarks notifiers --
// see bookmark_providers.dart header.)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/result.dart';
import '../domain/folder.dart';
import 'folder_providers.dart';

class FolderNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();
  static const defaultName = 'New folder';

  @override
  Future<void> build() async {}

  /// Creates a root-level folder with the default name and returns its id.
  /// The caller (sidebar `+` button) immediately sets
  /// [pendingFolderEditIdProvider] to this id so the row enters inline
  /// edit mode on the next reactive emission.
  Future<String?> addFolder() async {
    final now = DateTime.now();
    final folder = Folder(
      id: _uuid.v4(),
      name: defaultName,
      createdAt: now,
      updatedAt: now,
    );
    state = const AsyncValue<void>.loading();
    final result = await ref.read(folderRepositoryProvider).save(folder);
    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
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
    if (trimmed.isEmpty) return;
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
        if (value.name == trimmed) return;
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
}

final folderNotifierProvider =
    AsyncNotifierProvider<FolderNotifier, void>(FolderNotifier.new);
