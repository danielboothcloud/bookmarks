import 'package:freezed_annotation/freezed_annotation.dart';

part 'drive_folder.freezed.dart';
part 'drive_folder.g.dart';

/// Per-folder entry inside the canonical `bookmarks.json` envelope.
///
/// Top-level folders carry `parentId == null`; nested folders carry the
/// parent's UUID. The null case is omitted from the emitted JSON per
/// `@JsonSerializable(includeIfNull: false)`.
@freezed
abstract class DriveFolder with _$DriveFolder {
  const factory DriveFolder({
    required String id,
    required String name,
    String? parentId,
    required String createdAt,
    required String updatedAt,
  }) = _DriveFolder;

  factory DriveFolder.fromJson(Map<String, dynamic> json) =>
      _$DriveFolderFromJson(json);
}
