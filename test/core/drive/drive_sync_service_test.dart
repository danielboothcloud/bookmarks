import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_credentials_store.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_snapshot_builder.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
import 'package:bookmarks/core/drive/merge_applier.dart';
import 'package:bookmarks/core/drive/models/drive_bookmarks_file.dart';
import 'package:bookmarks/core/drive/sync_status.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pull the base64-encoded media block out of a Drive multipart upload
/// body. The multipart layout: the second part has a
/// `Content-Transfer-Encoding: base64` header followed by a blank line
/// and then the base64 payload terminated by `--<boundary>--`.
/// Mirrors `_extractBase64Body` in drive_file_service_test.dart.
String _decodeUploadedJson(String multipart) {
  final match = RegExp(
    r'Content-Transfer-Encoding: base64\r?\n\r?\n([^\r\n-]+)',
  ).firstMatch(multipart);
  if (match == null) {
    // Fallback for raw bodies (e.g. when MockClient passes media directly).
    return multipart;
  }
  return utf8.decode(base64.decode(match.group(1)!.trim()));
}

class _InMemorySecureStorage implements FlutterSecureStorage {
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

void _seedCreds(_InMemorySecureStorage storage) {
  storage.store[DriveStorageKeys.accessToken] = 'access-x';
  storage.store[DriveStorageKeys.refreshToken] = 'refresh-x';
  storage.store[DriveStorageKeys.expiresAt] =
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
}

/// Simulates a Drive API server. Records every request and returns
/// scripted responses in order. Defaults to a 200 for unknown calls.
class _FakeDriveServer {
  _FakeDriveServer({String? initialRemoteJson}) {
    if (initialRemoteJson != null) {
      _remoteContent = initialRemoteJson;
    } else {
      _remoteContent = jsonEncode({
        'version': 1,
        'lastModified': DateTime.now().toUtc().toIso8601String(),
        'bookmarks': <Object>[],
        'folders': <Object>[],
        'tags': <Object>[],
      });
    }
  }

  late String _remoteContent;
  String get remoteContent => _remoteContent;
  set remoteContent(String value) => _remoteContent = value;

  final List<http.Request> updateRequests = <http.Request>[];
  final List<http.Request> getRequests = <http.Request>[];

  /// FIFO of update responses. null entry means "200 success".
  final List<http.Response Function()> updateScript = [];

  http.Client buildClient() {
    return MockClient.streaming((request, bodyStream) async {
      final url = request.url;

      // PATCH-style upload: PATCH /upload/drive/v3/files/{fileId}?uploadType=media
      if (url.path.startsWith('/upload/drive/v3/files/')) {
        // Read body so the snapshot bytes are observable.
        final bytes = await bodyStream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        final body = utf8.decode(bytes);
        updateRequests.add(http.Request(request.method, url)..body = body);

        if (updateScript.isNotEmpty) {
          final response = updateScript.removeAt(0)();
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(response.body)),
            response.statusCode,
            headers: response.headers,
          );
        }
        // Default success: persist the body, return 200 with file metadata.
        _remoteContent = body;
        final ok = jsonEncode({'id': 'file-id-1', 'name': 'bookmarks.json'});
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(ok)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      // files.get media download (any GET on /drive/v3/files/<id> that
      // carries `alt=media` either as query param or in the request).
      if (request.method == 'GET' &&
          url.path.startsWith('/drive/v3/files/')) {
        getRequests.add(http.Request(request.method, url));
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(_remoteContent)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }

      // Default empty 200 to keep the auth client happy.
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{}')),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
  }
}

/// Fake Drive server whose GET (probe) responses are scripted by HTTP
/// status code. Each probe attempt consumes the next entry in
/// [probeStatuses]; once exhausted, falls back to 200 with the empty v1
/// envelope. PATCH (upload) calls default to 200 with file metadata.
class _ProbingFakeServer {
  _ProbingFakeServer({required this.probeStatuses});

  final List<int> probeStatuses;
  int probeGetCount = 0;

  static final String _emptyEnvelope = jsonEncode({
    'version': 1,
    'lastModified': '2026-05-20T00:00:00.000Z',
    'bookmarks': <Object>[],
    'folders': <Object>[],
    'tags': <Object>[],
  });

