// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drive_bookmarks_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DriveBookmarksFile _$DriveBookmarksFileFromJson(Map<String, dynamic> json) =>
    _DriveBookmarksFile(
      version: (json['version'] as num).toInt(),
      lastModified: json['lastModified'] as String,
      bookmarks:
          (json['bookmarks'] as List<dynamic>?)
              ?.map((e) => DriveBookmark.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <DriveBookmark>[],
      folders:
          (json['folders'] as List<dynamic>?)
              ?.map((e) => DriveFolder.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <DriveFolder>[],
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((e) => DriveTag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <DriveTag>[],
    );

Map<String, dynamic> _$DriveBookmarksFileToJson(_DriveBookmarksFile instance) =>
    <String, dynamic>{
      'version': instance.version,
      'lastModified': instance.lastModified,
      'bookmarks': instance.bookmarks.map((e) => e.toJson()).toList(),
      'folders': instance.folders.map((e) => e.toJson()).toList(),
      'tags': instance.tags.map((e) => e.toJson()).toList(),
    };
