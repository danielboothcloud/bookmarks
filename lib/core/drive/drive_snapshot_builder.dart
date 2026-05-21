import 'package:drift/drift.dart' show OrderingTerm;

import '../database/app_database.dart';
import 'models/drive_bookmark.dart';
import 'models/drive_bookmarks_file.dart';
import 'models/drive_folder.dart';
import 'models/drive_tag.dart';

/// Reads the local Drift state and assembles a canonical
/// [DriveBookmarksFile] v1 envelope ready for upload.
///
/// Goes directly to `AppDatabase` (rather than through the feature
/// repositories) for one structural reason: the per-bookmark `tagIds`
/// array needs the raw `bookmark_tags` junction, which no single
/// repository exposes without an N+1 fan-out. The architecture
/// explicitly permits `core/drive/` to consume `core/database/`
/// directly (architecture line 638-647).
///
/// Outputs deterministic JSON: arrays are sorted by `createdAt` ASC
/// then `id` ASC so a stable database produces byte-identical JSON
/// across snapshot calls -- useful for tests and for diffing Drive
/// revisions across versions.
class DriveSnapshotBuilder {
  DriveSnapshotBuilder(
    this._db, {
    DateTime Function() clock = _defaultClock,
  }) : _clock = clock;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  /// Returns a snapshot of the current local state in the canonical v1
  /// envelope. The four table reads happen inside a single transaction
  /// so the snapshot is point-in-time consistent (no half-written
  /// junction rows).
  Future<DriveBookmarksFile> build() async {
    final result = await _db.transaction(() async {
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

      // Group junctions by bookmarkId for O(1) lookup during conversion.
      final tagIdsByBookmark = <String, List<String>>{};
      for (final j in junctionRows) {
        tagIdsByBookmark
            .putIfAbsent(j.bookmarkId, () => <String>[])
            .add(j.tagId);
      }

      return (
        bookmarks: bookmarkRows,
        folders: folderRows,
        tags: tagRows,
        tagIdsByBookmark: tagIdsByBookmark,
      );
    });

    return DriveBookmarksFile(
      version: 1,
      lastModified: _clock().toIso8601String(),
      bookmarks: result.bookmarks
          .map(
            (row) => _toDriveBookmark(
              row,
              result.tagIdsByBookmark[row.id] ?? const <String>[],
            ),
          )
          .toList(growable: false),
      folders: result.folders.map(_toDriveFolder).toList(growable: false),
      tags: result.tags.map(_toDriveTag).toList(growable: false),
    );
  }

  static DriveBookmark _toDriveBookmark(BookmarkRow row, List<String> tagIds) {
    return DriveBookmark(
      id: row.id,
      url: row.url,
      title: row.title,
      notes: row.notes,
      folderId: row.folderId,
      faviconBase64: row.faviconBase64,
      tagIds: tagIds,
      createdAt: _toIsoUtc(row.createdAt),
      updatedAt: _toIsoUtc(row.updatedAt),
    );
  }

  static DriveFolder _toDriveFolder(FolderRow row) {
    return DriveFolder(
      id: row.id,
      name: row.name,
      parentId: row.parentId,
      createdAt: _toIsoUtc(row.createdAt),
      updatedAt: _toIsoUtc(row.updatedAt),
    );
  }

  static DriveTag _toDriveTag(TagRow row) {
    return DriveTag(
      id: row.id,
      name: row.name,
      createdAt: _toIsoUtc(row.createdAt),
      updatedAt: _toIsoUtc(row.updatedAt),
    );
  }

  static String _toIsoUtc(int msSinceEpoch) {
    return DateTime.fromMillisecondsSinceEpoch(msSinceEpoch, isUtc: true)
        .toIso8601String();
  }
}
