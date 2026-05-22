import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connectivity providers — Story 4.5.
///
/// Wraps the `connectivity_plus` v6.1.x API so the sync orchestrator can
/// observe `offline -> online` transitions and wake the engine up. The
/// package's stream is the wake-up signal; the engine's per-attempt
/// retry is the actual health check (a captive-portal Wi-Fi reports
/// `[ConnectivityResult.wifi]` and we let it try, then surface
/// `SyncFailed(NetworkError)` if Drive is unreachable).
///
/// **v6.1.x API shape:** `Connectivity().onConnectivityChanged` is a
/// `Stream<List<ConnectivityResult>>` (v5 returned a single
/// `ConnectivityResult`; v6 returns the full list of currently-active
/// interfaces). We treat any non-`none` entry as "online" — a wifi
/// connection plus a tethered phone both count as online; the only
/// offline state is `[ConnectivityResult.none]`.
///
/// The provider yields the current state synchronously on first
/// subscribe (from `checkConnectivity()`) so subscribers don't sit in
/// `AsyncLoading` on a stable network until the OS publishes its next
/// change event.

/// Wraps the `Connectivity()` singleton for test override. Production
/// reads the singleton once at app boot; tests override with a
/// `_FakeConnectivity` exposing a controllable stream.
final connectivityProvider = Provider<Connectivity>((_) => Connectivity());

/// Derived `bool` stream — `true` iff at least one network interface is
/// active. Emits the current state synchronously on first subscribe,
/// then forwards every OS connectivity change. The orchestrator's
/// `offline -> online` transition guard lives in
/// `drive_sync_providers.dart`; this provider does NOT de-dup
/// `true -> true` re-emits (Wi-Fi -> Wi-Fi+Ethernet still emits both
/// times).
final connectivityOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivityProvider);
  final initial = await connectivity.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  await for (final list in connectivity.onConnectivityChanged) {
    yield list.any((r) => r != ConnectivityResult.none);
  }
});
