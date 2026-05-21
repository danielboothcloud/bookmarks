import 'package:drift/drift.dart' show OrderingTerm;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../database/app_database.dart';

part 'local_snapshot.freezed.dart';

/// Point-in-time snapshot of the local Drift state in the shape the
/// merge engine consumes.
///
/// Built either by [DriveSnapshotBuilder.readLocalSnapshot] (for the
/// push path, which then converts to [DriveBookmarksFile]) or by
/// [MergeApplier] inside its merge transaction (for the pull path,
/// where the snapshot must be point-in-time-consistent with the
/// transaction's writes that follow).
///
/// `tagIdsByBookmark` is the pre-grouped junction set keyed by
/// `bookmarkId` — same shape `DriveSnapshotBuilder` already assembles.
/// The grouping happens at snapshot time so the engine never re-walks
/// the junction list.
@freezed
abstract class LocalSnapshot with _$LocalSnapshot {
  const factory LocalSnapshot({
    required List<BookmarkRow> bookmarks,
    required List<FolderRow> folders,
    required List<TagRow> tags,
    required Map<String, List<String>> tagIdsByBookmark,
  }) = _LocalSnapshot;
}

/// Reads the four sync-relevant tables and assembles a [LocalSnapshot].
/// Caller MUST already be inside a `_db.transaction(...)` block — Drift
/// does not support nested transactions.
///
/// Shared by [DriveSnapshotBuilder] (push path) and [MergeApplier]
/// (pull path) so the snapshot shape stays in lock-step.
Future<LocalSnapshot> readLocalSnapshotInTransaction(AppDatabase db) async {
  final bookmarkRows = await (db.select(db.bookmarks)
        ..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  final folderRows = await (db.select(db.folders)
        ..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  final tagRows = await (db.select(db.tags)
        ..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  final junctionRows = await (db.select(db.bookmarkTags)
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
