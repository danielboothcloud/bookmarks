// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'merge_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MergePlan {

 List<DriveBookmark> get bookmarksToUpsert; List<String> get bookmarksToDelete; List<DriveFolder> get foldersToUpsert; List<String> get foldersToDelete; List<DriveTag> get tagsToUpsert; List<String> get tagsToDelete; Map<String, List<String>> get bookmarkTagLinksToReplace;
/// Create a copy of MergePlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MergePlanCopyWith<MergePlan> get copyWith => _$MergePlanCopyWithImpl<MergePlan>(this as MergePlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MergePlan&&const DeepCollectionEquality().equals(other.bookmarksToUpsert, bookmarksToUpsert)&&const DeepCollectionEquality().equals(other.bookmarksToDelete, bookmarksToDelete)&&const DeepCollectionEquality().equals(other.foldersToUpsert, foldersToUpsert)&&const DeepCollectionEquality().equals(other.foldersToDelete, foldersToDelete)&&const DeepCollectionEquality().equals(other.tagsToUpsert, tagsToUpsert)&&const DeepCollectionEquality().equals(other.tagsToDelete, tagsToDelete)&&const DeepCollectionEquality().equals(other.bookmarkTagLinksToReplace, bookmarkTagLinksToReplace));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bookmarksToUpsert),const DeepCollectionEquality().hash(bookmarksToDelete),const DeepCollectionEquality().hash(foldersToUpsert),const DeepCollectionEquality().hash(foldersToDelete),const DeepCollectionEquality().hash(tagsToUpsert),const DeepCollectionEquality().hash(tagsToDelete),const DeepCollectionEquality().hash(bookmarkTagLinksToReplace));

@override
String toString() {
  return 'MergePlan(bookmarksToUpsert: $bookmarksToUpsert, bookmarksToDelete: $bookmarksToDelete, foldersToUpsert: $foldersToUpsert, foldersToDelete: $foldersToDelete, tagsToUpsert: $tagsToUpsert, tagsToDelete: $tagsToDelete, bookmarkTagLinksToReplace: $bookmarkTagLinksToReplace)';
}


}

/// @nodoc
abstract mixin class $MergePlanCopyWith<$Res>  {
  factory $MergePlanCopyWith(MergePlan value, $Res Function(MergePlan) _then) = _$MergePlanCopyWithImpl;
@useResult
$Res call({
 List<DriveBookmark> bookmarksToUpsert, List<String> bookmarksToDelete, List<DriveFolder> foldersToUpsert, List<String> foldersToDelete, List<DriveTag> tagsToUpsert, List<String> tagsToDelete, Map<String, List<String>> bookmarkTagLinksToReplace
});




}
/// @nodoc
class _$MergePlanCopyWithImpl<$Res>
    implements $MergePlanCopyWith<$Res> {
  _$MergePlanCopyWithImpl(this._self, this._then);

  final MergePlan _self;
  final $Res Function(MergePlan) _then;

/// Create a copy of MergePlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bookmarksToUpsert = null,Object? bookmarksToDelete = null,Object? foldersToUpsert = null,Object? foldersToDelete = null,Object? tagsToUpsert = null,Object? tagsToDelete = null,Object? bookmarkTagLinksToReplace = null,}) {
  return _then(_self.copyWith(
bookmarksToUpsert: null == bookmarksToUpsert ? _self.bookmarksToUpsert : bookmarksToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveBookmark>,bookmarksToDelete: null == bookmarksToDelete ? _self.bookmarksToDelete : bookmarksToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,foldersToUpsert: null == foldersToUpsert ? _self.foldersToUpsert : foldersToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveFolder>,foldersToDelete: null == foldersToDelete ? _self.foldersToDelete : foldersToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,tagsToUpsert: null == tagsToUpsert ? _self.tagsToUpsert : tagsToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveTag>,tagsToDelete: null == tagsToDelete ? _self.tagsToDelete : tagsToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,bookmarkTagLinksToReplace: null == bookmarkTagLinksToReplace ? _self.bookmarkTagLinksToReplace : bookmarkTagLinksToReplace // ignore: cast_nullable_to_non_nullable
as Map<String, List<String>>,
  ));
}

}


