// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'parsed_bookmarks_tree.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParsedBookmark {

 String get url; String get title;
/// Create a copy of ParsedBookmark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParsedBookmarkCopyWith<ParsedBookmark> get copyWith => _$ParsedBookmarkCopyWithImpl<ParsedBookmark>(this as ParsedBookmark, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParsedBookmark&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,url,title);

@override
String toString() {
  return 'ParsedBookmark(url: $url, title: $title)';
}


}

/// @nodoc
abstract mixin class $ParsedBookmarkCopyWith<$Res>  {
  factory $ParsedBookmarkCopyWith(ParsedBookmark value, $Res Function(ParsedBookmark) _then) = _$ParsedBookmarkCopyWithImpl;
@useResult
$Res call({
 String url, String title
});




}
/// @nodoc
class _$ParsedBookmarkCopyWithImpl<$Res>
    implements $ParsedBookmarkCopyWith<$Res> {
  _$ParsedBookmarkCopyWithImpl(this._self, this._then);

  final ParsedBookmark _self;
  final $Res Function(ParsedBookmark) _then;

/// Create a copy of ParsedBookmark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? title = null,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ParsedBookmark].
extension ParsedBookmarkPatterns on ParsedBookmark {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParsedBookmark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParsedBookmark() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParsedBookmark value)  $default,){
final _that = this;
switch (_that) {
case _ParsedBookmark():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParsedBookmark value)?  $default,){
final _that = this;
switch (_that) {
case _ParsedBookmark() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String title)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParsedBookmark() when $default != null:
return $default(_that.url,_that.title);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String title)  $default,) {final _that = this;
switch (_that) {
case _ParsedBookmark():
return $default(_that.url,_that.title);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String title)?  $default,) {final _that = this;
switch (_that) {
case _ParsedBookmark() when $default != null:
return $default(_that.url,_that.title);case _:
  return null;

}
}

}

/// @nodoc


class _ParsedBookmark implements ParsedBookmark {
  const _ParsedBookmark({required this.url, required this.title});
  

@override final  String url;
@override final  String title;

/// Create a copy of ParsedBookmark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParsedBookmarkCopyWith<_ParsedBookmark> get copyWith => __$ParsedBookmarkCopyWithImpl<_ParsedBookmark>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParsedBookmark&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,url,title);

@override
String toString() {
  return 'ParsedBookmark(url: $url, title: $title)';
}


}

/// @nodoc
abstract mixin class _$ParsedBookmarkCopyWith<$Res> implements $ParsedBookmarkCopyWith<$Res> {
  factory _$ParsedBookmarkCopyWith(_ParsedBookmark value, $Res Function(_ParsedBookmark) _then) = __$ParsedBookmarkCopyWithImpl;
@override @useResult
$Res call({
 String url, String title
});




}
/// @nodoc
class __$ParsedBookmarkCopyWithImpl<$Res>
    implements _$ParsedBookmarkCopyWith<$Res> {
  __$ParsedBookmarkCopyWithImpl(this._self, this._then);

  final _ParsedBookmark _self;
  final $Res Function(_ParsedBookmark) _then;

/// Create a copy of ParsedBookmark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? title = null,}) {
  return _then(_ParsedBookmark(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ParsedFolderNode {

 String get name; List<ParsedFolderNode> get subfolders; List<ParsedBookmark> get bookmarks;
/// Create a copy of ParsedFolderNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParsedFolderNodeCopyWith<ParsedFolderNode> get copyWith => _$ParsedFolderNodeCopyWithImpl<ParsedFolderNode>(this as ParsedFolderNode, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParsedFolderNode&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.subfolders, subfolders)&&const DeepCollectionEquality().equals(other.bookmarks, bookmarks));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(subfolders),const DeepCollectionEquality().hash(bookmarks));

@override
String toString() {
  return 'ParsedFolderNode(name: $name, subfolders: $subfolders, bookmarks: $bookmarks)';
}


}

/// @nodoc
abstract mixin class $ParsedFolderNodeCopyWith<$Res>  {
  factory $ParsedFolderNodeCopyWith(ParsedFolderNode value, $Res Function(ParsedFolderNode) _then) = _$ParsedFolderNodeCopyWithImpl;
@useResult
$Res call({
 String name, List<ParsedFolderNode> subfolders, List<ParsedBookmark> bookmarks
});




}
/// @nodoc
class _$ParsedFolderNodeCopyWithImpl<$Res>
    implements $ParsedFolderNodeCopyWith<$Res> {
  _$ParsedFolderNodeCopyWithImpl(this._self, this._then);

  final ParsedFolderNode _self;
  final $Res Function(ParsedFolderNode) _then;

/// Create a copy of ParsedFolderNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? subfolders = null,Object? bookmarks = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,subfolders: null == subfolders ? _self.subfolders : subfolders // ignore: cast_nullable_to_non_nullable
as List<ParsedFolderNode>,bookmarks: null == bookmarks ? _self.bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<ParsedBookmark>,
  ));
}

}


