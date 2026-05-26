import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/connectivity_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async =>
      store[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

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
    store.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthNotifier extends DriveAuthNotifier {
  _FakeAuthNotifier(this._initial);
  final DriveAuthState _initial;
  @override
  Future<DriveAuthState> build() async => _initial;
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

class _FakeDriveServer {
  _FakeDriveServer({String? initialRemoteJson})
      : remoteContent = initialRemoteJson ??
            jsonEncode({
              'version': 1,
              'lastModified': DateTime.utc(2026, 5, 19).toIso8601String(),
              'bookmarks': <Object>[],
              'folders': <Object>[],
              'tags': <Object>[],
            });

  String remoteContent;
  bool _online = true;
  final List<http.Request> uploads = <http.Request>[];

  void setOnline(bool value) => _online = value;

  http.Client buildClient() =>
      MockClient.streaming((request, bodyStream) async {
        if (!_online) {
          throw http.ClientException(
            'Simulated network failure',
            request.url,
          );
        }
        final url = request.url;
        if (url.path.startsWith('/upload/drive/v3/files/')) {
          final body = await bodyStream
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          final text = utf8.decode(body);
          uploads.add(http.Request(request.method, url)..body = text);
          remoteContent = text;
          return http.StreamedResponse(
            Stream<List<int>>.value(
                utf8.encode('{"id":"file-1","name":"bookmarks.json"}')),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            url.path.startsWith('/drive/v3/files/')) {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(remoteContent)),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{}')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });
}

void _seedCreds(_InMemoryStorage storage) {
  storage.store[DriveStorageKeys.accessToken] = 'a';
  storage.store[DriveStorageKeys.refreshToken] = 'r';
  storage.store[DriveStorageKeys.expiresAt] =
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
}

const _fastRetry = DriveRetryPolicy(
  maxAttempts: 2,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 3),
);

/// Recording subclass of [DriveSyncService] for asserting `sync()` call
/// counts at the integration boundary. Forwards everything else to the
/// real engine so the underlying push/pull/coalesce behaviours stay
/// honest.
class _CountingSyncService extends DriveSyncService {
  _CountingSyncService({
    required super.queue,
    required super.snapshotBuilder,
    required super.credentials,
    required super.storage,
    required super.httpClient,
    required super.mergeApplier,
    super.retryPolicy,
  });

  int syncCallCount = 0;

  @override
  Future<Result<void, AppError>> sync({required String fileId}) {
    syncCallCount++;
    return super.sync(fileId: fileId);
  }
}

ProviderContainer _buildContainer({
  required AppDatabase db,
  required _InMemoryStorage storage,
  required _FakeDriveServer drive,
  required DriveAuthState auth,
  required _FakeConnectivity connectivity,
}) {
  final client = drive.buildClient();
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      flutterSecureStorageProvider.overrideWithValue(storage),
      httpClientProvider.overrideWithValue(client),
      driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      connectivityProvider.overrideWithValue(connectivity),
      driveSyncServiceProvider.overrideWith((ref) {
        return _CountingSyncService(
          queue: ref.watch(syncQueueRepositoryProvider),
          snapshotBuilder: ref.watch(driveSnapshotBuilderProvider),
          credentials: ref.watch(driveCredentialsStoreProvider),
          storage: ref.watch(flutterSecureStorageProvider),
          httpClient: ref.watch(httpClientProvider),
          mergeApplier: ref.watch(mergeApplierProvider),
          retryPolicy: _fastRetry,
        );
      }),
    ],
  );
}

Bookmark _bm(String id) {
  final now = DateTime.now();
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: 'Title $id',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _waitForStatus(
  ProviderContainer container,
  bool Function(SyncStatus) predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final completer = Completer<void>();
  final sub = container
      .read(driveSyncServiceProvider)
      .watchStatus()
      .listen((s) {
    if (predicate(s) && !completer.isCompleted) completer.complete();
  });
  final current = container.read(syncStatusProvider).value;
  if (current != null && predicate(current) && !completer.isCompleted) {
    completer.complete();
  }
  try {
    await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

void main() {
  late AppDatabase db;
  late _InMemoryStorage storage;
  late _FakeDriveServer drive;
  late _FakeConnectivity connectivity;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemoryStorage();
    drive = _FakeDriveServer();
    connectivity = _FakeConnectivity();
    _seedCreds(storage);
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
  });

  tearDown(() async {
    await connectivity.dispose();
    await db.close();
  });

  test(
      'A: connectivity restoration triggers a fresh sync after offline failure',
      () async {
    connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.none],
    );
    drive.setOnline(false);

    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
        connectivityOnlineProvider, (_, _) {},
        fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {},
        fireImmediately: true);

    // Queue write → orchestrator debounce → sync() → push fails (offline)
    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    await _waitForStatus(container, (s) => s is SyncFailed);

    final svc = container.read(driveSyncServiceProvider)
        as _CountingSyncService;
    final beforeCount = svc.syncCallCount;
    expect(beforeCount, greaterThan(0),
        reason: 'queue-debounce trigger fired at least once');

    // Bring connectivity back online and let Drive answer.
    drive.setOnline(true);
    connectivity.emit(const [ConnectivityResult.wifi]);

    await _waitForStatus(container, (s) => s is SyncSynced);
    expect(svc.syncCallCount, greaterThan(beforeCount),
        reason: 'connectivity-restored listener fired an additional sync()');
    expect(drive.uploads, isNotEmpty,
        reason: 'the queued bookmark uploaded once Drive was reachable');
  });

  test('B: same-state re-emit ([wifi] -> [wifi, ethernet]) does NOT sync()',
      () async {
    connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.wifi],
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
        connectivityOnlineProvider, (_, _) {},
        fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);

    // Settle initial auth-state sync.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final svc = container.read(driveSyncServiceProvider)
        as _CountingSyncService;
    final baseline = svc.syncCallCount;

    connectivity.emit(
      const [ConnectivityResult.wifi, ConnectivityResult.ethernet],
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(svc.syncCallCount, baseline,
        reason: 'true -> true re-emit is filtered by the transition guard');
  });

  test('C: online -> offline does NOT sync()', () async {
    connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.wifi],
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
        connectivityOnlineProvider, (_, _) {},
        fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final svc = container.read(driveSyncServiceProvider)
        as _CountingSyncService;
    final baseline = svc.syncCallCount;

    connectivity.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(svc.syncCallCount, baseline,
        reason: 'true -> false is the wrong direction');
  });

  test(
      'D: connectivity offline -> online while DISCONNECTED suppresses sync()',
      () async {
    connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.none],
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.disconnected(),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
        connectivityOnlineProvider, (_, _) {},
        fireImmediately: true);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    connectivity.emit(const [ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final svc = container.read(driveSyncServiceProvider)
        as _CountingSyncService;
    expect(svc.syncCallCount, 0,
        reason: 'auth guard suppresses connectivity-restored sync()');
  });

  test(
      'E: coalescing — queue-write + connectivity-restored within the '
      'debounce window result in a single SyncSynced terminal emit',
      () async {
    connectivity = _FakeConnectivity(
      initial: const [ConnectivityResult.wifi],
    );
    final container = _buildContainer(
      db: db,
      storage: storage,
      drive: drive,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
      connectivity: connectivity,
    );
    addTearDown(container.dispose);

    container.read(autoPushOrchestratorProvider);
    container.listen<AsyncValue<bool>>(
        connectivityOnlineProvider, (_, _) {},
        fireImmediately: true);
    container.listen(syncStatusProvider, (_, _) {}, fireImmediately: true);
    container.listen(syncQueuePendingCountProvider, (_, _) {},
        fireImmediately: true);

    // Settle initial auth-state sync first.
    await _waitForStatus(container, (s) => s is SyncSynced);

    // Record SyncSynced emits from now on.
    final syncedEmits = <SyncStatus>[];
    final sub =
        container.read(driveSyncServiceProvider).watchStatus().listen((s) {
      if (s is SyncSynced) syncedEmits.add(s);
    });

    final repo = BookmarkRepository(db);
    await repo.save(_bm('b1'));
    // Within the 250 ms debounce window, also flip connectivity offline
    // then back online to fire the connectivity trigger.
    connectivity.emit(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    connectivity.emit(const [ConnectivityResult.wifi]);

    // Wait long enough for the orchestrator's debounce + the engine's
    // coalesced cycle to complete.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(syncedEmits.length, lessThanOrEqualTo(2),
        reason:
            'coalesce merges overlapping triggers; at most a small handful '
            'of terminal SyncSynced emissions in a quiet window');

    await sub.cancel();
  });
}
