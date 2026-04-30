// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'url_metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UrlMetadata {

 String? get title; String? get faviconBase64;
/// Create a copy of UrlMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UrlMetadataCopyWith<UrlMetadata> get copyWith => _$UrlMetadataCopyWithImpl<UrlMetadata>(this as UrlMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UrlMetadata&&(identical(other.title, title) || other.title == title)&&(identical(other.faviconBase64, faviconBase64) || other.faviconBase64 == faviconBase64));
}


@override
int get hashCode => Object.hash(runtimeType,title,faviconBase64);

@override
String toString() {
  return 'UrlMetadata(title: $title, faviconBase64: $faviconBase64)';
}


}

/// @nodoc
abstract mixin class $UrlMetadataCopyWith<$Res>  {
  factory $UrlMetadataCopyWith(UrlMetadata value, $Res Function(UrlMetadata) _then) = _$UrlMetadataCopyWithImpl;
@useResult
$Res call({
 String? title, String? faviconBase64
});




}
/// @nodoc
class _$UrlMetadataCopyWithImpl<$Res>
    implements $UrlMetadataCopyWith<$Res> {
  _$UrlMetadataCopyWithImpl(this._self, this._then);

  final UrlMetadata _self;
  final $Res Function(UrlMetadata) _then;

/// Create a copy of UrlMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = freezed,Object? faviconBase64 = freezed,}) {
  return _then(_self.copyWith(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,faviconBase64: freezed == faviconBase64 ? _self.faviconBase64 : faviconBase64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [UrlMetadata].
extension UrlMetadataPatterns on UrlMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UrlMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UrlMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UrlMetadata value)  $default,){
final _that = this;
switch (_that) {
case _UrlMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UrlMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _UrlMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? title,  String? faviconBase64)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UrlMetadata() when $default != null:
return $default(_that.title,_that.faviconBase64);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? title,  String? faviconBase64)  $default,) {final _that = this;
switch (_that) {
case _UrlMetadata():
return $default(_that.title,_that.faviconBase64);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? title,  String? faviconBase64)?  $default,) {final _that = this;
switch (_that) {
case _UrlMetadata() when $default != null:
return $default(_that.title,_that.faviconBase64);case _:
  return null;

}
}

}

/// @nodoc


class _UrlMetadata implements UrlMetadata {
  const _UrlMetadata({this.title, this.faviconBase64});
  

@override final  String? title;
@override final  String? faviconBase64;

/// Create a copy of UrlMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UrlMetadataCopyWith<_UrlMetadata> get copyWith => __$UrlMetadataCopyWithImpl<_UrlMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UrlMetadata&&(identical(other.title, title) || other.title == title)&&(identical(other.faviconBase64, faviconBase64) || other.faviconBase64 == faviconBase64));
}


@override
int get hashCode => Object.hash(runtimeType,title,faviconBase64);

@override
String toString() {
  return 'UrlMetadata(title: $title, faviconBase64: $faviconBase64)';
}


}

/// @nodoc
abstract mixin class _$UrlMetadataCopyWith<$Res> implements $UrlMetadataCopyWith<$Res> {
  factory _$UrlMetadataCopyWith(_UrlMetadata value, $Res Function(_UrlMetadata) _then) = __$UrlMetadataCopyWithImpl;
@override @useResult
$Res call({
 String? title, String? faviconBase64
});




}
/// @nodoc
class __$UrlMetadataCopyWithImpl<$Res>
    implements _$UrlMetadataCopyWith<$Res> {
  __$UrlMetadataCopyWithImpl(this._self, this._then);

  final _UrlMetadata _self;
  final $Res Function(_UrlMetadata) _then;

/// Create a copy of UrlMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? faviconBase64 = freezed,}) {
  return _then(_UrlMetadata(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,faviconBase64: freezed == faviconBase64 ? _self.faviconBase64 : faviconBase64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
