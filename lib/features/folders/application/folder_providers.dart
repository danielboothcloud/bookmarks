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
