// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'drive_bookmark.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DriveBookmark {

 String get id; String get url; String get title; String? get notes; String? get folderId; String? get faviconBase64; List<String> get tagIds; String get createdAt; String get updatedAt;
/// Create a copy of DriveBookmark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DriveBookmarkCopyWith<DriveBookmark> get copyWith => _$DriveBookmarkCopyWithImpl<DriveBookmark>(this as DriveBookmark, _$identity);

  /// Serializes this DriveBookmark to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveBookmark&&(identical(other.id, id) || other.id == id)&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.folderId, folderId) || other.folderId == folderId)&&(identical(other.faviconBase64, faviconBase64) || other.faviconBase64 == faviconBase64)&&const DeepCollectionEquality().equals(other.tagIds, tagIds)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,url,title,notes,folderId,faviconBase64,const DeepCollectionEquality().hash(tagIds),createdAt,updatedAt);

@override
String toString() {
  return 'DriveBookmark(id: $id, url: $url, title: $title, notes: $notes, folderId: $folderId, faviconBase64: $faviconBase64, tagIds: $tagIds, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $DriveBookmarkCopyWith<$Res>  {
  factory $DriveBookmarkCopyWith(DriveBookmark value, $Res Function(DriveBookmark) _then) = _$DriveBookmarkCopyWithImpl;
@useResult
$Res call({
 String id, String url, String title, String? notes, String? folderId, String? faviconBase64, List<String> tagIds, String createdAt, String updatedAt
});




}
/// @nodoc
class _$DriveBookmarkCopyWithImpl<$Res>
    implements $DriveBookmarkCopyWith<$Res> {
  _$DriveBookmarkCopyWithImpl(this._self, this._then);

  final DriveBookmark _self;
  final $Res Function(DriveBookmark) _then;

/// Create a copy of DriveBookmark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? url = null,Object? title = null,Object? notes = freezed,Object? folderId = freezed,Object? faviconBase64 = freezed,Object? tagIds = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,folderId: freezed == folderId ? _self.folderId : folderId // ignore: cast_nullable_to_non_nullable
as String?,faviconBase64: freezed == faviconBase64 ? _self.faviconBase64 : faviconBase64 // ignore: cast_nullable_to_non_nullable
as String?,tagIds: null == tagIds ? _self.tagIds : tagIds // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DriveBookmark].
extension DriveBookmarkPatterns on DriveBookmark {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DriveBookmark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DriveBookmark() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DriveBookmark value)  $default,){
final _that = this;
switch (_that) {
case _DriveBookmark():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DriveBookmark value)?  $default,){
final _that = this;
switch (_that) {
case _DriveBookmark() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String url,  String title,  String? notes,  String? folderId,  String? faviconBase64,  List<String> tagIds,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DriveBookmark() when $default != null:
return $default(_that.id,_that.url,_that.title,_that.notes,_that.folderId,_that.faviconBase64,_that.tagIds,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String url,  String title,  String? notes,  String? folderId,  String? faviconBase64,  List<String> tagIds,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _DriveBookmark():
return $default(_that.id,_that.url,_that.title,_that.notes,_that.folderId,_that.faviconBase64,_that.tagIds,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String url,  String title,  String? notes,  String? folderId,  String? faviconBase64,  List<String> tagIds,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _DriveBookmark() when $default != null:
return $default(_that.id,_that.url,_that.title,_that.notes,_that.folderId,_that.faviconBase64,_that.tagIds,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DriveBookmark implements DriveBookmark {
  const _DriveBookmark({required this.id, required this.url, required this.title, this.notes, this.folderId, this.faviconBase64, final  List<String> tagIds = const <String>[], required this.createdAt, required this.updatedAt}): _tagIds = tagIds;
  factory _DriveBookmark.fromJson(Map<String, dynamic> json) => _$DriveBookmarkFromJson(json);

@override final  String id;
@override final  String url;
@override final  String title;
@override final  String? notes;
@override final  String? folderId;
@override final  String? faviconBase64;
 final  List<String> _tagIds;
@override@JsonKey() List<String> get tagIds {
  if (_tagIds is EqualUnmodifiableListView) return _tagIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tagIds);
}

@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of DriveBookmark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DriveBookmarkCopyWith<_DriveBookmark> get copyWith => __$DriveBookmarkCopyWithImpl<_DriveBookmark>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DriveBookmarkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DriveBookmark&&(identical(other.id, id) || other.id == id)&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.folderId, folderId) || other.folderId == folderId)&&(identical(other.faviconBase64, faviconBase64) || other.faviconBase64 == faviconBase64)&&const DeepCollectionEquality().equals(other._tagIds, _tagIds)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,url,title,notes,folderId,faviconBase64,const DeepCollectionEquality().hash(_tagIds),createdAt,updatedAt);

@override
String toString() {
  return 'DriveBookmark(id: $id, url: $url, title: $title, notes: $notes, folderId: $folderId, faviconBase64: $faviconBase64, tagIds: $tagIds, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$DriveBookmarkCopyWith<$Res> implements $DriveBookmarkCopyWith<$Res> {
  factory _$DriveBookmarkCopyWith(_DriveBookmark value, $Res Function(_DriveBookmark) _then) = __$DriveBookmarkCopyWithImpl;
@override @useResult
$Res call({
 String id, String url, String title, String? notes, String? folderId, String? faviconBase64, List<String> tagIds, String createdAt, String updatedAt
});




}
/// @nodoc
class __$DriveBookmarkCopyWithImpl<$Res>
    implements _$DriveBookmarkCopyWith<$Res> {
  __$DriveBookmarkCopyWithImpl(this._self, this._then);

  final _DriveBookmark _self;
  final $Res Function(_DriveBookmark) _then;

/// Create a copy of DriveBookmark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? url = null,Object? title = null,Object? notes = freezed,Object? folderId = freezed,Object? faviconBase64 = freezed,Object? tagIds = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_DriveBookmark(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,folderId: freezed == folderId ? _self.folderId : folderId // ignore: cast_nullable_to_non_nullable
as String?,faviconBase64: freezed == faviconBase64 ? _self.faviconBase64 : faviconBase64 // ignore: cast_nullable_to_non_nullable
as String?,tagIds: null == tagIds ? _self._tagIds : tagIds // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
