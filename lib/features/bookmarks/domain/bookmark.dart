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
}
