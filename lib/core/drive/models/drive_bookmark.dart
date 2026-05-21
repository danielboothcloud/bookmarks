import 'package:freezed_annotation/freezed_annotation.dart';

part 'drive_bookmark.freezed.dart';
part 'drive_bookmark.g.dart';

/// Per-bookmark entry inside the canonical `bookmarks.json` envelope.
///
/// Field order (declaration order = JSON emit order):
/// `id`, `url`, `title`, `notes`, `folderId`, `faviconBase64`, `tagIds`,
/// `createdAt`, `updatedAt`.
///
/// Optional fields (`notes`, `folderId`, `faviconBase64`) are omitted
/// from the wire JSON when null per `@JsonSerializable(includeIfNull:
/// false)`. `tagIds` is always present (possibly empty) -- the explicit
/// empty list avoids the null-vs-empty foot-gun across language
/// boundaries.
///
/// `faviconBase64`, when present, includes the `data:image/<mime>;base64,`
/// prefix as stored locally -- the wire format matches the on-disk
/// format byte-for-byte.
@freezed
abstract class DriveBookmark with _$DriveBookmark {
  const factory DriveBookmark({
    required String id,
    required String url,
    required String title,
    String? notes,
    String? folderId,
    String? faviconBase64,
    @Default(<String>[]) List<String> tagIds,
    required String createdAt,
    required String updatedAt,
  }) = _DriveBookmark;

  factory DriveBookmark.fromJson(Map<String, dynamic> json) =>
      _$DriveBookmarkFromJson(json);
}
