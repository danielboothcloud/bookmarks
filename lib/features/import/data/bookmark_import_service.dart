import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import '../../bookmarks/domain/bookmark.dart';
import '../../bookmarks/domain/i_bookmark_repository.dart';
import '../../folders/domain/folder.dart';
import '../../folders/domain/i_folder_repository.dart';
import '../domain/import_progress.dart';
import '../domain/import_result.dart';
import '../domain/parsed_bookmarks_tree.dart';

/// Walks a [ParsedBookmarksTree] and writes its folders + bookmarks
/// through the repository layer.
///
/// **Invariant — repository-only writes.** Every mutation goes through
/// `IFolderRepository.save` and `IBookmarkRepository.save`. Direct
/// Drift inserts would bypass `sync_triggers.drift` (the 11 outbox
/// triggers that enqueue Drive sync rows) AND `bookmarks_fts.drift`
/// (the 5 FTS triggers that maintain the search index). The
/// architecture's "Application-Layer Integrity" section (Epic 2 A1,
/// reaffirmed Epic 4 retro §0) is load-bearing for Epic 5 — see
/// `docs/import-model.md` § Writer contract.
///
/// **NFR5 — responsive 500+ import.** Drift requires the main isolate
/// on macOS, so isolate-based parallelism is unavailable (Epic 4 retro
/// §8). Instead, the writer yields to the frame scheduler every
/// [_batchSize] writes via `Future<void>.delayed(Duration.zero)`. This
/// lets `LinearProgressIndicator` repaint and keeps the Settings
/// `ListView` scrollable during a 500-bookmark import.
///
/// **Folder parent-before-child.** A depth-first walk emits each
/// parent folder before its children so the child's `parentId` always
/// resolves at write time.
///
/// **Failure mode.** Partial writes are NOT rolled back. Wrapping the
/// 500-write run in a single Drift transaction would block sync for
/// the entire import duration and triples memory usage in the engine.
/// Instead, an early failure returns `Err(StorageError(...))` with
/// whatever folders/bookmarks made it through still persisted; the
/// user-visible message is the calm "Couldn't save imported
/// bookmarks. Try again?" copy. The next import attempt picks up
/// fresh; no partial-recovery semantics.
class BookmarkImportService {
  BookmarkImportService({
    required IFolderRepository folderRepo,
    required IBookmarkRepository bookmarkRepo,
    Uuid? uuid,
    DateTime Function()? now,
  })  : _folderRepo = folderRepo,
        _bookmarkRepo = bookmarkRepo,
        _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now;

  final IFolderRepository _folderRepo;
  final IBookmarkRepository _bookmarkRepo;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Yield to the frame scheduler every N writes. 50 chosen as a
  /// starting point — tune up if dev profiling shows the yields
  /// dominate the import time; tune down if 500-bookmark imports
  /// produce visible jank. See `docs/import-model.md` § NFR5 strategy.
  static const int _batchSize = 50;

