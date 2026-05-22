import 'dart:async';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/connectivity_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSyncService implements DriveSyncService {
  final List<String> syncedFileIds = [];
  final List<String> pushedFileIds = [];
  final List<String> pulledFileIds = [];
  int resetCalls = 0;
  final _controller = StreamController<dynamic>.broadcast();

  @override
  Future<Result<void, AppError>> sync({required String fileId}) async {
    syncedFileIds.add(fileId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<void, AppError>> push({required String fileId}) async {
    pushedFileIds.add(fileId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<void, AppError>> pull({required String fileId}) async {
    pulledFileIds.add(fileId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<void> reset() async {
    resetCalls++;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity({
    List<ConnectivityResult> initial = const [ConnectivityResult.none],
  }) : _current = initial;

  List<ConnectivityResult> _current;
  final _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  void emit(List<ConnectivityResult> next) {
    _current = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDriveAuthNotifier extends DriveAuthNotifier {
  _FakeDriveAuthNotifier(this._initial);
  final DriveAuthState _initial;

  @override
  Future<DriveAuthState> build() async => _initial;

  void set(DriveAuthState newState) {
    state = AsyncData(newState);
  }
}

ProviderContainer _buildContainer({
  required AppDatabase db,
  required _RecordingSyncService service,
  required DriveAuthState initialAuth,
  _FakeDriveAuthNotifier? authNotifierOut,
  _FakeConnectivity? connectivity,
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      driveSyncServiceProvider.overrideWithValue(service),
      driveAuthStateProvider.overrideWith(
        () => authNotifierOut ?? _FakeDriveAuthNotifier(initialAuth),
      ),
      if (connectivity != null)
        connectivityProvider.overrideWithValue(connectivity),
    ],
  );
}

void main() {
  late AppDatabase db;
  late _RecordingSyncService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = _RecordingSyncService();
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  test('queue insert fires sync() within ~300ms when auth is connected',
      () async {
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'test@example.com',
        fileId: 'fake-file-id',
      ),
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    await db.customStatement(
      "INSERT INTO sync_queue (operation, entity_type, entity_id, payload, "
      "created_at) VALUES ('upsert', 'bookmark', 'b1', NULL, 1)",
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(service.syncedFileIds, ['fake-file-id']);
    expect(service.pushedFileIds, isEmpty,
        reason: 'orchestrator now calls sync(), not push()');
  });

  test('queue insert does NOT fire sync() when auth is disconnected',
      () async {
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.disconnected(),
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    await db.customStatement(
      "INSERT INTO sync_queue (operation, entity_type, entity_id, payload, "
      "created_at) VALUES ('upsert', 'bookmark', 'b1', NULL, 1)",
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(service.syncedFileIds, isEmpty);
  });

  test('auth-state transition into connected triggers a sync()', () async {
    final notifier = _FakeDriveAuthNotifier(
      const DriveAuthState.disconnected(),
    );
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.disconnected(),
      authNotifierOut: notifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.syncedFileIds, isEmpty);

    notifier.set(const DriveAuthState.connected(
      email: 'x@y.com',
      fileId: 'connected-file-id',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.syncedFileIds, ['connected-file-id']);
  });

  test('rapid queue bursts within debounce window collapse to one sync()',
      () async {
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'fid',
      ),
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.read(syncQueuePendingCountProvider);

    for (var i = 0; i < 5; i++) {
      await db.customStatement(
        "INSERT INTO sync_queue (operation, entity_type, entity_id, payload, "
        "created_at) VALUES ('upsert', 'bookmark', ?, NULL, 1)",
        ['b$i'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(service.syncedFileIds, hasLength(1),
        reason:
            'debounce should collapse the 5 bursts into a single sync()');

    expect((await SyncQueueRepository(db).drain()), hasLength(5));
  });

  // ---------------------------------------------------------------------
  // Story 4.5: connectivity-restored trigger
  // ---------------------------------------------------------------------

  test(
      'connectivity offline -> online while connected fires sync() once',
      () async {
    final connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.none],
    );
    addTearDown(connectivity.dispose);
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'connected-fid',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    // Keep the StreamProvider alive so its async* loop runs.
    container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, __) {},
      fireImmediately: true,
    );

    // Let the initial `_ -> connected` auth-state sync fire and settle;
    // capture baseline count so the connectivity assertion isolates the
    // new trigger.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final baseline = service.syncedFileIds.length;

    connectivity.emit(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.syncedFileIds.length, baseline + 1,
        reason: 'offline -> online fires exactly one additional sync()');
    expect(service.syncedFileIds.last, 'connected-fid');
  });

  test('connectivity online -> online does NOT fire sync()', () async {
    final connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.wifi],
    );
    addTearDown(connectivity.dispose);
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'fid',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, __) {},
      fireImmediately: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final baselineCount = service.syncedFileIds.length;

    connectivity.emit(
      const [ConnectivityResult.wifi, ConnectivityResult.ethernet],
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.syncedFileIds.length, baselineCount,
        reason: 'wifi -> wifi+ethernet is a same-state re-emit; no sync');
  });

  test('connectivity online -> offline does NOT fire sync()', () async {
    final connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.wifi],
    );
    addTearDown(connectivity.dispose);
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'fid',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, __) {},
      fireImmediately: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final baselineCount = service.syncedFileIds.length;

    connectivity.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.syncedFileIds.length, baselineCount,
        reason: 'online -> offline is the wrong direction; no sync');
  });

  test(
      'connectivity offline -> online while DISCONNECTED does NOT fire '
      'sync()', () async {
    final connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.none],
    );
    addTearDown(connectivity.dispose);
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.disconnected(),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
      connectivityOnlineProvider,
      (_, __) {},
      fireImmediately: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    connectivity.emit(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.syncedFileIds, isEmpty,
        reason: 'auth guard must short-circuit when disconnected');
  });

  // ---------------------------------------------------------------------
  // Story 4.5: connected -> disconnected hook
  // ---------------------------------------------------------------------

  test('connected -> disconnected calls DriveSyncService.reset()',
      () async {
    final notifier = _FakeDriveAuthNotifier(
      const DriveAuthState.connected(email: 'x@y.com', fileId: 'fid'),
    );
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'fid',
      ),
      authNotifierOut: notifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Initial connected emit fires a sync(); reset hasn't been called yet.
    expect(service.resetCalls, 0);

    notifier.set(const DriveAuthState.disconnected());
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.resetCalls, 1,
        reason: 'connected -> disconnected must call DriveSyncService.reset()');
  });

  test(
      'connected -> disconnected invalidates hasEverSyncedProvider (next '
      'read starts from false)', () async {
    final notifier = _FakeDriveAuthNotifier(
      const DriveAuthState.connected(email: 'x@y.com', fileId: 'fid'),
    );
    final container = _buildContainer(
      db: db,
      service: service,
      initialAuth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'fid',
      ),
      authNotifierOut: notifier,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    // Read once to materialize the provider.
    final firstRead = container.read(hasEverSyncedProvider);
    expect(firstRead, isA<AsyncValue<bool>>());

    notifier.set(const DriveAuthState.disconnected());
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // After invalidate, the next read returns a fresh provider state —
    // for a StreamProvider that's AsyncLoading until the first yield.
    // The initial yield is `false` so re-reading should yield false
    // (or loading-then-false). The contract is "starts clean".
    final secondRead = container.read(hasEverSyncedProvider);
    // Either AsyncLoading (just-invalidated) or AsyncData(false).
    expect(
      secondRead.maybeWhen(
        data: (v) => v,
        orElse: () => null,
      ),
      anyOf(equals(false), isNull),
      reason: 'invalidation must reset hasEverSynced to its initial state',
    );
  });
}
