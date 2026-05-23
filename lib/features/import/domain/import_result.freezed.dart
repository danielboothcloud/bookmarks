// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'import_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ImportResult {

 int get foldersCreated; int get bookmarksImported; int get itemsSkipped; Duration get elapsed;
/// Create a copy of ImportResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImportResultCopyWith<ImportResult> get copyWith => _$ImportResultCopyWithImpl<ImportResult>(this as ImportResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportResult&&(identical(other.foldersCreated, foldersCreated) || other.foldersCreated == foldersCreated)&&(identical(other.bookmarksImported, bookmarksImported) || other.bookmarksImported == bookmarksImported)&&(identical(other.itemsSkipped, itemsSkipped) || other.itemsSkipped == itemsSkipped)&&(identical(other.elapsed, elapsed) || other.elapsed == elapsed));
}


@override
int get hashCode => Object.hash(runtimeType,foldersCreated,bookmarksImported,itemsSkipped,elapsed);

@override
String toString() {
  return 'ImportResult(foldersCreated: $foldersCreated, bookmarksImported: $bookmarksImported, itemsSkipped: $itemsSkipped, elapsed: $elapsed)';
}


}

/// @nodoc
abstract mixin class $ImportResultCopyWith<$Res>  {
  factory $ImportResultCopyWith(ImportResult value, $Res Function(ImportResult) _then) = _$ImportResultCopyWithImpl;
@useResult
$Res call({
 int foldersCreated, int bookmarksImported, int itemsSkipped, Duration elapsed
});




}
/// @nodoc
class _$ImportResultCopyWithImpl<$Res>
    implements $ImportResultCopyWith<$Res> {
  _$ImportResultCopyWithImpl(this._self, this._then);

  final ImportResult _self;
  final $Res Function(ImportResult) _then;

/// Create a copy of ImportResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? foldersCreated = null,Object? bookmarksImported = null,Object? itemsSkipped = null,Object? elapsed = null,}) {
  return _then(_self.copyWith(
foldersCreated: null == foldersCreated ? _self.foldersCreated : foldersCreated // ignore: cast_nullable_to_non_nullable
as int,bookmarksImported: null == bookmarksImported ? _self.bookmarksImported : bookmarksImported // ignore: cast_nullable_to_non_nullable
as int,itemsSkipped: null == itemsSkipped ? _self.itemsSkipped : itemsSkipped // ignore: cast_nullable_to_non_nullable
as int,elapsed: null == elapsed ? _self.elapsed : elapsed // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

}


/// Adds pattern-matching-related methods to [ImportResult].
extension ImportResultPatterns on ImportResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ImportResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ImportResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ImportResult value)  $default,){
final _that = this;
switch (_that) {
case _ImportResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ImportResult value)?  $default,){
final _that = this;
switch (_that) {
case _ImportResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int foldersCreated,  int bookmarksImported,  int itemsSkipped,  Duration elapsed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ImportResult() when $default != null:
return $default(_that.foldersCreated,_that.bookmarksImported,_that.itemsSkipped,_that.elapsed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int foldersCreated,  int bookmarksImported,  int itemsSkipped,  Duration elapsed)  $default,) {final _that = this;
switch (_that) {
case _ImportResult():
return $default(_that.foldersCreated,_that.bookmarksImported,_that.itemsSkipped,_that.elapsed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int foldersCreated,  int bookmarksImported,  int itemsSkipped,  Duration elapsed)?  $default,) {final _that = this;
switch (_that) {
case _ImportResult() when $default != null:
return $default(_that.foldersCreated,_that.bookmarksImported,_that.itemsSkipped,_that.elapsed);case _:
  return null;

}
}

}

/// @nodoc


class _ImportResult implements ImportResult {
  const _ImportResult({required this.foldersCreated, required this.bookmarksImported, required this.itemsSkipped, required this.elapsed});
  

@override final  int foldersCreated;
@override final  int bookmarksImported;
@override final  int itemsSkipped;
@override final  Duration elapsed;

/// Create a copy of ImportResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ImportResultCopyWith<_ImportResult> get copyWith => __$ImportResultCopyWithImpl<_ImportResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ImportResult&&(identical(other.foldersCreated, foldersCreated) || other.foldersCreated == foldersCreated)&&(identical(other.bookmarksImported, bookmarksImported) || other.bookmarksImported == bookmarksImported)&&(identical(other.itemsSkipped, itemsSkipped) || other.itemsSkipped == itemsSkipped)&&(identical(other.elapsed, elapsed) || other.elapsed == elapsed));
}


@override
int get hashCode => Object.hash(runtimeType,foldersCreated,bookmarksImported,itemsSkipped,elapsed);

@override
String toString() {
  return 'ImportResult(foldersCreated: $foldersCreated, bookmarksImported: $bookmarksImported, itemsSkipped: $itemsSkipped, elapsed: $elapsed)';
}


}

/// @nodoc
abstract mixin class _$ImportResultCopyWith<$Res> implements $ImportResultCopyWith<$Res> {
  factory _$ImportResultCopyWith(_ImportResult value, $Res Function(_ImportResult) _then) = __$ImportResultCopyWithImpl;
@override @useResult
$Res call({
 int foldersCreated, int bookmarksImported, int itemsSkipped, Duration elapsed
});




}
/// @nodoc
class __$ImportResultCopyWithImpl<$Res>
    implements _$ImportResultCopyWith<$Res> {
  __$ImportResultCopyWithImpl(this._self, this._then);

  final _ImportResult _self;
  final $Res Function(_ImportResult) _then;

/// Create a copy of ImportResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? foldersCreated = null,Object? bookmarksImported = null,Object? itemsSkipped = null,Object? elapsed = null,}) {
  return _then(_ImportResult(
foldersCreated: null == foldersCreated ? _self.foldersCreated : foldersCreated // ignore: cast_nullable_to_non_nullable
as int,bookmarksImported: null == bookmarksImported ? _self.bookmarksImported : bookmarksImported // ignore: cast_nullable_to_non_nullable
as int,itemsSkipped: null == itemsSkipped ? _self.itemsSkipped : itemsSkipped // ignore: cast_nullable_to_non_nullable
as int,elapsed: null == elapsed ? _self.elapsed : elapsed // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

// dart format on