/// Adds pattern-matching-related methods to [ParsedFolderNode].
extension ParsedFolderNodePatterns on ParsedFolderNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParsedFolderNode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParsedFolderNode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParsedFolderNode value)  $default,){
final _that = this;
switch (_that) {
case _ParsedFolderNode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParsedFolderNode value)?  $default,){
final _that = this;
switch (_that) {
case _ParsedFolderNode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  List<ParsedFolderNode> subfolders,  List<ParsedBookmark> bookmarks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParsedFolderNode() when $default != null:
return $default(_that.name,_that.subfolders,_that.bookmarks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  List<ParsedFolderNode> subfolders,  List<ParsedBookmark> bookmarks)  $default,) {final _that = this;
switch (_that) {
case _ParsedFolderNode():
return $default(_that.name,_that.subfolders,_that.bookmarks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  List<ParsedFolderNode> subfolders,  List<ParsedBookmark> bookmarks)?  $default,) {final _that = this;
switch (_that) {
case _ParsedFolderNode() when $default != null:
return $default(_that.name,_that.subfolders,_that.bookmarks);case _:
  return null;

}
}

}

/// @nodoc


class _ParsedFolderNode implements ParsedFolderNode {
  const _ParsedFolderNode({required this.name, required final  List<ParsedFolderNode> subfolders, required final  List<ParsedBookmark> bookmarks}): _subfolders = subfolders,_bookmarks = bookmarks;
  

@override final  String name;
 final  List<ParsedFolderNode> _subfolders;
@override List<ParsedFolderNode> get subfolders {
  if (_subfolders is EqualUnmodifiableListView) return _subfolders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_subfolders);
}

 final  List<ParsedBookmark> _bookmarks;
@override List<ParsedBookmark> get bookmarks {
  if (_bookmarks is EqualUnmodifiableListView) return _bookmarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookmarks);
}


/// Create a copy of ParsedFolderNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParsedFolderNodeCopyWith<_ParsedFolderNode> get copyWith => __$ParsedFolderNodeCopyWithImpl<_ParsedFolderNode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParsedFolderNode&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._subfolders, _subfolders)&&const DeepCollectionEquality().equals(other._bookmarks, _bookmarks));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_subfolders),const DeepCollectionEquality().hash(_bookmarks));

@override
String toString() {
  return 'ParsedFolderNode(name: $name, subfolders: $subfolders, bookmarks: $bookmarks)';
}


}