  http.Client buildClient() {
    return MockClient.streaming((request, bodyStream) async {
      final url = request.url;
      if (request.method == 'GET' &&
          url.path.startsWith('/drive/v3/files/')) {
        probeGetCount++;
        final status =
            probeStatuses.isNotEmpty ? probeStatuses.removeAt(0) : 200;
        // googleapis parses application/json bodies on non-2xx into
        // DetailedApiRequestError; with malformed JSON the decoder
        // throws FormatException which DriveRetryPolicy does NOT
        // classify as transient. Wrap the error body as valid JSON so
        // the 500/503 path lands on DetailedApiRequestError(status).
        final body = status == 200
            ? _emptyEnvelope
            : jsonEncode({
                'error': {'code': status, 'message': 'transient'},
              });
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(body)),
          status,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (url.path.startsWith('/upload/drive/v3/files/')) {
        await bodyStream
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
        return http.StreamedResponse(
          Stream<List<int>>.value(
              utf8.encode('{"id":"file-1","name":"bookmarks.json"}')),
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
}

/// Test retry policy with near-zero delays so retry tests don't take seconds.
const _fastRetry = DriveRetryPolicy(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 1),
  maxDelay: Duration(milliseconds: 5),
);

DriveSyncService _buildService({
  required AppDatabase db,
  required _InMemorySecureStorage storage,
  required http.Client client,
  DriveRetryPolicy retryPolicy = _fastRetry,
  DateTime Function()? clock,
}) {
  return DriveSyncService(
    queue: SyncQueueRepository(db),
    snapshotBuilder: DriveSnapshotBuilder(db),
    credentials: DriveCredentialsStore(
      storage: storage,
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
    ),
    storage: storage,
    httpClient: client,
    mergeApplier: MergeApplier(db),
    retryPolicy: retryPolicy,
    clock: clock ?? () => DateTime.utc(2026, 5, 20, 14, 23, 45, 123),
  );
}

Future<void> _seedBookmark(AppDatabase db, String id) async {
  await db.customStatement(
    'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
    'favicon_base64, created_at, updated_at) '
    "VALUES (?, ?, ?, NULL, NULL, NULL, ?, ?)",
    [id, 'https://example.com/$id', 'Title $id', 1, 1],
  );
}

void main() {
  late AppDatabase db;
  late _InMemorySecureStorage storage;
  late _FakeDriveServer server;
  late DriveSyncService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = _InMemorySecureStorage();
    _seedCreds(storage);
    storage.store[kDriveLastPulledAtKey] =
        DateTime.utc(2026, 5, 19).toIso8601String();
    server = _FakeDriveServer();
    service = _buildService(db: db, storage: storage, client: server.buildClient());
  });

  tearDown(() async {
    await service.dispose();
    await db.close();
  });

  test('empty queue + open gate: no upload, emits synced, returns Ok',
      () async {
    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(server.updateRequests, isEmpty);
    // Initial sub may miss the synchronous broadcast; just check no
    // failure / pushing fired.
    expect(statuses, isNot(contains(isA<SyncFailed>())));
    expect(statuses, isNot(contains(isA<SyncPushing>())));

    await sub.cancel();
  });

  test('non-empty queue + open gate: uploads snapshot, drains queue, emits '
      'pushing then synced', () async {
    await _seedBookmark(db, 'b1');
    // The seed insert fires a trigger -> one queue row.
    expect((await SyncQueueRepository(db).drain()), hasLength(1));

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(server.updateRequests, hasLength(1));

    // The body uploaded was a serialized DriveBookmarksFile inside the
    // multipart Drive upload envelope.
    final body = _decodeUploadedJson(server.updateRequests.single.body);
    final parsed = DriveBookmarksFile.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
    expect(parsed.bookmarks, hasLength(1));
    expect(parsed.bookmarks.single.id, 'b1');

    // Queue drained.
    expect(await SyncQueueRepository(db).drain(), isEmpty);

    // Order discipline: pushing must arrive before synced. A regression
    // that flips the order (e.g. emit synced inside _pushInternal before
    // the upload actually completed) would silently slip past a length-
    // only check.
    final pushingIdx = statuses.indexWhere((s) => s is SyncPushing);
    final syncedIdx = statuses.indexWhere((s) => s is SyncSynced);
    expect(pushingIdx, isNonNegative, reason: 'must emit pushing');
    expect(syncedIdx, greaterThan(pushingIdx),
        reason: 'synced must follow pushing, not precede it');

    await sub.cancel();
  });

  test('watchStatus replays the most recent status to a late subscriber',
      () async {
    // H2 regression: broadcast(sync: true) does NOT replay to late
    // subscribers. The service prepends `currentStatus` so the indicator
    // can render "Synced with Drive" on first paint instead of an empty
    // gap. Subscribe BEFORE any push and assert the seed lands.
    final first = await service.watchStatus().first;
    expect(first, isA<SyncIdle>(),
        reason: 'initial subscriber must observe the seed idle state');

    // Drive a push, then attach a NEW subscriber and assert it
    // observes the most-recent state (not nothing).
    await _seedBookmark(db, 'b1');
    await service.push(fileId: 'file-id-1');
    final late = await service.watchStatus().first;
    expect(late, isA<SyncSynced>(),
        reason: 'late subscriber must observe the most-recent emit');
  });

  test('push() drains only the IDs captured at drain start — rows that '
      'arrive between drain and upload survive into the next cycle',
      () async {
    // AC3 step (f): the engine deletes only the originally-captured IDs
    // after upload succeeds. Rows inserted by an arriving mutation after
    // the snapshot was drained must persist for the next push.
    await _seedBookmark(db, 'b1');
    final repo = SyncQueueRepository(db);
    final originalIds = (await repo.drain()).map((r) => r.id).toSet();
    expect(originalIds, hasLength(1));

    // Insert a 2nd queue row WHILE the upload is "in flight" by hooking
    // the fake server's update handler. The synchronous side-effect
    // model: the http call body has been read; before returning 200, the
    // script inserts another sync_queue row. From the engine's point of
    // view this row arrived after drain() and must survive deleteByIds.
    server.updateScript.add(() {
      // Fire-and-forget the insert; the response is returned immediately.
      // The customStatement future will resolve before the engine's
      // deleteByIds runs because both share the same event loop and the
      // insert is sync enough for sqlite.
      // ignore: discarded_futures
      db.customStatement(
        "INSERT INTO sync_queue (operation, entity_type, entity_id, "
        "payload, created_at) VALUES ('upsert', 'bookmark', 'b-mid', "
        'NULL, 9999999)',
      );
      return http.Response('{"id":"f1"}', 200,
          headers: const {'content-type': 'application/json'});
    });

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());

    // The originally captured row was deleted; the row inserted during
    // the upload survives.
    final remaining = await repo.drain();
    expect(remaining, hasLength(1),
        reason: 'mid-upload insert must survive selective delete');
    expect(remaining.single.entityId, 'b-mid');
  });

  test('Drive returns 500 once then 200: retry, emits synced, queue drained',
      () async {
    await _seedBookmark(db, 'b1');

    server.updateScript.add(() => http.Response('server error', 500));
    // Second call falls through to default 200.

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(server.updateRequests, hasLength(2));
    expect(await SyncQueueRepository(db).drain(), isEmpty);

    await sub.cancel();
  });

  test(
      'Drive returns 500 three times: emits failed, queue NOT drained, returns Err',
      () async {
    await _seedBookmark(db, 'b1');

    server.updateScript.addAll([
      () => http.Response('boom', 500),
      () => http.Response('boom', 500),
      () => http.Response('boom', 500),
    ]);

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Err<void, AppError>>());
    expect(server.updateRequests, hasLength(3));
    expect(await SyncQueueRepository(db).drain(), hasLength(1));
    expect(statuses.whereType<SyncFailed>(), isNotEmpty);

    await sub.cancel();
  });

