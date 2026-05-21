// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncStatus {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncStatus()';
}


}

/// @nodoc
class $SyncStatusCopyWith<$Res>  {
$SyncStatusCopyWith(SyncStatus _, $Res Function(SyncStatus) __);
}


/// Adds pattern-matching-related methods to [SyncStatus].
extension SyncStatusPatterns on SyncStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SyncIdle value)?  idle,TResult Function( SyncPushing value)?  pushing,TResult Function( SyncSynced value)?  synced,TResult Function( SyncFailed value)?  failed,TResult Function( SyncAwaitingInitialPull value)?  awaitingInitialPull,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SyncIdle() when idle != null:
return idle(_that);case SyncPushing() when pushing != null:
return pushing(_that);case SyncSynced() when synced != null:
return synced(_that);case SyncFailed() when failed != null:
return failed(_that);case SyncAwaitingInitialPull() when awaitingInitialPull != null:
return awaitingInitialPull(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SyncIdle value)  idle,required TResult Function( SyncPushing value)  pushing,required TResult Function( SyncSynced value)  synced,required TResult Function( SyncFailed value)  failed,required TResult Function( SyncAwaitingInitialPull value)  awaitingInitialPull,}){
final _that = this;
switch (_that) {
case SyncIdle():
return idle(_that);case SyncPushing():
return pushing(_that);case SyncSynced():
return synced(_that);case SyncFailed():
return failed(_that);case SyncAwaitingInitialPull():
return awaitingInitialPull(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SyncIdle value)?  idle,TResult? Function( SyncPushing value)?  pushing,TResult? Function( SyncSynced value)?  synced,TResult? Function( SyncFailed value)?  failed,TResult? Function( SyncAwaitingInitialPull value)?  awaitingInitialPull,}){
final _that = this;
switch (_that) {
case SyncIdle() when idle != null:
return idle(_that);case SyncPushing() when pushing != null:
return pushing(_that);case SyncSynced() when synced != null:
return synced(_that);case SyncFailed() when failed != null:
return failed(_that);case SyncAwaitingInitialPull() when awaitingInitialPull != null:
return awaitingInitialPull(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  pushing,TResult Function( DateTime at)?  synced,TResult Function( AppError error)?  failed,TResult Function()?  awaitingInitialPull,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SyncIdle() when idle != null:
return idle();case SyncPushing() when pushing != null:
return pushing();case SyncSynced() when synced != null:
return synced(_that.at);case SyncFailed() when failed != null:
return failed(_that.error);case SyncAwaitingInitialPull() when awaitingInitialPull != null:
return awaitingInitialPull();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  pushing,required TResult Function( DateTime at)  synced,required TResult Function( AppError error)  failed,required TResult Function()  awaitingInitialPull,}) {final _that = this;
switch (_that) {
case SyncIdle():
return idle();case SyncPushing():
return pushing();case SyncSynced():
return synced(_that.at);case SyncFailed():
return failed(_that.error);case SyncAwaitingInitialPull():
return awaitingInitialPull();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  pushing,TResult? Function( DateTime at)?  synced,TResult? Function( AppError error)?  failed,TResult? Function()?  awaitingInitialPull,}) {final _that = this;
switch (_that) {
case SyncIdle() when idle != null:
return idle();case SyncPushing() when pushing != null:
return pushing();case SyncSynced() when synced != null:
return synced(_that.at);case SyncFailed() when failed != null:
return failed(_that.error);case SyncAwaitingInitialPull() when awaitingInitialPull != null:
return awaitingInitialPull();case _:
  return null;

}
}

}

/// @nodoc


class SyncIdle implements SyncStatus {
  const SyncIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncStatus.idle()';
}


}




/// @nodoc


class SyncPushing implements SyncStatus {
  const SyncPushing();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncPushing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncStatus.pushing()';
}


}




/// @nodoc


class SyncSynced implements SyncStatus {
  const SyncSynced({required this.at});
  

 final  DateTime at;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncSyncedCopyWith<SyncSynced> get copyWith => _$SyncSyncedCopyWithImpl<SyncSynced>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncSynced&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode => Object.hash(runtimeType,at);

@override
String toString() {
  return 'SyncStatus.synced(at: $at)';
}


}

/// @nodoc
abstract mixin class $SyncSyncedCopyWith<$Res> implements $SyncStatusCopyWith<$Res> {
  factory $SyncSyncedCopyWith(SyncSynced value, $Res Function(SyncSynced) _then) = _$SyncSyncedCopyWithImpl;
@useResult
$Res call({
 DateTime at
});




}
/// @nodoc
class _$SyncSyncedCopyWithImpl<$Res>
    implements $SyncSyncedCopyWith<$Res> {
  _$SyncSyncedCopyWithImpl(this._self, this._then);

  final SyncSynced _self;
  final $Res Function(SyncSynced) _then;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(SyncSynced(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc


class SyncFailed implements SyncStatus {
  const SyncFailed(this.error);
  

 final  AppError error;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncFailedCopyWith<SyncFailed> get copyWith => _$SyncFailedCopyWithImpl<SyncFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'SyncStatus.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $SyncFailedCopyWith<$Res> implements $SyncStatusCopyWith<$Res> {
  factory $SyncFailedCopyWith(SyncFailed value, $Res Function(SyncFailed) _then) = _$SyncFailedCopyWithImpl;
@useResult
$Res call({
 AppError error
});




}
/// @nodoc
class _$SyncFailedCopyWithImpl<$Res>
    implements $SyncFailedCopyWith<$Res> {
  _$SyncFailedCopyWithImpl(this._self, this._then);

  final SyncFailed _self;
  final $Res Function(SyncFailed) _then;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(SyncFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as AppError,
  ));
}


}

/// @nodoc


class SyncAwaitingInitialPull implements SyncStatus {
  const SyncAwaitingInitialPull();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncAwaitingInitialPull);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SyncStatus.awaitingInitialPull()';
}


}




// dart format on
