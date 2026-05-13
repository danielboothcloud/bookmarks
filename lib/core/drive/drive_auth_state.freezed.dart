// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'drive_auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DriveAuthState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveAuthState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DriveAuthState()';
}


}

/// @nodoc
class $DriveAuthStateCopyWith<$Res>  {
$DriveAuthStateCopyWith(DriveAuthState _, $Res Function(DriveAuthState) __);
}


/// Adds pattern-matching-related methods to [DriveAuthState].
extension DriveAuthStatePatterns on DriveAuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DriveAuthDisconnected value)?  disconnected,TResult Function( DriveAuthConnecting value)?  connecting,TResult Function( DriveAuthConnected value)?  connected,TResult Function( DriveAuthFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DriveAuthDisconnected() when disconnected != null:
return disconnected(_that);case DriveAuthConnecting() when connecting != null:
return connecting(_that);case DriveAuthConnected() when connected != null:
return connected(_that);case DriveAuthFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DriveAuthDisconnected value)  disconnected,required TResult Function( DriveAuthConnecting value)  connecting,required TResult Function( DriveAuthConnected value)  connected,required TResult Function( DriveAuthFailed value)  failed,}){
final _that = this;
switch (_that) {
case DriveAuthDisconnected():
return disconnected(_that);case DriveAuthConnecting():
return connecting(_that);case DriveAuthConnected():
return connected(_that);case DriveAuthFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DriveAuthDisconnected value)?  disconnected,TResult? Function( DriveAuthConnecting value)?  connecting,TResult? Function( DriveAuthConnected value)?  connected,TResult? Function( DriveAuthFailed value)?  failed,}){
final _that = this;
switch (_that) {
case DriveAuthDisconnected() when disconnected != null:
return disconnected(_that);case DriveAuthConnecting() when connecting != null:
return connecting(_that);case DriveAuthConnected() when connected != null:
return connected(_that);case DriveAuthFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( String email,  String fileId)?  connected,TResult Function( AppError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DriveAuthDisconnected() when disconnected != null:
return disconnected();case DriveAuthConnecting() when connecting != null:
return connecting();case DriveAuthConnected() when connected != null:
return connected(_that.email,_that.fileId);case DriveAuthFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( String email,  String fileId)  connected,required TResult Function( AppError error)  failed,}) {final _that = this;
switch (_that) {
case DriveAuthDisconnected():
return disconnected();case DriveAuthConnecting():
return connecting();case DriveAuthConnected():
return connected(_that.email,_that.fileId);case DriveAuthFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( String email,  String fileId)?  connected,TResult? Function( AppError error)?  failed,}) {final _that = this;
switch (_that) {
case DriveAuthDisconnected() when disconnected != null:
return disconnected();case DriveAuthConnecting() when connecting != null:
return connecting();case DriveAuthConnected() when connected != null:
return connected(_that.email,_that.fileId);case DriveAuthFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class DriveAuthDisconnected implements DriveAuthState {
  const DriveAuthDisconnected();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveAuthDisconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DriveAuthState.disconnected()';
}


}




/// @nodoc


class DriveAuthConnecting implements DriveAuthState {
  const DriveAuthConnecting();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveAuthConnecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'DriveAuthState.connecting()';
}


}




/// @nodoc


class DriveAuthConnected implements DriveAuthState {
  const DriveAuthConnected({required this.email, required this.fileId});
  

 final  String email;
 final  String fileId;

/// Create a copy of DriveAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DriveAuthConnectedCopyWith<DriveAuthConnected> get copyWith => _$DriveAuthConnectedCopyWithImpl<DriveAuthConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveAuthConnected&&(identical(other.email, email) || other.email == email)&&(identical(other.fileId, fileId) || other.fileId == fileId));
}


@override
int get hashCode => Object.hash(runtimeType,email,fileId);

@override
String toString() {
  return 'DriveAuthState.connected(email: $email, fileId: $fileId)';
}


}

/// @nodoc
abstract mixin class $DriveAuthConnectedCopyWith<$Res> implements $DriveAuthStateCopyWith<$Res> {
  factory $DriveAuthConnectedCopyWith(DriveAuthConnected value, $Res Function(DriveAuthConnected) _then) = _$DriveAuthConnectedCopyWithImpl;
@useResult
$Res call({
 String email, String fileId
});




}
/// @nodoc
class _$DriveAuthConnectedCopyWithImpl<$Res>
    implements $DriveAuthConnectedCopyWith<$Res> {
  _$DriveAuthConnectedCopyWithImpl(this._self, this._then);

  final DriveAuthConnected _self;
  final $Res Function(DriveAuthConnected) _then;

/// Create a copy of DriveAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? email = null,Object? fileId = null,}) {
  return _then(DriveAuthConnected(
email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,fileId: null == fileId ? _self.fileId : fileId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DriveAuthFailed implements DriveAuthState {
  const DriveAuthFailed(this.error);
  

 final  AppError error;

/// Create a copy of DriveAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DriveAuthFailedCopyWith<DriveAuthFailed> get copyWith => _$DriveAuthFailedCopyWithImpl<DriveAuthFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DriveAuthFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'DriveAuthState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $DriveAuthFailedCopyWith<$Res> implements $DriveAuthStateCopyWith<$Res> {
  factory $DriveAuthFailedCopyWith(DriveAuthFailed value, $Res Function(DriveAuthFailed) _then) = _$DriveAuthFailedCopyWithImpl;
@useResult
$Res call({
 AppError error
});




}
/// @nodoc
class _$DriveAuthFailedCopyWithImpl<$Res>
    implements $DriveAuthFailedCopyWith<$Res> {
  _$DriveAuthFailedCopyWithImpl(this._self, this._then);

  final DriveAuthFailed _self;
  final $Res Function(DriveAuthFailed) _then;

/// Create a copy of DriveAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(DriveAuthFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as AppError,
  ));
}


}

// dart format on
