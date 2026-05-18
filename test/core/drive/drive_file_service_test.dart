import 'dart:convert';

import 'package:bookmarks/core/drive/drive_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // A zero-delay, zero-retry policy keeps unit tests fast; the retry
  // behaviour itself is covered by the dedicated `DriveRetryPolicy`
  // group below.
  const noRetry = DriveRetryPolicy(
    maxAttempts: 1,
    initialDelay: Duration.zero,
    maxDelay: Duration.zero,
  );

  group('DriveFileService.ensureBookmarksFile', () {
    test('returns existing file id when one match', () async {
      late http.Request lastList;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/files') && req.method == 'GET') {
          lastList = req as http.Request;
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'existing-1', 'modifiedTime': '2026-05-10T12:00:00Z'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${req.method} ${req.url}');
      });

      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      final id = await svc.ensureBookmarksFile(accessToken: 'token-abc');

      expect(id, 'existing-1');
      expect(lastList.headers['Authorization'], 'Bearer token-abc');
      expect(lastList.url.queryParameters['spaces'], 'appDataFolder');
      expect(lastList.url.queryParameters['q'], "name = 'bookmarks.json'");
      expect(lastList.url.queryParameters['orderBy'], 'modifiedTime desc');
      // The Drive client uses '$fields' (alt name 'fields') — accept either.
      final fields =
          lastList.url.queryParameters['fields'] ?? lastList.url.queryParameters[r'$fields'];
      expect(fields, 'files(id, modifiedTime)');
    });

    test('returns most-recently-modified id when multiple matches', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'newer', 'modifiedTime': '2026-05-11T08:00:00Z'},
                {'id': 'older', 'modifiedTime': '2026-05-10T08:00:00Z'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request');
      });

      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      final id = await svc.ensureBookmarksFile(accessToken: 'token');
      expect(id, 'newer');
    });

    test('creates an empty file when no match', () async {
      String? createdBody;
      int listCount = 0;
      int createCount = 0;

      final client = MockClient((req) async {
        if (req.method == 'GET') {
          listCount++;
          return http.Response(jsonEncode({'files': []}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.method == 'POST') {
          createCount++;
          createdBody = req.body;
          return http.Response(
            jsonEncode({'id': 'created-1'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${req.method} ${req.url}');
      });

      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      final id = await svc.ensureBookmarksFile(accessToken: 'token');

      expect(id, 'created-1');
      expect(listCount, 1);
      expect(createCount, 1);
      // Drive multipart upload: metadata as JSON + base64-encoded media.
      expect(createdBody, contains('"name":"bookmarks.json"'));
      expect(createdBody, contains('"parents":["appDataFolder"]'));
      // Decode the base64 media block to validate the JSON shape.
      final mediaB64 = _extractBase64Body(createdBody!);
      final media = utf8.decode(base64.decode(mediaB64));
      expect(media, contains('"version":1'));
      expect(media, contains('"bookmarks":[]'));
      expect(media, contains('"folders":[]'));
      expect(media, contains('"tags":[]'));
      expect(media, contains('"lastModified"'));
    });

    test('throws on 5xx from files.list', () async {
      final client = MockClient(
        (req) async => http.Response('boom', 503),
      );
      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      await expectLater(
        svc.ensureBookmarksFile(accessToken: 't'),
        throwsA(anything),
      );
    });

    test('throws on 401 from files.list', () async {
      final client = MockClient(
        (req) async => http.Response('nope', 401),
      );
      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      await expectLater(
        svc.ensureBookmarksFile(accessToken: 't'),
        throwsA(anything),
      );
    });

    test('bearer header is present on the create call too', () async {
      final headersSeen = <String?>[];
      final client = MockClient((req) async {
        headersSeen.add(req.headers['Authorization']);
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({'files': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'id': 'created-2'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = DriveFileService(httpClient: client, retryPolicy: noRetry);
      await svc.ensureBookmarksFile(accessToken: 'tok');
      expect(headersSeen, isNotEmpty);
      for (final h in headersSeen) {
        expect(h, 'Bearer tok');
      }
    });

    test('retries transient 5xx on files.list, succeeds on attempt 3',
        () async {
      var listAttempt = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          listAttempt++;
          if (listAttempt < 3) return http.Response('boom', 503);
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'eventually', 'modifiedTime': '2026-05-11T08:00:00Z'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected ${req.method}');
      });
      // Zero-delay retry policy so the test runs in milliseconds.
      final svc = DriveFileService(
        httpClient: client,
        retryPolicy: const DriveRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );
      final id = await svc.ensureBookmarksFile(accessToken: 't');
      expect(id, 'eventually');
      expect(listAttempt, 3);
    });

    test('does NOT retry on 401 (caller needs to re-auth)', () async {
      var attempts = 0;
      final client = MockClient((req) async {
        attempts++;
        return http.Response('nope', 401);
      });
      final svc = DriveFileService(
        httpClient: client,
        retryPolicy: const DriveRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );
      await expectLater(
        svc.ensureBookmarksFile(accessToken: 't'),
        throwsA(anything),
      );
      expect(attempts, 1, reason: '401 must propagate without retry');
    });

    test('lastModified in the created body is ISO-8601 UTC', () async {
      String? body;
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({'files': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        body = req.body;
        return http.Response(
          jsonEncode({'id': 'c'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await DriveFileService(httpClient: client, retryPolicy: noRetry)
          .ensureBookmarksFile(accessToken: 't');
      final media = utf8.decode(base64.decode(_extractBase64Body(body!)));
      final match = RegExp(r'"lastModified":"([^"]+)"').firstMatch(media);
      expect(match, isNotNull);
      final ts = match!.group(1)!;
      expect(ts.endsWith('Z'), isTrue, reason: 'expected UTC ISO 8601');
      expect(() => DateTime.parse(ts), returnsNormally);
    });
  });
}

/// Pull the base64-encoded media block out of a Drive multipart upload
/// body. The multipart layout (per googleapis): the second part has a
/// `Content-Transfer-Encoding: base64` header followed by a blank line
/// and then the base64 payload terminated by `--<boundary>--`.
String _extractBase64Body(String multipart) {
  final match = RegExp(
    r'Content-Transfer-Encoding: base64\r?\n\r?\n([^\r\n-]+)',
  ).firstMatch(multipart);
  if (match == null) {
    throw StateError('No base64 part found in multipart body');
  }
  return match.group(1)!;
}