  test('Drive returns 401: no retry, emits failed', () async {
    await _seedBookmark(db, 'b1');
    server.updateScript.add(() => http.Response('unauthorized', 401));

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Err<void, AppError>>());
    // 401 propagates immediately -- one attempt only.
    expect(server.updateRequests, hasLength(1));
    expect(statuses.whereType<SyncFailed>(), isNotEmpty);

    await sub.cancel();
  });

  test('concurrent push() calls: second awaits first; exactly one upload',
      () async {
    await _seedBookmark(db, 'b1');

    // Don't await -- fire both effectively in parallel.
    final r1 = service.push(fileId: 'file-id-1');
    final r2 = service.push(fileId: 'file-id-1');

    final results = await Future.wait([r1, r2]);
    expect(results.every((r) => r is Ok<void, AppError>), isTrue);
    expect(server.updateRequests, hasLength(1),
        reason: 'second call should have awaited the first, not retriggered');
  });

  test('first-connect probe with empty remote: opens gate, returns true via push',
      () async {
    storage.store.remove(kDriveLastPulledAtKey);
    expect(storage.store.containsKey(kDriveLastPulledAtKey), isFalse);

    await _seedBookmark(db, 'b1');
    final result = await service.push(fileId: 'file-id-1');

    expect(result, isA<Ok<void, AppError>>());
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);
    expect(server.updateRequests, hasLength(1),
        reason: 'gate opened -> push proceeds');
  });

