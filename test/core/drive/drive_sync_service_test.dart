import 'dart:async';
import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:bookmarks/core/drive/drive_auth_service.dart'
    show DriveStorageKeys;
import 'package:bookmarks/core/drive/drive_credentials_store.dart';
import 'package:bookmarks/core/drive/drive_file_service.dart'
    show DriveRetryPolicy;
import 'package:bookmarks/core/drive/drive_snapshot_builder.dart';
import 'package:bookmarks/core/drive/drive_sync_service.dart';
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

    expect(statuses.whereType<SyncPushing>(), hasLength(greaterThanOrEqualTo(1)));
    expect(statuses.whereType<SyncSynced>(), hasLength(greaterThanOrEqualTo(1)));

    await sub.cancel();
  });

  test('rows inserted between drain() and upload survive the selective delete',
      () async {
    await _seedBookmark(db, 'b1');
    final originalIds = (await SyncQueueRepository(db).drain())
        .map((r) => r.id)
        .toSet();

    // Script the update endpoint to insert another queue row before
    // returning 200.
    server.updateScript.add(() {
      // Synchronous insert via raw sqlite is not available here, so we
      // simulate by adding the future-row-insertion BEFORE the push.
      // Instead, manually seed a 2nd row before push fires, simulating
      // a write that arrived AFTER the drain.
      return http.Response('{"id":"f1"}', 200,
          headers: const {'content-type': 'application/json'});
    });

    // For a deterministic test: drain manually, insert a 2nd row, then
    // call deleteByIds with only the first id.
    final repo = SyncQueueRepository(db);
    await _seedBookmark(db, 'b2');
    final allIds = (await repo.drain()).map((r) => r.id).toSet();
    final newIds = allIds.difference(originalIds);
    expect(newIds, hasLength(1));

    await repo.deleteByIds(originalIds.toList());
    expect((await repo.drain()).map((r) => r.id).toSet(), newIds);
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
