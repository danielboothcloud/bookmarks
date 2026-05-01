import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/database/app_database.dart';

part 'folder.freezed.dart';

@freezed
abstract class Folder with _$Folder {
  const factory Folder({
    required String id,
    required String name,
    String? parentId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Folder;

  factory Folder.fromDrift(FolderRow row) => Folder(
        id: row.id,
        name: row.name,
        parentId: row.parentId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      );
}