/// Adds pattern-matching-related methods to [MergePlan].
extension MergePlanPatterns on MergePlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MergePlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MergePlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MergePlan value)  $default,){
final _that = this;
switch (_that) {
case _MergePlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MergePlan value)?  $default,){
final _that = this;
switch (_that) {
case _MergePlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<DriveBookmark> bookmarksToUpsert,  List<String> bookmarksToDelete,  List<DriveFolder> foldersToUpsert,  List<String> foldersToDelete,  List<DriveTag> tagsToUpsert,  List<String> tagsToDelete,  Map<String, List<String>> bookmarkTagLinksToReplace)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MergePlan() when $default != null:
return $default(_that.bookmarksToUpsert,_that.bookmarksToDelete,_that.foldersToUpsert,_that.foldersToDelete,_that.tagsToUpsert,_that.tagsToDelete,_that.bookmarkTagLinksToReplace);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<DriveBookmark> bookmarksToUpsert,  List<String> bookmarksToDelete,  List<DriveFolder> foldersToUpsert,  List<String> foldersToDelete,  List<DriveTag> tagsToUpsert,  List<String> tagsToDelete,  Map<String, List<String>> bookmarkTagLinksToReplace)  $default,) {final _that = this;
switch (_that) {
case _MergePlan():
return $default(_that.bookmarksToUpsert,_that.bookmarksToDelete,_that.foldersToUpsert,_that.foldersToDelete,_that.tagsToUpsert,_that.tagsToDelete,_that.bookmarkTagLinksToReplace);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<DriveBookmark> bookmarksToUpsert,  List<String> bookmarksToDelete,  List<DriveFolder> foldersToUpsert,  List<String> foldersToDelete,  List<DriveTag> tagsToUpsert,  List<String> tagsToDelete,  Map<String, List<String>> bookmarkTagLinksToReplace)?  $default,) {final _that = this;
switch (_that) {
case _MergePlan() when $default != null:
return $default(_that.bookmarksToUpsert,_that.bookmarksToDelete,_that.foldersToUpsert,_that.foldersToDelete,_that.tagsToUpsert,_that.tagsToDelete,_that.bookmarkTagLinksToReplace);case _:
  return null;

}
}

}

/// @nodoc


class _MergePlan implements MergePlan {
  const _MergePlan({required final  List<DriveBookmark> bookmarksToUpsert, required final  List<String> bookmarksToDelete, required final  List<DriveFolder> foldersToUpsert, required final  List<String> foldersToDelete, required final  List<DriveTag> tagsToUpsert, required final  List<String> tagsToDelete, required final  Map<String, List<String>> bookmarkTagLinksToReplace}): _bookmarksToUpsert = bookmarksToUpsert,_bookmarksToDelete = bookmarksToDelete,_foldersToUpsert = foldersToUpsert,_foldersToDelete = foldersToDelete,_tagsToUpsert = tagsToUpsert,_tagsToDelete = tagsToDelete,_bookmarkTagLinksToReplace = bookmarkTagLinksToReplace;
  

 final  List<DriveBookmark> _bookmarksToUpsert;
@override List<DriveBookmark> get bookmarksToUpsert {
  if (_bookmarksToUpsert is EqualUnmodifiableListView) return _bookmarksToUpsert;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookmarksToUpsert);
}

 final  List<String> _bookmarksToDelete;
@override List<String> get bookmarksToDelete {
  if (_bookmarksToDelete is EqualUnmodifiableListView) return _bookmarksToDelete;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_bookmarksToDelete);
}

 final  List<DriveFolder> _foldersToUpsert;
@override List<DriveFolder> get foldersToUpsert {
  if (_foldersToUpsert is EqualUnmodifiableListView) return _foldersToUpsert;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_foldersToUpsert);
}

 final  List<String> _foldersToDelete;
@override List<String> get foldersToDelete {
  if (_foldersToDelete is EqualUnmodifiableListView) return _foldersToDelete;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_foldersToDelete);
}

 final  List<DriveTag> _tagsToUpsert;
@override List<DriveTag> get tagsToUpsert {
  if (_tagsToUpsert is EqualUnmodifiableListView) return _tagsToUpsert;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tagsToUpsert);
}

 final  List<String> _tagsToDelete;
@override List<String> get tagsToDelete {
  if (_tagsToDelete is EqualUnmodifiableListView) return _tagsToDelete;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tagsToDelete);
}

 final  Map<String, List<String>> _bookmarkTagLinksToReplace;
