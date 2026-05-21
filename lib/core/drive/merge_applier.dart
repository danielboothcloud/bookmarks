import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../error/app_error.dart';
import '../error/result.dart';
import 'local_snapshot.dart';
import 'merge_engine.dart';
import 'models/drive_bookmark.dart';
import 'models/drive_bookmarks_file.dart';
import 'models/drive_folder.dart';
import 'models/drive_tag.dart';

/// Applies a parsed remote [DriveBookmarksFile] to the local Drift
/// database by computing a per-record LWW merge plan and writing the
/// plan inside a single transaction.
///
/// Story 4.3 design decisions enforced here:
///
///  * **Single transaction.** All merge writes — folder/bookmark/tag
///    upserts, junction replacements, cascade deletes, orphan-tag
///    sweep, AND the cursor cleanup — happen inside one
///    `_db.transaction(...)` block. A crash mid-merge rolls
///    everything back (NFR13).
///
///  * **Inline replication of repository transaction shapes.** Drift
///    does NOT support nested transactions, so calling
///    `BookmarkRepository.delete` / `FolderRepository.deleteCascade` /
///    `TagRepository.unlinkBookmarkTag` from inside the merge would
///    throw. Instead this file replicates their SQL inline. If those
///    repositories ever evolve their cascade / sweep behavior, this
///    applier MUST follow suit. Source-of-truth:
///    `lib/features/bookmarks/data/bookmark_repository.dart` (delete),
///    `lib/features/folders/data/folder_repository.dart`
///    (deleteCascade), and
///    `lib/features/tags/data/tag_repository.dart` (unlinkBookmarkTag
///    sweep). Architecture rationale: architecture.md:856
///    Application-Layer Integrity.
///
///  * **Trigger feedback cleanup.** The 11 outbox triggers from
///    Story 4.2 fire on every merge write, queuing a `sync_queue`
///    row per record. Without intervention, the auto-push
///    orchestrator would observe a non-zero queue immediately after
///    the merge and push the just-merged state straight back to
///    Drive (ping-pong). The fix:
///      1. Snapshot `cursorId = COALESCE(MAX(id), 0)` from
///         `sync_queue` BEFORE the merge writes.
///      2. Apply the merge.
///      3. `DELETE FROM sync_queue WHERE id > cursorId` — drops
///         only the rows the merge itself produced; any user
///         mutation already pending pre-merge is preserved.
///    The whole sequence runs inside the merge transaction, so a
///    rollback leaves the queue at its pre-merge state.
///
///  * **Dependency-correct write order.** Folders → bookmarks → tags
///    → junction replacements → bookmark deletes (cascade junctions)
///    → folder deletes (cascade bookmarks + junctions) → tag deletes
///    → final orphan-tag sweep. SQLite has no FK enforcement on
///    `bookmark_tags`; the application enforces integrity here.
class MergeApplier {
  MergeApplier(this._db);

  final AppDatabase _db;

  /// Computes the merge plan for [remote] against the current local
  /// state and writes it inside a single Drift transaction.
  ///
  /// Returns:
  ///  * `Ok(null)` on successful commit (including the empty-plan
  ///    no-op case).
  ///  * `Err(StorageError(...))` on transaction-level failure (any
  ///    exception during the transaction body rolls back ALL writes).
  Future<Result<void, AppError>> apply(DriveBookmarksFile remote) async {
    try {
      await _db.transaction(() async {
        final local = await _readLocalSnapshotInTxn();
        final plan = MergeEngine.merge(local: local, remote: remote);
        final cursorId = await _readMaxQueueId();

        await _applyFolderUpserts(plan.foldersToUpsert);
        await _applyBookmarkUpserts(plan.bookmarksToUpsert);
        await _applyTagUpserts(plan.tagsToUpsert);
        await _applyJunctionReplacements(plan.bookmarkTagLinksToReplace);
        await _applyBookmarkDeletes(plan.bookmarksToDelete);
        await _applyFolderDeletes(plan.foldersToDelete);
        await _applyTagDeletes(plan.tagsToDelete);
        await _sweepOrphanTags();

        // Cursor cleanup — drops any sync_queue rows the merge writes
        // above caused via the 4.2 outbox triggers. Rows whose id is
        // <= cursorId existed BEFORE the merge (real pending user
        // mutations) and survive. If cursorId == 0 the queue was empty
        // pre-merge, so "WHERE id > 0" still works correctly (autoinc
        // ids start at 1).
        await _db.customUpdate(
          'DELETE FROM sync_queue WHERE id > ?',
          variables: [Variable<int>(cursorId)],
          updates: {_db.syncQueue},
        );
      });
      return const Ok<void, AppError>(null);
    } catch (e) {
      return Err<void, AppError>(StorageError(e.toString()));
    }
  }

