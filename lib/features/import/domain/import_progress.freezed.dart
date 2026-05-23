// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'import_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ImportProgress {

 int get itemsWritten; int get totalItems;
/// Create a copy of ImportProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImportProgressCopyWith<ImportProgress> get copyWith => _$ImportProgressCopyWithImpl<ImportProgress>(this as ImportProgress, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportProgress&&(identical(other.itemsWritten, itemsWritten) || other.itemsWritten == itemsWritten)&&(identical(other.totalItems, totalItems) || other.totalItems == totalItems));
}


@override
int get hashCode => Object.hash(runtimeType,itemsWritten,totalItems);

@override
String toString() {
  return 'ImportProgress(itemsWritten: $itemsWritten, totalItems: $totalItems)';
}


}

/// @nodoc
abstract mixin class $ImportProgressCopyWith<$Res>  {
  factory $ImportProgressCopyWith(ImportProgress value, $Res Function(ImportProgress) _then) = _$ImportProgressCopyWithImpl;
@useResult
$Res call({
 int itemsWritten, int totalItems
});




}
/// @nodoc
class _$ImportProgressCopyWithImpl<$Res>
    implements $ImportProgressCopyWith<$Res> {
  _$ImportProgressCopyWithImpl(this._self, this._then);

  final ImportProgress _self;
  final $Res Function(ImportProgress) _then;

/// Create a copy of ImportProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? itemsWritten = null,Object? totalItems = null,}) {
  return _then(_self.copyWith(
itemsWritten: null == itemsWritten ? _self.itemsWritten : itemsWritten // ignore: cast_nullable_to_non_nullable
as int,totalItems: null == totalItems ? _self.totalItems : totalItems // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ImportProgress].
extension ImportProgressPatterns on ImportProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ImportProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ImportProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ImportProgress value)  $default,){
final _that = this;
switch (_that) {
case _ImportProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ImportProgress value)?  $default,){
final _that = this;
switch (_that) {
case _ImportProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int itemsWritten,  int totalItems)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ImportProgress() when $default != null:
return $default(_that.itemsWritten,_that.totalItems);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int itemsWritten,  int totalItems)  $default,) {final _that = this;
switch (_that) {
case _ImportProgress():
return $default(_that.itemsWritten,_that.totalItems);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int itemsWritten,  int totalItems)?  $default,) {final _that = this;
switch (_that) {
case _ImportProgress() when $default != null:
return $default(_that.itemsWritten,_that.totalItems);case _:
  return null;

}
}

}

/// @nodoc


class _ImportProgress implements ImportProgress {
  const _ImportProgress({required this.itemsWritten, required this.totalItems});
  

@override final  int itemsWritten;
@override final  int totalItems;

/// Create a copy of ImportProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ImportProgressCopyWith<_ImportProgress> get copyWith => __$ImportProgressCopyWithImpl<_ImportProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ImportProgress&&(identical(other.itemsWritten, itemsWritten) || other.itemsWritten == itemsWritten)&&(identical(other.totalItems, totalItems) || other.totalItems == totalItems));
}


@override
int get hashCode => Object.hash(runtimeType,itemsWritten,totalItems);

@override
String toString() {
  return 'ImportProgress(itemsWritten: $itemsWritten, totalItems: $totalItems)';
}


}

/// @nodoc
abstract mixin class _$ImportProgressCopyWith<$Res> implements $ImportProgressCopyWith<$Res> {
  factory _$ImportProgressCopyWith(_ImportProgress value, $Res Function(_ImportProgress) _then) = __$ImportProgressCopyWithImpl;
@override @useResult
$Res call({
 int itemsWritten, int totalItems
});




}
/// @nodoc
class __$ImportProgressCopyWithImpl<$Res>
    implements _$ImportProgressCopyWith<$Res> {
  __$ImportProgressCopyWithImpl(this._self, this._then);

  final _ImportProgress _self;
  final $Res Function(_ImportProgress) _then;

/// Create a copy of ImportProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? itemsWritten = null,Object? totalItems = null,}) {
  return _then(_ImportProgress(
itemsWritten: null == itemsWritten ? _self.itemsWritten : itemsWritten // ignore: cast_nullable_to_non_nullable
as int,totalItems: null == totalItems ? _self.totalItems : totalItems // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