  test('first-connect probe with non-empty remote: leaves gate closed, emits '
      'awaitingInitialPull, no upload', () async {
    storage.store.remove(kDriveLastPulledAtKey);
    server.remoteContent = jsonEncode({
      'version': 1,
      'lastModified': '2026-05-15T10:00:00.000Z',
      'bookmarks': [
        {
          'id': 'remote-b1',
          'url': 'https://other-device.com',
          'title': 'Other device bookmark',
          'tagIds': <String>[],
          'createdAt': '2026-05-15T10:00:00.000Z',
          'updatedAt': '2026-05-15T10:00:00.000Z',
        },
      ],
      'folders': <Object>[],
      'tags': <Object>[],
    });

    await _seedBookmark(db, 'b1');

    final statuses = <SyncStatus>[];
    final sub = service.watchStatus().listen(statuses.add);

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Err<void, AppError>>());
    expect(storage.store.containsKey(kDriveLastPulledAtKey), isFalse);
    expect(server.updateRequests, isEmpty);
    expect(statuses.whereType<SyncAwaitingInitialPull>(), isNotEmpty);

    await sub.cancel();
  });

  test('first-connect probe upload failure leaves gate closed and the next '
      'push retries the probe', () async {
    // Task 10 bullet 7: probe transient failure must not half-set the
    // gate, and the next push must re-attempt the probe (not pass it
    // through as already-checked).
    storage.store.remove(kDriveLastPulledAtKey);

    // First call: probe GET returns 500 three times -> retry exhausts ->
    // mapped to NetworkError. The fake server's `getRequests` records
    // the attempts so we can count probe re-attempts on the next push.
    // Build a server whose probe responses are scripted.
    final probeServer = _ProbingFakeServer(
      probeStatuses: [500, 500, 500, 200],
    );
    final probeService = _buildService(
      db: db,
      storage: storage,
      client: probeServer.buildClient(),
    );
    addTearDown(probeService.dispose);

    final first = await probeService.push(fileId: 'file-id-1');
    expect(first, isA<Err<void, AppError>>(),
        reason: 'probe retry-exhausted should bubble up as Err');
    expect(storage.store.containsKey(kDriveLastPulledAtKey), isFalse,
        reason: 'gate must stay closed when the probe fails');
    expect(probeServer.probeGetCount, 3,
        reason: 'retry policy fires 3 attempts on transient failure');

    // Second push: probe is re-attempted (not skipped). The 4th scripted
    // response is 200 with an empty envelope, so the probe opens the
    // gate and a push proceeds.
    await _seedBookmark(db, 'b1');
    final second = await probeService.push(fileId: 'file-id-1');
    expect(second, isA<Ok<void, AppError>>(),
        reason: 'next push re-probes and, with a 200, proceeds');
    expect(storage.store[kDriveLastPulledAtKey], isNotNull);
    expect(probeServer.probeGetCount, 4,
        reason: 'one additional probe attempt landed on the next push');
  });

  test('mid-upload stream EOF is treated as transient: retry succeeds and '
      'synced is emitted only after the retry succeeds', () async {
    // Task 10 bullet 10: a mid-upload SocketException-equivalent EOF
    // must NOT leak a premature synced emit; the engine emits pushing
    // once, retries inside DriveRetryPolicy, and only emits synced when
    // the retry's 200 response lands.
    await _seedBookmark(db, 'b1');

    var attempt = 0;
    final eofServer = _FakeDriveServer();
    eofServer.updateScript.add(() {
      attempt++;
      // Simulate mid-stream EOF as a thrown SocketException — the
      // retry policy classifies SocketException as transient.
      throw const SocketException('mid-upload EOF');
    });
    // Second attempt: default 200 fall-through.

    final eofService = _buildService(
      db: db,
      storage: storage,
      client: eofServer.buildClient(),
    );
    addTearDown(eofService.dispose);

    final statuses = <SyncStatus>[];
    final sub = eofService.watchStatus().listen(statuses.add);

    final result = await eofService.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(attempt, 1, reason: 'first attempt threw');
    expect(eofServer.updateRequests, hasLength(2),
        reason: 'retry produced a second wire-level attempt');

    // One pushing emit. Exactly one synced emit, AFTER pushing, AFTER
    // the second-attempt response.
    expect(statuses.whereType<SyncPushing>(), hasLength(1));
    expect(statuses.whereType<SyncSynced>(), hasLength(1));
    expect(statuses.whereType<SyncFailed>(), isEmpty,
        reason: 'transient retry must not leak failed mid-flight');

    await sub.cancel();
  });

  test('empty local DB + queue with delete-only rows still produces a valid '
      'empty snapshot upload', () async {
    // Adversarial edge: user deleted their last bookmark, queue has a
    // delete row, local DB is empty. Snapshot should be the empty
    // envelope; upload should succeed; queue should drain.
    final repo = SyncQueueRepository(db);
    // Manually seed a delete row without an underlying bookmark.
    await db.customStatement(
      "INSERT INTO sync_queue (operation, entity_type, entity_id, payload, "
      "created_at) VALUES ('delete', 'bookmark', 'bm-gone', NULL, 1)",
    );

    final result = await service.push(fileId: 'file-id-1');
    expect(result, isA<Ok<void, AppError>>());
    expect(server.updateRequests, hasLength(1));
    final body = _decodeUploadedJson(server.updateRequests.single.body);
    final parsed = DriveBookmarksFile.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
    expect(parsed.bookmarks, isEmpty);
    expect(await repo.drain(), isEmpty);
  });
}