  Future<int> _readMaxQueueId() async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(MAX(id), 0) AS m FROM sync_queue',
          readsFrom: {_db.syncQueue},
        )
        .getSingle();
    return row.read<int>('m');
  }

  // Inline duplicate of DriveSnapshotBuilder's read pass. Read here
  // (rather than reusing the builder) so the snapshot is captured
  // inside the merge transaction with no extra ceremony.
  Future<LocalSnapshot> _readLocalSnapshotInTxn() async {
    final bookmarkRows = await (_db.select(_db.bookmarks)
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final folderRows = await (_db.select(_db.folders)
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final tagRows = await (_db.select(_db.tags)
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final junctionRows = await (_db.select(_db.bookmarkTags)
          ..orderBy([
            (t) => OrderingTerm.asc(t.tagId),
          ]))
        .get();
    final tagIdsByBookmark = <String, List<String>>{};
    for (final j in junctionRows) {
      tagIdsByBookmark
          .putIfAbsent(j.bookmarkId, () => <String>[])
          .add(j.tagId);
    }
    return LocalSnapshot(
      bookmarks: bookmarkRows,
      folders: folderRows,
      tags: tagRows,
      tagIdsByBookmark: tagIdsByBookmark,
    );
  }

  Future<void> _applyFolderUpserts(List<DriveFolder> folders) async {
    for (final f in folders) {
      await _db.into(_db.folders).insertOnConflictUpdate(
            FoldersCompanion(
              id: Value(f.id),
              name: Value(f.name),
              parentId: Value(f.parentId),
              createdAt: Value(_isoToMs(f.createdAt)),
              updatedAt: Value(_isoToMs(f.updatedAt)),
            ),
          );
    }
  }

  Future<void> _applyBookmarkUpserts(List<DriveBookmark> bookmarks) async {
    for (final b in bookmarks) {
      await _db.into(_db.bookmarks).insertOnConflictUpdate(
            BookmarksCompanion(
              id: Value(b.id),
              url: Value(b.url),
              title: Value(b.title),
              notes: Value(b.notes),
              folderId: Value(b.folderId),
              faviconBase64: Value(b.faviconBase64),
              createdAt: Value(_isoToMs(b.createdAt)),
              updatedAt: Value(_isoToMs(b.updatedAt)),
            ),
          );
    }
  }

  Future<void> _applyTagUpserts(List<DriveTag> tags) async {
    for (final t in tags) {
      await _db.into(_db.tags).insertOnConflictUpdate(
            TagsCompanion(
              id: Value(t.id),
              name: Value(t.name),
              createdAt: Value(_isoToMs(t.createdAt)),
              updatedAt: Value(_isoToMs(t.updatedAt)),
            ),
          );
    }
  }

  Future<void> _applyJunctionReplacements(
    Map<String, List<String>> linksByBookmark,
  ) async {
    for (final entry in linksByBookmark.entries) {
      final bookmarkId = entry.key;
      final newTagIds = entry.value;
      // Replace strategy: drop every junction for this bookmark, then
      // insert the desired set. Fires bookmark_tags triggers — sync
      // queue rows generated here are cleaned up by the cursor sweep.
      await (_db.delete(_db.bookmarkTags)
            ..where((t) => t.bookmarkId.equals(bookmarkId)))
          .go();
      for (final tagId in newTagIds) {
        await _db.into(_db.bookmarkTags).insert(
              BookmarkTagsCompanion(
                bookmarkId: Value(bookmarkId),
                tagId: Value(tagId),
                createdAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }

  /// Inline replica of `BookmarkRepository.delete`'s transaction
  /// shape: junctions first, then the bookmark row. The orphan-tag
  /// sweep is deferred to the final pass so it runs once across all
  /// merge deletes.
  Future<void> _applyBookmarkDeletes(List<String> ids) async {
    for (final id in ids) {
      await (_db.delete(_db.bookmarkTags)
            ..where((t) => t.bookmarkId.equals(id)))
          .go();
      await (_db.delete(_db.bookmarks)..where((t) => t.id.equals(id))).go();
    }
  }

  /// Inline replica of `FolderRepository.deleteCascade`: junction
  /// rows for cascaded bookmarks → cascaded bookmarks → the folder.
  /// Orphan-tag sweep deferred to the final pass.
  Future<void> _applyFolderDeletes(List<String> ids) async {
    for (final id in ids) {
      await _db.customUpdate(
        'DELETE FROM bookmark_tags WHERE bookmark_id IN ('
        '  SELECT id FROM bookmarks WHERE folder_id = ?'
        ')',
        variables: [Variable<String>(id)],
        updates: {_db.bookmarkTags},
      );
      await (_db.delete(_db.bookmarks)..where((t) => t.folderId.equals(id)))
          .go();
      await (_db.delete(_db.folders)..where((t) => t.id.equals(id))).go();
    }
  }

  /// Direct tag deletion (no junctions expected, but defensive
  /// cleanup runs first in case of a malformed remote envelope).
  Future<void> _applyTagDeletes(List<String> ids) async {
    for (final id in ids) {
      await (_db.delete(_db.bookmarkTags)..where((t) => t.tagId.equals(id)))
          .go();
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
    }
  }

  /// Final pass: hard-delete tags whose last junction was removed
  /// during this merge. Mirrors the FR16 sweep at the tail of
  /// `BookmarkRepository.delete` and `FolderRepository.deleteCascade`.
  ///
  /// Scoped to tags absent from the remote upsert list? No — the
  /// merge upserts may have added new tags whose junctions are about
  /// to be created by the junction replacement pass. Run AFTER the
  /// junction replacements so newly-arrived tags (with junctions)
  /// survive while genuinely orphaned tags are dropped.
  Future<void> _sweepOrphanTags() async {
    await _db.customUpdate(
      'DELETE FROM tags '
      'WHERE id NOT IN (SELECT DISTINCT tag_id FROM bookmark_tags)',
      updates: {_db.tags},
    );
  }

  static int _isoToMs(String iso) {
    return DateTime.parse(iso).toUtc().millisecondsSinceEpoch;
  }
}