  Future<Result<ImportResult, AppError>> importTree(
    ParsedBookmarksTree tree, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final startedAt = DateTime.now();
    final totalItems = _countItems(tree);
    var itemsWritten = 0;
    var foldersCreated = 0;
    var bookmarksImported = 0;
    var itemsSkipped = tree.unparseableItems;
    // Story 5.2: collect every bookmark UUID the writer successfully
    // persists. The notifier hands this list to
    // `ImportFaviconBackfillService.backfill` after `ImportSucceeded`.
    // Folders are NOT tracked — they don't have favicons.
    final importedBookmarkIds = <String>[];

    // Empty tree: short-circuit. The notifier upstream interprets an
    // empty tree as an "invalid file" — we still return Ok with zero
    // counts in case the caller decided to import an empty folder
    // intentionally.
    if (totalItems == 0) {
      return Ok(ImportResult(
        foldersCreated: 0,
        bookmarksImported: 0,
        itemsSkipped: itemsSkipped,
        elapsed: DateTime.now().difference(startedAt),
        importedBookmarkIds: const <String>[],
      ));
    }

    Future<Result<void, AppError>> maybeYield() async {
      if (itemsWritten % _batchSize == 0 && itemsWritten > 0) {
        onProgress?.call(ImportProgress(
          itemsWritten: itemsWritten,
          totalItems: totalItems,
        ));
        await Future<void>.delayed(Duration.zero);
      }
      return const Ok(null);
    }

    Future<Result<void, AppError>> writeBookmark(
      ParsedBookmark parsed,
      String? folderId,
    ) async {
      // Defensive — parser already drops empty-href entries via the
      // unparseableItems counter. If somehow one slips through we
      // skip it here too rather than persisting a malformed row.
      if (parsed.url.trim().isEmpty) {
        itemsSkipped++;
        return const Ok(null);
      }
      final now = _now();
      final bookmark = Bookmark(
        id: _uuid.v4(),
        url: parsed.url,
        title: parsed.title,
        folderId: folderId,
        createdAt: now,
        updatedAt: now,
      );
      final result = await _bookmarkRepo.save(bookmark);
      switch (result) {
        case Err(:final error):
          return Err(error);
        case Ok():
          break;
      }
      importedBookmarkIds.add(bookmark.id);
      bookmarksImported++;
      itemsWritten++;
      await maybeYield();
      return const Ok(null);
    }

    Future<Result<void, AppError>> writeFolder(
      ParsedFolderNode node,
      String? parentId,
    ) async {
      final now = _now();
      final folder = Folder(
        id: _uuid.v4(),
        name: node.name,
        parentId: parentId,
        createdAt: now,
        updatedAt: now,
      );
      final saveResult = await _folderRepo.save(folder);
      switch (saveResult) {
        case Err(:final error):
          return Err(error);
        case Ok():
          break;
      }
      foldersCreated++;
      itemsWritten++;
      await maybeYield();

      for (final bm in node.bookmarks) {
        final bmResult = await writeBookmark(bm, folder.id);
        switch (bmResult) {
          case Err(:final error):
            return Err(error);
          case Ok():
            break;
        }
      }
      for (final sub in node.subfolders) {
        final subResult = await writeFolder(sub, folder.id);
        switch (subResult) {
          case Err(:final error):
            return Err(error);
          case Ok():
            break;
        }
      }
      return const Ok(null);
    }

    // Walk root bookmarks first (no parent folder), then root folders
    // depth-first. Order isn't load-bearing for the DB — `parentId`
    // resolves so long as the parent folder was written first — but
    // doing roots-first keeps the progress count monotonic in a way
    // that matches user intuition ("the orphan bookmarks were the
    // small initial batch; folders came next").
    for (final bm in tree.rootBookmarks) {
      final r = await writeBookmark(bm, null);
      switch (r) {
        case Err(:final error):
          return Err(error);
        case Ok():
          break;
      }
    }
    for (final folder in tree.rootFolders) {
      final r = await writeFolder(folder, null);
      switch (r) {
        case Err(:final error):
          return Err(error);
        case Ok():
          break;
      }
    }

    // Final progress emit so the UI sees the terminal "N/N" before
    // flipping to ImportSucceeded.
    onProgress?.call(ImportProgress(
      itemsWritten: itemsWritten,
      totalItems: totalItems,
    ));

    return Ok(ImportResult(
      foldersCreated: foldersCreated,
      bookmarksImported: bookmarksImported,
      itemsSkipped: itemsSkipped,
      elapsed: DateTime.now().difference(startedAt),
      importedBookmarkIds: List.unmodifiable(importedBookmarkIds),
    ));
  }

  /// Total writable items in [tree] — folders + bookmarks across all
  /// depths plus any root-level bookmarks. Used to compute the
  /// `totalItems` denominator surfaced to the UI's progress widget.
  int _countItems(ParsedBookmarksTree tree) {
    var count = tree.rootBookmarks.length;
    void walk(List<ParsedFolderNode> folders) {
      for (final f in folders) {
        count++;
        count += f.bookmarks.length;
        walk(f.subfolders);
      }
    }
    walk(tree.rootFolders);
    return count;
  }
}
