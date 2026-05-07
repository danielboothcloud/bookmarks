import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/database/app_database.dart';

part 'bookmark.freezed.dart';

@freezed
abstract class Bookmark with _$Bookmark {
  const factory Bookmark({
    required String id,
    required String url,
    required String title,
    String? notes,
    String? folderId,
    String? faviconBase64,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Bookmark;

  factory Bookmark.fromDrift(BookmarkRow row) => Bookmark(
        id: row.id,
        url: row.url,
        title: row.title,
        notes: row.notes,
        folderId: row.folderId,
        faviconBase64: row.faviconBase64,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      );

  /// Build a Bookmark from primitive column values. Used by `customSelect`
  /// query callers (e.g. [BookmarkRepository.watchByTagId]) that receive a
  /// Drift `QueryRow` rather than the typed `BookmarkRow` companion. The
  /// alternative -- materialising a `BookmarkRow` from the QueryRow then
  /// calling [Bookmark.fromDrift] -- is two conversions; this is one.
  factory Bookmark.fromDriftRow({
    required String id,
    required String url,
    required String title,
    String? notes,
    String? folderId,
    String? faviconBase64,
    required int createdAt,
    required int updatedAt,
  }) =>
      Bookmark(
        id: id,
        url: url,
        title: title,
        notes: notes,
        folderId: folderId,
        faviconBase64: faviconBase64,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      );
}
