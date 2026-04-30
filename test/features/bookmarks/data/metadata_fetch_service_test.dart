import 'dart:convert';
import 'dart:typed_data';

import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal HTML helper -- gives us a parseable document with a <title>.
String _htmlWithTitle(String title) =>
    '<!DOCTYPE html><html><head><title>$title</title></head><body></body></html>';

const _emptyHtml =
    '<!DOCTYPE html><html><head></head><body></body></html>';

/// 1x1 transparent PNG (smallest legal PNG; mime can be inferred).
final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=',
);

/// 1x1 ICO bytes - structurally valid enough for our purposes (we only base64).
final _tinyIcoBytes = Uint8List.fromList(
  List<int>.generate(64, (i) => i & 0xFF),
);

void main() {
  group('MetadataFetchService.fetch', () {
    test('returns title from <title> tag on happy path', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response.bytes(_tinyIcoBytes, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        return http.Response(_htmlWithTitle('Example Domain'), 200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.title, 'Example Domain');
    });

    test('returns null title when document has no <title>', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_emptyHtml, 200,
            headers: {'content-type': 'text/html'});
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.title, isNull);
      expect(result.faviconBase64, isNull);
    });

    test('favicon.ico 200 returns base64 data URI', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response.bytes(_tinyIcoBytes, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        return http.Response(_htmlWithTitle('T'), 200);
      });
      final service = MetadataFetchService(client: client);

      final favicon =
          (await service.fetch('https://example.com')).faviconBase64;

      expect(favicon, isNotNull);
      expect(favicon, startsWith('data:image/x-icon;base64,'));
      expect(favicon, contains(base64Encode(_tinyIcoBytes)));
    });

    test('favicon.ico 404 falls back to apple-touch-icon.png', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response.bytes(_tinyPngBytes, 200,
              headers: {'content-type': 'image/png'});
        }
        return http.Response(_htmlWithTitle('T'), 200);
      });
      final service = MetadataFetchService(client: client);

      final favicon =
          (await service.fetch('https://example.com')).faviconBase64;

      expect(favicon, isNotNull);
      expect(favicon, startsWith('data:image/png;base64,'));
    });

    test('both favicon paths fail -> faviconBase64 null (success-with-null)',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 500);
        }
        return http.Response(_htmlWithTitle('T'), 200);
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.faviconBase64, isNull);
    });

    test('slow page response triggers timeout -> success with both null',
        () async {
      // The service uses a real 8s timeout. To exercise the timeout path
      // deterministically without sleeping, override the timeout via the test
      // constructor.
      final client = MockClient((request) async {
        // Hang forever -- the timeout should kick in.
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('never', 200);
      });
      final service = MetadataFetchService(
        client: client,
        timeout: const Duration(milliseconds: 50),
      );

      final result = await service.fetch('https://example.com');

      expect(result.title, isNull);
      expect(result.faviconBase64, isNull);
    });

    test('oversized favicon (>64KB) is rejected', () async {
      final big = Uint8List(65 * 1024);
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response.bytes(big, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('T'), 200);
      });
      final service = MetadataFetchService(client: client);

      final favicon =
          (await service.fetch('https://example.com')).faviconBase64;

      expect(favicon, isNull);
    });

    test('oversized HTML body (>2MB declared content-length) is rejected',
        () async {
      // The service caps the title fetch at 2MB. Servers that advertise a
      // larger Content-Length must be short-circuited before the stream runs.
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('massive'), 200, headers: {
          'content-type': 'text/html',
          'content-length': '${10 * 1024 * 1024}', // 10MB advertised
        });
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.title, isNull,
          reason: 'declared content-length over cap should short-circuit');
    });

    test('malformed URL returns success with both null (no throw)', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        return http.Response('', 200);
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('not a url');

      expect(result.title, isNull);
      expect(result.faviconBase64, isNull);
      expect(calls, 0, reason: 'malformed URL must short-circuit before HTTP');
    });

    test('non-http(s) scheme is rejected without HTTP calls (M1)', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        return http.Response('', 200);
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('ftp://example.com/file');

      expect(result.title, isNull);
      expect(result.faviconBase64, isNull);
      expect(calls, 0, reason: 'ftp:// must be rejected before any HTTP call');
    });

    test('empty title strings are normalised to null', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('   '), 200,
            headers: {'content-type': 'text/html'});
      });
      final service = MetadataFetchService(client: client);

      expect((await service.fetch('https://example.com')).title, isNull);
    });
  });
}
