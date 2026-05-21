// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'drive_bookmarks_file.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DriveBookmarksFile {

 int get version; String get lastModified; List<DriveBookmark> get bookmarks; List<DriveFolder> get folders; List<DriveTag> get tags;
/// Create a copy of DriveBookmarksFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DriveBookmarksFileCopyWith<DriveBookmarksFile> get copyWith => _$DriveBookmarksFileCopyWithImpl<DriveBookmarksFile>(this as DriveBookmarksFile, _$identity);

  /// Serializes this DriveBookmarksFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveBookmarksFile&&(identical(other.version, version) || other.version == version)&&(identical(other.lastModified, lastModified) || other.lastModified == lastModified)&&const DeepCollectionEquality().equals(other.bookmarks, bookmarks)&&const DeepCollectionEquality().equals(other.folders, folders)&&const DeepCollectionEquality().equals(other.tags, tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,lastModified,const DeepCollectionEquality().hash(bookmarks),const DeepCollectionEquality().hash(folders),const DeepCollectionEquality().hash(tags));

@override
String toString() {
  return 'DriveBookmarksFile(version: $version, lastModified: $lastModified, bookmarks: $bookmarks, folders: $folders, tags: $tags)';
}


}

/// @nodoc
abstract mixin class $DriveBookmarksFileCopyWith<$Res>  {
  factory $DriveBookmarksFileCopyWith(DriveBookmarksFile value, $Res Function(DriveBookmarksFile) _then) = _$DriveBookmarksFileCopyWithImpl;
@useResult
$Res call({
 int version, String lastModified, List<DriveBookmark> bookmarks, List<DriveFolder> folders, List<DriveTag> tags
});




}
/// @nodoc
class _$DriveBookmarksFileCopyWithImpl<$Res>
    implements $DriveBookmarksFileCopyWith<$Res> {
  _$DriveBookmarksFileCopyWithImpl(this._self, this._then);

  final DriveBookmarksFile _self;
  final $Res Function(DriveBookmarksFile) _then;

/// Create a copy of DriveBookmarksFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? lastModified = null,Object? bookmarks = null,Object? folders = null,Object? tags = null,}) {
  return _then(_self.copyWith(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,lastModified: null == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as String,bookmarks: null == bookmarks ? _self.bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<DriveBookmark>,folders: null == folders ? _self.folders : folders // ignore: cast_nullable_to_non_nullable
as List<DriveFolder>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<DriveTag>,
  ));
}

}


/// Adds pattern-matching-related methods to [DriveBookmarksFile].
extension DriveBookmarksFilePatterns on DriveBookmarksFile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DriveBookmarksFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DriveBookmarksFile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DriveBookmarksFile value)  $default,){
final _that = this;
switch (_that) {
case _DriveBookmarksFile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DriveBookmarksFile value)?  $default,){
final _that = this;
switch (_that) {
case _DriveBookmarksFile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int version,  String lastModified,  List<DriveBookmark> bookmarks,  List<DriveFolder> folders,  List<DriveTag> tags)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DriveBookmarksFile() when $default != null:
return $default(_that.version,_that.lastModified,_that.bookmarks,_that.folders,_that.tags);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int version,  String lastModified,  List<DriveBookmark> bookmarks,  List<DriveFolder> folders,  List<DriveTag> tags)  $default,) {final _that = this;
switch (_that) {
case _DriveBookmarksFile():
return $default(_that.version,_that.lastModified,_that.bookmarks,_that.folders,_that.tags);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int version,  String lastModified,  List<DriveBookmark> bookmarks,  List<DriveFolder> folders,  List<DriveTag> tags)?  $default,) {final _that = this;
switch (_that) {
case _DriveBookmarksFile() when $default != null:
return $default(_that.version,_that.lastModified,_that.bookmarks,_that.folders,_that.tags);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DriveBookmarksFile implements DriveBookmarksFile {
  const _DriveBookmarksFile({required this.version, required this.lastModified, final  List<DriveBookmark> bookmarks = const <DriveBookmark>[], final  List<DriveFolder> folders = const <DriveFolder>[], final  List<DriveTag> tags = const <DriveTag>[]}): _bookmarks = bookmarks,_folders = folders,_tags = tags;
  factory _DriveBookmarksFile.fromJson(Map<String, dynamic> json) => _$DriveBookmarksFileFromJson(json);

@override final  int version;
@override final  String lastModified;
 final  List<DriveBookmark> _bookmarks;
@override@JsonKey() List<DriveBookmark> get bookmarks {
  if (_bookmarks is EqualUnmodifiableListView) return _bookmarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookmarks);
}

 final  List<DriveFolder> _folders;
@override@JsonKey() List<DriveFolder> get folders {
  if (_folders is EqualUnmodifiableListView) return _folders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_folders);
}

 final  List<DriveTag> _tags;
@override@JsonKey() List<DriveTag> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}


/// Create a copy of DriveBookmarksFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DriveBookmarksFileCopyWith<_DriveBookmarksFile> get copyWith => __$DriveBookmarksFileCopyWithImpl<_DriveBookmarksFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DriveBookmarksFileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DriveBookmarksFile&&(identical(other.version, version) || other.version == version)&&(identical(other.lastModified, lastModified) || other.lastModified == lastModified)&&const DeepCollectionEquality().equals(other._bookmarks, _bookmarks)&&const DeepCollectionEquality().equals(other._folders, _folders)&&const DeepCollectionEquality().equals(other._tags, _tags));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,lastModified,const DeepCollectionEquality().hash(_bookmarks),const DeepCollectionEquality().hash(_folders),const DeepCollectionEquality().hash(_tags));

@override
String toString() {
  return 'DriveBookmarksFile(version: $version, lastModified: $lastModified, bookmarks: $bookmarks, folders: $folders, tags: $tags)';
}


}

/// @nodoc
abstract mixin class _$DriveBookmarksFileCopyWith<$Res> implements $DriveBookmarksFileCopyWith<$Res> {
  factory _$DriveBookmarksFileCopyWith(_DriveBookmarksFile value, $Res Function(_DriveBookmarksFile) _then) = __$DriveBookmarksFileCopyWithImpl;
@override @useResult
$Res call({
 int version, String lastModified, List<DriveBookmark> bookmarks, List<DriveFolder> folders, List<DriveTag> tags
});




}
/// @nodoc
class __$DriveBookmarksFileCopyWithImpl<$Res>
    implements _$DriveBookmarksFileCopyWith<$Res> {
  __$DriveBookmarksFileCopyWithImpl(this._self, this._then);

  final _DriveBookmarksFile _self;
  final $Res Function(_DriveBookmarksFile) _then;

/// Create a copy of DriveBookmarksFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? lastModified = null,Object? bookmarks = null,Object? folders = null,Object? tags = null,}) {
  return _then(_DriveBookmarksFile(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,lastModified: null == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as String,bookmarks: null == bookmarks ? _self._bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<DriveBookmark>,folders: null == folders ? _self._folders : folders // ignore: cast_nullable_to_non_nullable
as List<DriveFolder>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<DriveTag>,
  ));
}


}

// dart format on
