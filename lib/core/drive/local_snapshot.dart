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