/// @nodoc
abstract mixin class _$ParsedFolderNodeCopyWith<$Res> implements $ParsedFolderNodeCopyWith<$Res> {
  factory _$ParsedFolderNodeCopyWith(_ParsedFolderNode value, $Res Function(_ParsedFolderNode) _then) = __$ParsedFolderNodeCopyWithImpl;
@override @useResult
$Res call({
 String name, List<ParsedFolderNode> subfolders, List<ParsedBookmark> bookmarks
});




}
/// @nodoc
class __$ParsedFolderNodeCopyWithImpl<$Res>
    implements _$ParsedFolderNodeCopyWith<$Res> {
  __$ParsedFolderNodeCopyWithImpl(this._self, this._then);

  final _ParsedFolderNode _self;
  final $Res Function(_ParsedFolderNode) _then;

/// Create a copy of ParsedFolderNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? subfolders = null,Object? bookmarks = null,}) {
  return _then(_ParsedFolderNode(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,subfolders: null == subfolders ? _self._subfolders : subfolders // ignore: cast_nullable_to_non_nullable
as List<ParsedFolderNode>,bookmarks: null == bookmarks ? _self._bookmarks : bookmarks // ignore: cast_nullable_to_non_nullable
as List<ParsedBookmark>,
  ));
}


}

/// @nodoc
mixin _$ParsedBookmarksTree {

 List<ParsedFolderNode> get rootFolders; List<ParsedBookmark> get rootBookmarks; int get unparseableItems;
/// Create a copy of ParsedBookmarksTree
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParsedBookmarksTreeCopyWith<ParsedBookmarksTree> get copyWith => _$ParsedBookmarksTreeCopyWithImpl<ParsedBookmarksTree>(this as ParsedBookmarksTree, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParsedBookmarksTree&&const DeepCollectionEquality().equals(other.rootFolders, rootFolders)&&const DeepCollectionEquality().equals(other.rootBookmarks, rootBookmarks)&&(identical(other.unparseableItems, unparseableItems) || other.unparseableItems == unparseableItems));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(rootFolders),const DeepCollectionEquality().hash(rootBookmarks),unparseableItems);

@override
String toString() {
  return 'ParsedBookmarksTree(rootFolders: $rootFolders, rootBookmarks: $rootBookmarks, unparseableItems: $unparseableItems)';
}


}

/// @nodoc
abstract mixin class $ParsedBookmarksTreeCopyWith<$Res>  {
  factory $ParsedBookmarksTreeCopyWith(ParsedBookmarksTree value, $Res Function(ParsedBookmarksTree) _then) = _$ParsedBookmarksTreeCopyWithImpl;
@useResult
$Res call({
 List<ParsedFolderNode> rootFolders, List<ParsedBookmark> rootBookmarks, int unparseableItems
});




}
/// @nodoc
class _$ParsedBookmarksTreeCopyWithImpl<$Res>
    implements $ParsedBookmarksTreeCopyWith<$Res> {
  _$ParsedBookmarksTreeCopyWithImpl(this._self, this._then);

  final ParsedBookmarksTree _self;
  final $Res Function(ParsedBookmarksTree) _then;

/// Create a copy of ParsedBookmarksTree
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rootFolders = null,Object? rootBookmarks = null,Object? unparseableItems = null,}) {
  return _then(_self.copyWith(
rootFolders: null == rootFolders ? _self.rootFolders : rootFolders // ignore: cast_nullable_to_non_nullable
as List<ParsedFolderNode>,rootBookmarks: null == rootBookmarks ? _self.rootBookmarks : rootBookmarks // ignore: cast_nullable_to_non_nullable
as List<ParsedBookmark>,unparseableItems: null == unparseableItems ? _self.unparseableItems : unparseableItems // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ParsedBookmarksTree].
extension ParsedBookmarksTreePatterns on ParsedBookmarksTree {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParsedBookmarksTree value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParsedBookmarksTree() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParsedBookmarksTree value)  $default,){
final _that = this;
switch (_that) {
case _ParsedBookmarksTree():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParsedBookmarksTree value)?  $default,){
final _that = this;
switch (_that) {
case _ParsedBookmarksTree() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ParsedFolderNode> rootFolders,  List<ParsedBookmark> rootBookmarks,  int unparseableItems)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParsedBookmarksTree() when $default != null:
return $default(_that.rootFolders,_that.rootBookmarks,_that.unparseableItems);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ParsedFolderNode> rootFolders,  List<ParsedBookmark> rootBookmarks,  int unparseableItems)  $default,) {final _that = this;
switch (_that) {
case _ParsedBookmarksTree():
return $default(_that.rootFolders,_that.rootBookmarks,_that.unparseableItems);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ParsedFolderNode> rootFolders,  List<ParsedBookmark> rootBookmarks,  int unparseableItems)?  $default,) {final _that = this;
switch (_that) {
case _ParsedBookmarksTree() when $default != null:
return $default(_that.rootFolders,_that.rootBookmarks,_that.unparseableItems);case _:
  return null;

}
}

}

