// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drive_bookmark.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DriveBookmark _$DriveBookmarkFromJson(Map<String, dynamic> json) =>
    _DriveBookmark(
      id: json['id'] as String,
      url: json['url'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String?,
      folderId: json['folderId'] as String?,
      faviconBase64: json['faviconBase64'] as String?,
      tagIds:
          (json['tagIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );

Map<String, dynamic> _$DriveBookmarkToJson(_DriveBookmark instance) =>
    <String, dynamic>{
      'id': instance.id,
      'url': instance.url,
      'title': instance.title,
      'notes': ?instance.notes,
      'folderId': ?instance.folderId,
      'faviconBase64': ?instance.faviconBase64,
      'tagIds': instance.tagIds,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };
