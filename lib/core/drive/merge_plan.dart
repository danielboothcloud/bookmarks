import 'package:freezed_annotation/freezed_annotation.dart';

import 'models/drive_bookmark.dart';
import 'models/drive_folder.dart';
import 'models/drive_tag.dart';

part 'merge_plan.freezed.dart';

/// Pure output of [MergeEngine.merge]: the set of writes the applier
/// must perform to bring the local DB into convergence with the
/// remote envelope.
///
/// Each list contains records to upsert (the wire-shape Drive types)
/// or string IDs to delete. `bookmarkTagLinksToReplace` is keyed by
/// `bookmarkId` and carries the FULL desired tag-id set for that
/// bookmark (a single bookmark's junction set is a function of the
/// bookmark's `updatedAt`, not per-link timestamps).
///
/// `foldersToUpsert` is emitted in topological order (parents before
/// children) so the applier can stream upserts in iteration order
/// without resorting.
@freezed
abstract class MergePlan with _$MergePlan {
  const factory MergePlan({
    required List<DriveBookmark> bookmarksToUpsert,
    required List<String> bookmarksToDelete,
    required List<DriveFolder> foldersToUpsert,
    required List<String> foldersToDelete,
    required List<DriveTag> tagsToUpsert,
    required List<String> tagsToDelete,
    required Map<String, List<String>> bookmarkTagLinksToReplace,
  }) = _MergePlan;
}
