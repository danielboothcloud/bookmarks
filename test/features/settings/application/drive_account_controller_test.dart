import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/features/settings/application/drive_account_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls the controller makes so we can assert order
/// without depending on real Drift / secure storage / OAuth.
class _CallLog {
  final List<String> events = [];
}

class _SpyQueueRepository implements SyncQueueRepository {
  _SpyQueueRepository(this._log, {this.throwOnClear = false});
  final _CallLog _log;
  final bool throwOnClear;
  int clearCalls = 0;

  @override
  Future<int> clear() async {
    clearCalls++;
    _log.events.add('queue.clear');
    if (throwOnClear) throw StateError('queue boom');
    return 0;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpySecureStorage implements FlutterSecureStorage {
  _SpySecureStorage(this._log, {this.throwOnDelete = false});
  final _CallLog _log;
  final bool throwOnDelete;
  final List<String> deletedKeys = [];

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    deletedKeys.add(key);
    _log.events.add('storage.delete:$key');
    if (throwOnDelete) throw StateError('storage boom');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyAuthNotifier extends DriveAuthNotifier {
  _SpyAuthNotifier(this._log, this._initial);
  final _CallLog _log;
  final DriveAuthState _initial;
  int resetCalls = 0;

  @override
  Future<DriveAuthState> build() async => _initial;

  @override
  Future<void> reset() async {
    resetCalls++;
    _log.events.add('auth.reset');
    state = const AsyncData(DriveAuthState.disconnected());
  }
}

ProviderContainer _buildContainer({
  required _CallLog log,
  required _SpyQueueRepository queue,
  required _SpySecureStorage storage,
  required _SpyAuthNotifier authNotifier,
}) {
  return ProviderContainer(overrides: [
    syncQueueRepositoryProvider.overrideWithValue(queue),
    flutterSecureStorageProvider.overrideWithValue(storage),
    driveAuthStateProvider.overrideWith(() => authNotifier),
  ]);
}

void main() {
  late _CallLog log;
  late _SpyQueueRepository queue;
  late _SpySecureStorage storage;
  late _SpyAuthNotifier authNotifier;

  setUp(() {
    log = _CallLog();
    queue = _SpyQueueRepository(log);
    storage = _SpySecureStorage(log);
    authNotifier = _SpyAuthNotifier(
      log,
      const DriveAuthState.connected(
        email: 'alice@example.com',
        fileId: 'file-1',
      ),
    );
  });

  test(
      'disconnect() calls queue.clear, storage.delete(last_pulled_at), '
      'and auth.reset exactly once each, in that order', () async {
    final container = _buildContainer(
      log: log,
      queue: queue,
      storage: storage,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);

    // Force the auth notifier to build so `state` is initialised.
    await container.read(driveAuthStateProvider.future);

    await container.read(driveAccountControllerProvider.notifier).disconnect();

    expect(queue.clearCalls, 1);
    expect(storage.deletedKeys, [kDriveLastPulledAtKey]);
    expect(authNotifier.resetCalls, 1);
    expect(log.events, [
      'queue.clear',
      'storage.delete:$kDriveLastPulledAtKey',
      'auth.reset',
    ]);
  });

  test('disconnect() continues if queue.clear throws (auth.reset still runs)',
      () async {
    queue = _SpyQueueRepository(log, throwOnClear: true);
    final container = _buildContainer(
      log: log,
      queue: queue,
      storage: storage,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);
    await container.read(driveAuthStateProvider.future);

    await container.read(driveAccountControllerProvider.notifier).disconnect();

    expect(queue.clearCalls, 1);
    expect(storage.deletedKeys, [kDriveLastPulledAtKey],
        reason: 'gate-clear runs even after queue-clear throws');
    expect(authNotifier.resetCalls, 1,
        reason: 'token wipe runs even after queue-clear throws');
  });

  test(
      'disconnect() continues if storage.delete throws (auth.reset still '
      'runs)', () async {
    storage = _SpySecureStorage(log, throwOnDelete: true);
    final container = _buildContainer(
      log: log,
      queue: queue,
      storage: storage,
      authNotifier: authNotifier,
    );
    addTearDown(container.dispose);
    await container.read(driveAuthStateProvider.future);

    await container.read(driveAccountControllerProvider.notifier).disconnect();

    expect(queue.clearCalls, 1);
    expect(authNotifier.resetCalls, 1,
        reason: 'token wipe runs even after gate-clear throws');
  });
}
