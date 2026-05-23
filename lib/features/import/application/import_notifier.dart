import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../domain/import_failure_reason.dart';
import '../domain/import_progress.dart';
import '../domain/import_state.dart';
import '../domain/parsed_bookmarks_tree.dart';
import 'import_providers.dart';

/// Orchestrates the import lifecycle: open the file picker → read
/// bytes → parse → write → settle into a terminal state.
///
/// **Debounce.** [pickAndImport] is a no-op if the current state is
/// anything other than `ImportIdle`. The Settings UI hides the button
/// during writing, but a second-click guard at the notifier level is
/// the load-bearing defence (AC12).
///
/// **AsyncNotifier choice.** Same shape as `DriveAuthNotifier` in
/// `lib/core/drive/drive_auth_providers.dart` — async because reading
/// the picked HTML file is async, sealed-state because the import
/// surface has discrete phases the UI needs to switch on.
class ImportNotifier extends AsyncNotifier<ImportState> {
  @override
  Future<ImportState> build() async => const ImportIdle();

  Future<void> pickAndImport() async {
    final current = state.value;
    // Allow re-import from a terminal state (succeeded / failed) by
    // dropping back to picking immediately. Guard only against an
    // already-in-flight run.
    if (current is ImportPicking ||
        current is ImportParsing ||
        current is ImportWriting) {
      return;
    }

    state = const AsyncData(ImportPicking());
    final picker = ref.read(filePickerProvider);
    final String? path;
    try {
      path = await picker.pickHtmlFile();
    } catch (_) {
      // Surface as invalid-file rather than crashing the UI. The
      // file_picker package occasionally throws on unusual sandbox
      // configurations; the user's mental model maps "I selected
      // something and nothing useful happened" to "invalid file"
      // more cleanly than a generic "storage error".
      state = const AsyncData(ImportFailed(ImportFailureReason.invalidFile));
      return;
    }
    if (path == null) {
      // AC7 / state-machine contract: user cancel is silent — drop
      // straight back to idle. Not a "failed" terminal state.
      state = const AsyncData(ImportIdle());
      return;
    }

    state = const AsyncData(ImportParsing());

    final String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      state = const AsyncData(ImportFailed(ImportFailureReason.invalidFile));
      return;
    }

    final parser = ref.read(browserBookmarksHtmlParserProvider);
    final tree = parser.parse(content);

    if (_isEmpty(tree)) {
      state = const AsyncData(ImportFailed(ImportFailureReason.invalidFile));
      return;
    }

    final service = ref.read(bookmarkImportServiceProvider);
    state = const AsyncData(ImportWriting(
      ImportProgress(itemsWritten: 0, totalItems: 0),
    ));
    final result = await service.importTree(
      tree,
      onProgress: (p) {
        state = AsyncData(ImportWriting(p));
      },
    );
    switch (result) {
      case Ok(:final value):
        state = AsyncData(ImportSucceeded(value));
      case Err():
        state = const AsyncData(
            ImportFailed(ImportFailureReason.storageError));
    }
  }

  /// Drops a terminal state back to [ImportIdle] so the user can
  /// start another import. No-op when called from a non-terminal
  /// state — the active import owns transitions while it runs.
  void resetToIdle() {
    final current = state.value;
    if (current is ImportSucceeded || current is ImportFailed) {
      state = const AsyncData(ImportIdle());
    }
  }

  /// A tree is "empty" when no bookmark exists anywhere in it — root or
  /// nested. Empty trees are classified as `invalidFile` because a
  /// browser-exported bookmark file that produces zero bookmarks is
  /// indistinguishable from a non-bookmark HTML page (or a malformed
  /// export). A folder-structure-only template (no bookmarks at any
  /// depth) is therefore deliberately rejected — importing it would
  /// create empty folders with no user value, and surfacing the calm
  /// "doesn't appear to be a bookmark export" copy is the correct UX.
  bool _isEmpty(ParsedBookmarksTree tree) {
    if (tree.rootBookmarks.isNotEmpty) return false;
    return tree.rootFolders.every(_folderEmpty);
  }

  bool _folderEmpty(ParsedFolderNode node) {
    if (node.bookmarks.isNotEmpty) return false;
    if (node.subfolders.isEmpty) return true;
    return node.subfolders.every(_folderEmpty);
  }
}
