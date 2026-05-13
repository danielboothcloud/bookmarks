import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'drive_auth_service.dart';
import 'drive_auth_state.dart';
import 'drive_file_service.dart';

final flutterSecureStorageProvider = Provider<FlutterSecureStorage>((_) {
  return const FlutterSecureStorage();
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final driveFileServiceProvider = Provider<DriveFileService>((ref) {
  return DriveFileService(httpClient: ref.watch(httpClientProvider));
});

final driveAuthServiceProvider = Provider<DriveAuthService>((ref) {
  return DriveAuthService(
    storage: ref.watch(flutterSecureStorageProvider),
    driveFileService: ref.watch(driveFileServiceProvider),
    httpClient: ref.watch(httpClientProvider),
  );
});

/// Owns the live [DriveAuthState]. `build()` resolves from secure
/// storage at construction; `connect()` mirrors the service's stream
/// onto `state`.
///
/// Async because [DriveAuthService.resolveInitialState] reads from
/// secure storage (a few microseconds, but technically async). The
/// router redirect (see `app_router.dart`) treats the loading window
/// as "stay where you are" so the first paint isn't blocked.
class DriveAuthNotifier extends AsyncNotifier<DriveAuthState> {
  @override
  Future<DriveAuthState> build() {
    final service = ref.watch(driveAuthServiceProvider);
    return service.resolveInitialState();
  }

  Future<void> connect() async {
    ref.read(hasAttemptedConnectProvider.notifier).markAttempted();
    final service = ref.read(driveAuthServiceProvider);
    await for (final s in service.connect()) {
      state = AsyncData(s);
    }
  }

  /// Wipe tokens. Used by 4.5 (disconnect from Settings). Exposed
  /// today so tests can drive the flow.
  Future<void> reset() async {
    await ref.read(driveAuthServiceProvider).clearTokens();
    state = const AsyncData(DriveAuthState.disconnected());
    ref.read(hasAttemptedConnectProvider.notifier).reset();
  }
}

final driveAuthStateProvider =
    AsyncNotifierProvider<DriveAuthNotifier, DriveAuthState>(
  DriveAuthNotifier.new,
);

/// One bit of ephemeral UI history: has the user clicked "Connect"
/// at least once this session? Differentiates the welcome screen's
/// "no message" (fresh) from "Drive connection needed to sync"
/// (post-cancel) states without complicating [DriveAuthState] itself.
class HasAttemptedConnectNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void markAttempted() => state = true;
  void reset() => state = false;
}

final hasAttemptedConnectProvider =
    NotifierProvider<HasAttemptedConnectNotifier, bool>(
  HasAttemptedConnectNotifier.new,
);
