import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/drive_auth_providers.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_auth_state.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_sync_providers.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/features/import/application/import_providers.dart';
import 'package:bookmarks/features/import/data/file_picker_wrapper.dart';
import 'package:bookmarks/features/import/domain/import_failure_reason.dart';
import 'package:bookmarks/features/import/domain/import_state.dart';
import 'package:bookmarks/features/search/application/search_providers.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _InMemoryStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      store[key];
  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
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

/// Minimal copy of the `_FakeDriveServer` from
/// `sync_indicator_flow_test.dart`. Epic 4 retro T1 calls for a shared
/// `test/helpers/fake_drive.dart` — when that lands, this block can
/// move there.
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
  final List<http.Request> uploads = <http.Request>[];

  http.Client buildClient() => MockClient.streaming((request, bodyStream) async {
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

ProviderContainer _container({
  required AppDatabase db,
  required String? pickedPath,
  _FakeDriveServer? drive,
  _InMemoryStorage? storage,
  DriveAuthState auth = const DriveAuthState.disconnected(),
}) {
  final overrides = [
    appDatabaseProvider.overrideWithValue(db),
    filePickerProvider.overrideWithValue(
      FilePickerWrapper.fake(() => pickedPath),
    ),
    if (drive != null) ...[
      if (storage != null)
        flutterSecureStorageProvider.overrideWithValue(storage),
      httpClientProvider.overrideWithValue(drive.buildClient()),
      driveAuthStateProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      driveSyncServiceProvider.overrideWith((ref) {
        return DriveSyncService(
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
  ];
  return ProviderContainer(overrides: overrides);
}

Future<ImportState> _runImport(ProviderContainer container) async {
  await container.read(importNotifierProvider.future);
  await container.read(importNotifierProvider.notifier).pickAndImport();
  return container.read(importNotifierProvider).value!;
}

Future<void> _waitForStatus(
  ProviderContainer container,
  bool Function(SyncStatus) predicate, {
  Duration timeout = const Duration(seconds: 5),
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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('A: full import flow lands all folders and bookmarks in the DB',
      () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
    );
    addTearDown(container.dispose);

    final state = await _runImport(container);
    expect(state, isA<ImportSucceeded>());

    final folders = await db.select(db.folders).get();
    final bookmarks = await db.select(db.bookmarks).get();
    expect(folders.length, 5,
        reason: 'Bookmarks bar + Dev + Languages + News + Other bookmarks');
    expect(bookmarks.length, 15);

    // No orphans — every folder.parentId resolves to a known folder id.
    final ids = folders.map((f) => f.id).toSet();
    for (final f in folders) {
      if (f.parentId != null) {
        expect(ids.contains(f.parentId), isTrue,
            reason: 'folder ${f.name} parentId must resolve');
      }
    }
    // Imported bookmarks land with faviconBase64 null (AC11; 5.2 fills
    // these in later).
    expect(bookmarks.every((b) => b.faviconBase64 == null), isTrue);
  });

  test('B: invalid file shows calm-error and leaves the DB untouched',
      () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/malformed_bookmarks.html',
    );
    addTearDown(container.dispose);

    final state = await _runImport(container);
    expect(state, isA<ImportFailed>());
    expect((state as ImportFailed).reason, ImportFailureReason.invalidFile);

    final bookmarks = await db.select(db.bookmarks).get();
    final folders = await db.select(db.folders).get();
    expect(bookmarks, isEmpty);
    expect(folders, isEmpty);
  });

  test('C: user cancels file picker — silent return to cancelled state',
      () async {
    final container = _container(db: db, pickedPath: null);
    addTearDown(container.dispose);

    final state = await _runImport(container);
    expect(state, isA<ImportFailed>());
    expect((state as ImportFailed).reason, ImportFailureReason.userCancelled);

    // Nothing was written; nothing was even attempted.
    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks, isEmpty);
  });

  test('D: 500-bookmark import stays responsive (NFR5) — '
      'multiple progress emits + under 5s', () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/large_bookmarks.html',
    );
    addTearDown(container.dispose);

    await container.read(importNotifierProvider.future);
    final writingProgress = <int>[];
    container.listen(importNotifierProvider, (_, next) {
      final v = next.value;
      if (v is ImportWriting) writingProgress.add(v.progress.itemsWritten);
    });

    final stopwatch = Stopwatch()..start();
    await container.read(importNotifierProvider.notifier).pickAndImport();
    stopwatch.stop();

    expect(writingProgress.length, greaterThanOrEqualTo(5),
        reason: 'frame yields fire at least 5 progress updates');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'NFR5 — 500-bookmark import must complete under 5s');
    expect(writingProgress.last, 531,
        reason: '31 folders + 500 bookmarks = 531 total writes');

    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks.length, 500);
  });

  test('E: import-then-sync coalesces 500 writes into ≤ 2 push cycles',
      () async {
    final storage = _InMemoryStorage()..store;
    _seedCreds(storage);
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    final drive = _FakeDriveServer();

    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/large_bookmarks.html',
      drive: drive,
      storage: storage,
      auth: const DriveAuthState.connected(
        email: 'x@y.com',
        fileId: 'file-1',
      ),
    );
    addTearDown(container.dispose);

    // Boot the orchestrator + keep the StreamProviders subscribed for
    // the duration of the test.
    container.read(autoPushOrchestratorProvider);
    container.listen(syncQueuePendingCountProvider, (_, __) {},
        fireImmediately: true);
    container.listen(syncStatusProvider, (_, __) {}, fireImmediately: true);
    container.listen(hasEverSyncedProvider, (_, __) {},
        fireImmediately: true);

    final state = await _runImport(container);
    expect(state, isA<ImportSucceeded>());

    // Wait for the sync engine to settle. Per Story 4.5 Surprise #5,
    // the orchestrator may emit a follow-up cycle if a queue write
    // lands during the first cycle's tail — both terminate at
    // SyncSynced. We assert <= 2 cycles total.
    await _waitForStatus(container, (s) => s is SyncSynced,
        timeout: const Duration(seconds: 10));
    // Give the orchestrator a debounce window to absorb a possible
    // follow-up cycle, then snapshot the upload count.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(drive.uploads.length, lessThanOrEqualTo(2),
        reason: 'queue-debounce must coalesce 500 writes into ≤ 2 pushes');
    expect(drive.uploads.length, greaterThanOrEqualTo(1),
        reason: 'at least one push must have occurred');
  });

  test('F: imported bookmarks are immediately searchable via FTS',
      () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
    );
    addTearDown(container.dispose);

    final state = await _runImport(container);
    expect(state, isA<ImportSucceeded>());

    // Search for one of the imported bookmark titles — Hacker News is
    // inside the News folder in the Chrome fixture.
    final results = await container
        .read(searchRepositoryProvider)
        .search('Hacker')
        .first;
    expect(results, isNotEmpty,
        reason: 'FTS triggers fired on every bookmark insert');
    expect(results.any((b) => b.url == 'https://news.ycombinator.com'),
        isTrue);
  });
}
