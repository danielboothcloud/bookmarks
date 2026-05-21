import 'dart:async';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSyncService implements DriveSyncService {
  final List<String> syncedFileIds = [];
  final List<String> pushedFileIds = [];
  final List<String> pulledFileIds = [];
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
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
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      driveSyncServiceProvider.overrideWithValue(service),
      driveAuthStateProvider.overrideWith(
        () => authNotifierOut ?? _FakeDriveAuthNotifier(initialAuth),
      ),
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
}
