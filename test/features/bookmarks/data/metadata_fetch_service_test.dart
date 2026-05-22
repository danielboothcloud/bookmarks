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

    test(
        'all favicon requests carry a Safari-shaped User-Agent (defeats '
        'default-Dart-UA WAF blocks)', () async {
      final seenUserAgents = <String>{};
      final client = MockClient((request) async {
        seenUserAgents.add(request.headers['user-agent'] ?? '');
        if (request.url.path == '/favicon.ico') {
          return http.Response.bytes(_tinyIcoBytes, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        if (request.url.path == '/favicon.svg') {
          return http.Response('', 404);
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('T'), 200,
            headers: {'content-type': 'text/html'});
      });
      final service = MetadataFetchService(client: client);

      await service.fetch('https://example.com');

      expect(seenUserAgents, isNot(contains('')),
          reason: 'every request must carry a UA header');
      // Sanity-check the shape (Mozilla prefix + Bookmarks identifier).
      for (final ua in seenUserAgents) {
        expect(ua, startsWith('Mozilla/5.0'),
            reason: 'UA must be browser-shaped to defeat WAFs');
        expect(ua, contains('Bookmarks/'),
            reason: 'UA must identify us so server logs can attribute');
      }
    });

    test(
        'HTML-declared favicon (<link rel="icon">) is fetched and preferred '
        'over the static /favicon.ico fallback', () async {
      // Site declares a versioned favicon in <head>. The static
      // /favicon.ico still exists but serves a DIFFERENT image
      // (sometimes a stale or 1x1 transparent). Declared wins.
      const declaredBytes = [1, 2, 3, 4, 5, 6, 7, 8];
      final client = MockClient((request) async {
        if (request.url.path == '/static/favicon-v3.png') {
          return http.Response.bytes(declaredBytes, 200,
              headers: {'content-type': 'image/png'});
        }
        if (request.url.path == '/favicon.ico' ||
            request.url.path == '/favicon.svg' ||
            request.url.path == '/apple-touch-icon.png') {
          return http.Response.bytes(_tinyIcoBytes, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        return http.Response(
          '<!DOCTYPE html><html><head>'
          '<title>Hello</title>'
          '<link rel="icon" type="image/png" href="/static/favicon-v3.png">'
          '</head><body></body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.title, 'Hello');
      expect(result.faviconBase64, startsWith('data:image/png;base64,'));
      expect(result.faviconBase64, contains(base64Encode(declaredBytes)),
          reason: 'declared icon must win over the static fallback');
    });

    test('<link rel="shortcut icon"> is recognised as a declared icon',
        () async {
      // Legacy IE-era declaration; many older sites still use it.
      const declaredBytes = [9, 9, 9, 9, 9, 9, 9, 9, 9];
      final client = MockClient((request) async {
        if (request.url.path == '/legacy-shortcut.ico') {
          return http.Response.bytes(declaredBytes, 200,
              headers: {'content-type': 'image/x-icon'});
        }
        if (request.url.path == '/favicon.ico' ||
            request.url.path == '/favicon.svg' ||
            request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(
          '<!DOCTYPE html><html><head>'
          '<title>T</title>'
          '<link rel="shortcut icon" href="/legacy-shortcut.ico">'
          '</head><body></body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.faviconBase64, contains(base64Encode(declaredBytes)));
    });

    test(
        'relative href in <link rel="icon"> is resolved against the page URL',
        () async {
      const declaredBytes = [7, 7, 7, 7];
      final client = MockClient((request) async {
        if (request.url.path == '/blog/icons/favicon.png') {
          return http.Response.bytes(declaredBytes, 200,
              headers: {'content-type': 'image/png'});
        }
        if (request.url.path == '/favicon.ico' ||
            request.url.path == '/favicon.svg' ||
            request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(
          '<!DOCTYPE html><html><head>'
          '<link rel="icon" href="icons/favicon.png">'
          '</head><body></body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com/blog/post-1');

      expect(result.faviconBase64, contains(base64Encode(declaredBytes)));
    });

    test('static /favicon.svg success returns image/svg+xml data URI',
        () async {
      const svgBytes = [
        0x3C, 0x73, 0x76, 0x67, 0x20, 0x78, 0x6D, 0x6C, 0x6E, 0x73,
        0x3D, 0x22, 0x68, 0x74, 0x74, 0x70, // <svg xmlns="http
      ];
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('', 404);
        }
        if (request.url.path == '/favicon.svg') {
          return http.Response.bytes(svgBytes, 200,
              headers: {'content-type': 'image/svg+xml'});
        }
        if (request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('T'), 200,
            headers: {'content-type': 'text/html'});
      });
      final service = MetadataFetchService(client: client);

      final favicon =
          (await service.fetch('https://example.com')).faviconBase64;
      expect(favicon, startsWith('data:image/svg+xml;base64,'));
    });

    test(
        'soft-404 returning HTML body at a favicon URL is rejected (no '
        'content-type, magic-byte sniff catches it)', () async {
      // Pathological server: returns 200 with the homepage HTML for any
      // unknown path, no content-type header. Without the HTML
      // magic-byte sniff, the bytes would be base64-encoded as if they
      // were a favicon.
      final client = MockClient((request) async {
        if (request.url.path == '/' || request.url.path.endsWith('.png') ||
            request.url.path.endsWith('.ico') ||
            request.url.path.endsWith('.svg')) {
          // No content-type header — mimicking the misconfigured-server case.
          return http.Response(
            '<!DOCTYPE html><html><head><title>T</title></head>'
            '<body>soft 404</body></html>',
            200,
          );
        }
        return http.Response('', 404);
      });
      final service = MetadataFetchService(client: client);

      final result = await service.fetch('https://example.com');

      expect(result.faviconBase64, isNull,
          reason: 'magic-byte HTML sniff must reject the soft-404 body');
    });

    test(
        'content-type text/html on /favicon.ico is rejected (explicit '
        'non-image content-type)', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/favicon.ico') {
          return http.Response('<html>nope</html>', 200,
              headers: {'content-type': 'text/html'});
        }
        if (request.url.path == '/favicon.svg' ||
            request.url.path == '/apple-touch-icon.png') {
          return http.Response('', 404);
        }
        return http.Response(_htmlWithTitle('T'), 200,
            headers: {'content-type': 'text/html'});
      });
      final service = MetadataFetchService(client: client);

      expect(
          (await service.fetch('https://example.com')).faviconBase64, isNull);
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