/// @nodoc


class _ParsedBookmarksTree implements ParsedBookmarksTree {
  const _ParsedBookmarksTree({required final  List<ParsedFolderNode> rootFolders, required final  List<ParsedBookmark> rootBookmarks, required this.unparseableItems}): _rootFolders = rootFolders,_rootBookmarks = rootBookmarks;
  

 final  List<ParsedFolderNode> _rootFolders;
@override List<ParsedFolderNode> get rootFolders {
  if (_rootFolders is EqualUnmodifiableListView) return _rootFolders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rootFolders);
}

 final  List<ParsedBookmark> _rootBookmarks;
@override List<ParsedBookmark> get rootBookmarks {
  if (_rootBookmarks is EqualUnmodifiableListView) return _rootBookmarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rootBookmarks);
}

@override final  int unparseableItems;

/// Create a copy of ParsedBookmarksTree
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParsedBookmarksTreeCopyWith<_ParsedBookmarksTree> get copyWith => __$ParsedBookmarksTreeCopyWithImpl<_ParsedBookmarksTree>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParsedBookmarksTree&&const DeepCollectionEquality().equals(other._rootFolders, _rootFolders)&&const DeepCollectionEquality().equals(other._rootBookmarks, _rootBookmarks)&&(identical(other.unparseableItems, unparseableItems) || other.unparseableItems == unparseableItems));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_rootFolders),const DeepCollectionEquality().hash(_rootBookmarks),unparseableItems);

@override
String toString() {
  return 'ParsedBookmarksTree(rootFolders: $rootFolders, rootBookmarks: $rootBookmarks, unparseableItems: $unparseableItems)';
}


}

/// @nodoc
abstract mixin class _$ParsedBookmarksTreeCopyWith<$Res> implements $ParsedBookmarksTreeCopyWith<$Res> {
  factory _$ParsedBookmarksTreeCopyWith(_ParsedBookmarksTree value, $Res Function(_ParsedBookmarksTree) _then) = __$ParsedBookmarksTreeCopyWithImpl;
@override @useResult
$Res call({
 List<ParsedFolderNode> rootFolders, List<ParsedBookmark> rootBookmarks, int unparseableItems
});




}
/// @nodoc
class __$ParsedBookmarksTreeCopyWithImpl<$Res>
    implements _$ParsedBookmarksTreeCopyWith<$Res> {
  __$ParsedBookmarksTreeCopyWithImpl(this._self, this._then);

  final _ParsedBookmarksTree _self;
  final $Res Function(_ParsedBookmarksTree) _then;

/// Create a copy of ParsedBookmarksTree
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rootFolders = null,Object? rootBookmarks = null,Object? unparseableItems = null,}) {
  return _then(_ParsedBookmarksTree(
rootFolders: null == rootFolders ? _self._rootFolders : rootFolders // ignore: cast_nullable_to_non_nullable
as List<ParsedFolderNode>,rootBookmarks: null == rootBookmarks ? _self._rootBookmarks : rootBookmarks // ignore: cast_nullable_to_non_nullable
as List<ParsedBookmark>,unparseableItems: null == unparseableItems ? _self.unparseableItems : unparseableItems // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