@override Map<String, List<String>> get bookmarkTagLinksToReplace {
  if (_bookmarkTagLinksToReplace is EqualUnmodifiableMapView) return _bookmarkTagLinksToReplace;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_bookmarkTagLinksToReplace);
}


/// Create a copy of MergePlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MergePlanCopyWith<_MergePlan> get copyWith => __$MergePlanCopyWithImpl<_MergePlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MergePlan&&const DeepCollectionEquality().equals(other._bookmarksToUpsert, _bookmarksToUpsert)&&const DeepCollectionEquality().equals(other._bookmarksToDelete, _bookmarksToDelete)&&const DeepCollectionEquality().equals(other._foldersToUpsert, _foldersToUpsert)&&const DeepCollectionEquality().equals(other._foldersToDelete, _foldersToDelete)&&const DeepCollectionEquality().equals(other._tagsToUpsert, _tagsToUpsert)&&const DeepCollectionEquality().equals(other._tagsToDelete, _tagsToDelete)&&const DeepCollectionEquality().equals(other._bookmarkTagLinksToReplace, _bookmarkTagLinksToReplace));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_bookmarksToUpsert),const DeepCollectionEquality().hash(_bookmarksToDelete),const DeepCollectionEquality().hash(_foldersToUpsert),const DeepCollectionEquality().hash(_foldersToDelete),const DeepCollectionEquality().hash(_tagsToUpsert),const DeepCollectionEquality().hash(_tagsToDelete),const DeepCollectionEquality().hash(_bookmarkTagLinksToReplace));

@override
String toString() {
  return 'MergePlan(bookmarksToUpsert: $bookmarksToUpsert, bookmarksToDelete: $bookmarksToDelete, foldersToUpsert: $foldersToUpsert, foldersToDelete: $foldersToDelete, tagsToUpsert: $tagsToUpsert, tagsToDelete: $tagsToDelete, bookmarkTagLinksToReplace: $bookmarkTagLinksToReplace)';
}


}

/// @nodoc
abstract mixin class _$MergePlanCopyWith<$Res> implements $MergePlanCopyWith<$Res> {
  factory _$MergePlanCopyWith(_MergePlan value, $Res Function(_MergePlan) _then) = __$MergePlanCopyWithImpl;
@override @useResult
$Res call({
 List<DriveBookmark> bookmarksToUpsert, List<String> bookmarksToDelete, List<DriveFolder> foldersToUpsert, List<String> foldersToDelete, List<DriveTag> tagsToUpsert, List<String> tagsToDelete, Map<String, List<String>> bookmarkTagLinksToReplace
});




}
/// @nodoc
class __$MergePlanCopyWithImpl<$Res>
    implements _$MergePlanCopyWith<$Res> {
  __$MergePlanCopyWithImpl(this._self, this._then);

  final _MergePlan _self;
  final $Res Function(_MergePlan) _then;

/// Create a copy of MergePlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bookmarksToUpsert = null,Object? bookmarksToDelete = null,Object? foldersToUpsert = null,Object? foldersToDelete = null,Object? tagsToUpsert = null,Object? tagsToDelete = null,Object? bookmarkTagLinksToReplace = null,}) {
  return _then(_MergePlan(
bookmarksToUpsert: null == bookmarksToUpsert ? _self._bookmarksToUpsert : bookmarksToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveBookmark>,bookmarksToDelete: null == bookmarksToDelete ? _self._bookmarksToDelete : bookmarksToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,foldersToUpsert: null == foldersToUpsert ? _self._foldersToUpsert : foldersToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveFolder>,foldersToDelete: null == foldersToDelete ? _self._foldersToDelete : foldersToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,tagsToUpsert: null == tagsToUpsert ? _self._tagsToUpsert : tagsToUpsert // ignore: cast_nullable_to_non_nullable
as List<DriveTag>,tagsToDelete: null == tagsToDelete ? _self._tagsToDelete : tagsToDelete // ignore: cast_nullable_to_non_nullable
as List<String>,bookmarkTagLinksToReplace: null == bookmarkTagLinksToReplace ? _self._bookmarkTagLinksToReplace : bookmarkTagLinksToReplace // ignore: cast_nullable_to_non_nullable
as Map<String, List<String>>,
  ));
}


}

// dart format on
