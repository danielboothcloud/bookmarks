// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'local_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LocalSnapshot {

 List<BookmarkRow> get bookmarks; List<FolderRow> get folders; List<TagRow> get tags; Map<String, List<String>> get tagIdsByBookmark;
/// Create a copy of LocalSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalSnapshotCopyWith<LocalSnapshot> get copyWith => _$LocalSnapshotCopyWithImpl<LocalSnapshot>(this as LocalSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalSnapshot&&const DeepCollectionEquality().equals(other.bookmarks, bookmarks)&&const DeepCollectionEquality().equals(other.folders, folders)&&const DeepCollectionEquality().equals(other.tags, tags)&&const DeepCollectionEquality().equals(other.tagIdsByBookmark, tagIdsByBookmark));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bookmarks),const DeepCollectionEquality().hash(folders),const DeepCollectionEquality().hash(tags),const DeepCollectionEquality().hash(tagIdsByBookmark));

@override
String toString() {
  return 'LocalSnapshot(bookmarks: $bookmarks, folders: $folders, tags: $tags, tagIdsByBookmark: $tagIdsByBookmark)';
}


}

/// @nodoc
abstract mixin class $LocalSnapshotCopyWith<$Res>  {
  factory $LocalSnapshotCopyWith(LocalSnapshot value, $Res Function(LocalSnapshot) _then) = _$LocalSnapshotCopyWithImpl;
@useResult
$Res call({
 List<BookmarkRow> bookmarks, List<FolderRow> folders, List<TagRow> tags, Map<String, List<String>> tagIdsByBookmark
});




}
/// @nodoc
class _$LocalSnapshotCopyWithImpl<$Res>
    implements $LocalSnapshotCopyWith<$Res> {
  _$LocalSnapshotCopyWithImpl(this._self, this._then);

  final LocalSnapshot _self;
  final $Res Function(LocalSnapshot) _then;

/// Create a copy of LocalSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bookmarks = null,Object? folders = null,Object? tags = null,Object? tagIdsByBookmark = null,}) {
  return _then(_self.copyWith(
bookmarks: null == bookmarks ? _self.bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<BookmarkRow>,folders: null == folders ? _self.folders : folders // ignore: cast_nullable_to_non_nullable
as List<FolderRow>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<TagRow>,tagIdsByBookmark: null == tagIdsByBookmark ? _self.tagIdsByBookmark : tagIdsByBookmark // ignore: cast_nullable_to_non_nullable
as Map<String, List<String>>,
  ));
}

}


/// Adds pattern-matching-related methods to [LocalSnapshot].
extension LocalSnapshotPatterns on LocalSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocalSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocalSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocalSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _LocalSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocalSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _LocalSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<BookmarkRow> bookmarks,  List<FolderRow> folders,  List<TagRow> tags,  Map<String, List<String>> tagIdsByBookmark)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocalSnapshot() when $default != null:
return $default(_that.bookmarks,_that.folders,_that.tags,_that.tagIdsByBookmark);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<BookmarkRow> bookmarks,  List<FolderRow> folders,  List<TagRow> tags,  Map<String, List<String>> tagIdsByBookmark)  $default,) {final _that = this;
switch (_that) {
case _LocalSnapshot():
return $default(_that.bookmarks,_that.folders,_that.tags,_that.tagIdsByBookmark);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<BookmarkRow> bookmarks,  List<FolderRow> folders,  List<TagRow> tags,  Map<String, List<String>> tagIdsByBookmark)?  $default,) {final _that = this;
switch (_that) {
case _LocalSnapshot() when $default != null:
return $default(_that.bookmarks,_that.folders,_that.tags,_that.tagIdsByBookmark);case _:
  return null;

}
}

}

/// @nodoc


class _LocalSnapshot implements LocalSnapshot {
  const _LocalSnapshot({required final  List<BookmarkRow> bookmarks, required final  List<FolderRow> folders, required final  List<TagRow> tags, required final  Map<String, List<String>> tagIdsByBookmark}): _bookmarks = bookmarks,_folders = folders,_tags = tags,_tagIdsByBookmark = tagIdsByBookmark;
  

 final  List<BookmarkRow> _bookmarks;
@override List<BookmarkRow> get bookmarks {
  if (_bookmarks is EqualUnmodifiableListView) return _bookmarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookmarks);
}

 final  List<FolderRow> _folders;
@override List<FolderRow> get folders {
  if (_folders is EqualUnmodifiableListView) return _folders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_folders);
}

 final  List<TagRow> _tags;
@override List<TagRow> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

 final  Map<String, List<String>> _tagIdsByBookmark;
@override Map<String, List<String>> get tagIdsByBookmark {
  if (_tagIdsByBookmark is EqualUnmodifiableMapView) return _tagIdsByBookmark;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_tagIdsByBookmark);
}


/// Create a copy of LocalSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocalSnapshotCopyWith<_LocalSnapshot> get copyWith => __$LocalSnapshotCopyWithImpl<_LocalSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocalSnapshot&&const DeepCollectionEquality().equals(other._bookmarks, _bookmarks)&&const DeepCollectionEquality().equals(other._folders, _folders)&&const DeepCollectionEquality().equals(other._tags, _tags)&&const DeepCollectionEquality().equals(other._tagIdsByBookmark, _tagIdsByBookmark));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_bookmarks),const DeepCollectionEquality().hash(_folders),const DeepCollectionEquality().hash(_tags),const DeepCollectionEquality().hash(_tagIdsByBookmark));

@override
String toString() {
  return 'LocalSnapshot(bookmarks: $bookmarks, folders: $folders, tags: $tags, tagIdsByBookmark: $tagIdsByBookmark)';
}


}

/// @nodoc
abstract mixin class _$LocalSnapshotCopyWith<$Res> implements $LocalSnapshotCopyWith<$Res> {
  factory _$LocalSnapshotCopyWith(_LocalSnapshot value, $Res Function(_LocalSnapshot) _then) = __$LocalSnapshotCopyWithImpl;
@override @useResult
$Res call({
 List<BookmarkRow> bookmarks, List<FolderRow> folders, List<TagRow> tags, Map<String, List<String>> tagIdsByBookmark
});




}
/// @nodoc
class __$LocalSnapshotCopyWithImpl<$Res>
    implements _$LocalSnapshotCopyWith<$Res> {
  __$LocalSnapshotCopyWithImpl(this._self, this._then);

  final _LocalSnapshot _self;
  final $Res Function(_LocalSnapshot) _then;

/// Create a copy of LocalSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bookmarks = null,Object? folders = null,Object? tags = null,Object? tagIdsByBookmark = null,}) {
  return _then(_LocalSnapshot(
bookmarks: null == bookmarks ? _self._bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<BookmarkRow>,folders: null == folders ? _self._folders : folders // ignore: cast_nullable_to_non_nullable
as List<FolderRow>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<TagRow>,tagIdsByBookmark: null == tagIdsByBookmark ? _self._tagIdsByBookmark : tagIdsByBookmark // ignore: cast_nullable_to_non_nullable
as Map<String, List<String>>,
  ));
}


}

// dart format on
