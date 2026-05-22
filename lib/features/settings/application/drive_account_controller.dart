import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/drive/drive_auth_providers.dart';
import '../../../core/drive/drive_sync_providers.dart';
import '../../../core/drive/drive_sync_service.dart';

/// Cross-cutting orchestrator for the Settings "Disconnect" action —
/// Story 4.5.
///
/// Owns the disconnect choreography that spans three subsystems:
/// the sync queue, the push gate (secure storage), and the auth notifier.
/// Lives at the application layer because no single subsystem owns
/// disconnect end-to-end:
///   - `DriveAuthNotifier.reset()` knows how to wipe tokens but
///     intentionally does NOT know about queue rows or the push gate.
///   - `SyncQueueRepository.clear()` knows how to empty the queue but
///     not about auth state or secure-storage keys.
///   - `DriveSyncService.reset()` knows how to clear engine in-memory
///     state but is triggered indirectly via the orchestrator's
///     auth-state listener (see `autoPushOrchestratorProvider`).
///
/// The controller is `Notifier<void>` — it holds no state. The work
/// happens entirely inside [disconnect].
///
/// **Order matters.** Clear the queue first, then the gate, then wipe
/// tokens. Wiping tokens first then trying to flush the queue would leak
/// a final push attempt against soon-to-be-stale credentials; clearing
/// the queue first is harmless because every local change persists in
/// the Drift DB regardless of queue state.
///
/// **Best-effort cleanup.** A partial failure (e.g. macOS Keychain
/// hiccup on the gate-delete) is logged via `debugPrint` and the next
/// step still runs — the user-facing outcome must be "Drive is
/// disconnected" even on partial state. Any zombie keys heal on the
/// next connect via `DriveAuthService.resolveInitialState()`'s
/// all-or-nothing check.
class DriveAccountController extends Notifier<void> {
  @override
  void build() {}

  Future<void> disconnect() async {
    // Step 1: clear the outbox so a soon-to-be-wiped credential set
    // can't fire a final push during the brief window between (2) and
    // (3). Local data is unaffected.
    try {
      await ref.read(syncQueueRepositoryProvider).clear();
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint('DriveAccountController.disconnect: queue clear failed: '
            '$e\n$s');
      }
    }

    // Step 2: close the push gate so a future reconnect to a different
    // account doesn't push without going through the pull-first cycle.
    try {
      await ref
          .read(flutterSecureStorageProvider)
          .delete(key: kDriveLastPulledAtKey);
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint('DriveAccountController.disconnect: gate clear failed: '
            '$e\n$s');
      }
    }

    // Step 3: wipe tokens and flip auth state to disconnected. The
    // resulting `connected -> disconnected` transition trips the
    // `autoPushOrchestratorProvider` auth-state listener, which calls
    // `DriveSyncService.reset()` to clear engine in-memory state. The
    // router's `_AuthRefreshNotifier` also picks up the change and
    // redirects /settings -> /welcome.
    await ref.read(driveAuthStateProvider.notifier).reset();
  }
}

final driveAccountControllerProvider =
    NotifierProvider<DriveAccountController, void>(
  DriveAccountController.new,
);
