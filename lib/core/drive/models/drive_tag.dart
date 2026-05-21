import 'package:freezed_annotation/freezed_annotation.dart';

part 'drive_tag.freezed.dart';
part 'drive_tag.g.dart';

/// Per-tag entry inside the canonical `bookmarks.json` envelope.
///
/// Tags carry identity (`id`) and an `updatedAt` timestamp so Story
/// 4.3's per-tag LWW merge can resolve renames without losing
/// per-bookmark linkage. Embedding tag names per-bookmark would lose
/// rename semantics.
@freezed
abstract class DriveTag with _$DriveTag {
  const factory DriveTag({
    required String id,
    required String name,
    required String createdAt,
    required String updatedAt,
  }) = _DriveTag;

  factory DriveTag.fromJson(Map<String, dynamic> json) =>
      _$DriveTagFromJson(json);
}
