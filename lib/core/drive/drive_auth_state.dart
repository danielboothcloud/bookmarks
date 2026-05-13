import 'package:freezed_annotation/freezed_annotation.dart';

import '../error/app_error.dart';

part 'drive_auth_state.freezed.dart';

/// The user's Google Drive connection state. Owned by
/// `driveAuthStateProvider`; mutated by `DriveAuthService`.
///
/// State semantics:
/// - [DriveAuthDisconnected]: no tokens in secure storage. Router
///   redirects to /welcome.
/// - [DriveAuthConnecting]: OAuth flow is in flight (browser open,
///   awaiting localhost callback). Welcome screen renders the
///   "Waiting for browser…" state.
/// - [DriveAuthConnected]: tokens persisted, file ID resolved. Router
///   redirects to /bookmarks.
/// - [DriveAuthFailed]: a non-cancellation error occurred during
///   connect. Welcome screen renders the "Couldn't connect — try
///   again" message. Carries the typed [AppError] payload for
///   forward-looking diagnostics in 4.4/4.5; for 4.1 the user-visible
///   string is the same regardless of variant.
@freezed
sealed class DriveAuthState with _$DriveAuthState {
  const factory DriveAuthState.disconnected() = DriveAuthDisconnected;
  const factory DriveAuthState.connecting() = DriveAuthConnecting;
  const factory DriveAuthState.connected({
    required String email,
    required String fileId,
  }) = DriveAuthConnected;
  const factory DriveAuthState.failed(AppError error) = DriveAuthFailed;
}
