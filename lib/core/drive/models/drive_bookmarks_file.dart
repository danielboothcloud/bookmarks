import 'package:freezed_annotation/freezed_annotation.dart';

import 'drive_bookmark.dart';
import 'drive_folder.dart';
import 'drive_tag.dart';

part 'drive_bookmarks_file.freezed.dart';
part 'drive_bookmarks_file.g.dart';

/// The canonical envelope for `bookmarks.json` stored in
/// `appDataFolder`. Version 1 (Story 4.2). Once any user has data in
/// Drive at v1, the format is permanent until a properly-versioned
/// migration replaces it.
///
/// Top-level shape (declaration order = JSON emit order):
///   `version` (always `1` at this revision),
///   `lastModified` (ISO 8601 UTC string with `Z` suffix),
///   `bookmarks`, `folders`, `tags`.
///
/// Top-level arrays are sorted by `createdAt` ASC then `id` ASC by the
/// snapshot builder, so a stable database produces byte-identical JSON
/// across snapshot calls -- useful both for tests and for diffing what
/// changed across versions in Drive.
@freezed
abstract class DriveBookmarksFile with _$DriveBookmarksFile {
  const factory DriveBookmarksFile({
    required int version,
    required String lastModified,
    @Default(<DriveBookmark>[]) List<DriveBookmark> bookmarks,
    @Default(<DriveFolder>[]) List<DriveFolder> folders,
    @Default(<DriveTag>[]) List<DriveTag> tags,
  }) = _DriveBookmarksFile;

  factory DriveBookmarksFile.fromJson(Map<String, dynamic> json) =>
      _$DriveBookmarksFileFromJson(json);
}
