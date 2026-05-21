// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drive_folder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DriveFolder _$DriveFolderFromJson(Map<String, dynamic> json) => _DriveFolder(
  id: json['id'] as String,
  name: json['name'] as String,
  parentId: json['parentId'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, dynamic> _$DriveFolderToJson(_DriveFolder instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'parentId': ?instance.parentId,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };
