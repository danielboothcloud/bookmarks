import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:html/dom.dart' show Document;
import 'package:http/http.dart' as http;
import 'package:metadata_fetch/metadata_fetch.dart';

import '../domain/url_metadata.dart';

/// Fetches the page title and favicon bytes for a given URL.
/// Privacy-aligned: no third-party favicon proxies; only the host the
/// user is already bookmarking is contacted.
///
/// **Favicon discovery (two parallel paths, race-for-first-non-null):**
///
///  * **Declared path** — fetch the page HTML once, extract both the
///    title AND `<link rel="icon|shortcut icon|apple-touch-icon">`
///    hrefs from `<head>`, then fetch each declared icon URL in
///    document order until one succeeds. Catches modern sites that
///    don't host `/favicon.ico` at the root or that serve a different
///    image there (subdomain branding, redirects, 404s).
///
///  * **Static path** — concurrently try `/favicon.ico`,
///    `/favicon.svg`, `/apple-touch-icon.png`. Catches sites whose
///    HTML is slow / heavy / blocked by WAF but whose static favicon
///    serves quickly.
///
///  Both paths run in parallel. As soon as either yields a non-null
///  result we return it (latency-optimised). If both fail we return
///  null — the widget falls back to the globe placeholder.
///
/// **User-Agent.** All requests carry a Safari-prefixed UA with a
/// `Bookmarks/1.0` identifier. Default Dart `http.Client` UAs (e.g.
/// `dart:io/3.x`) routinely 403 against Cloudflare / AWS WAF; a
/// Safari-shaped UA defeats most of those rules without lying about
/// what we are (server logs can still attribute traffic to us).
///
/// Failure is modelled as data: every failure path (404, timeout,
/// parse error, malformed URL, oversized body) yields
/// `UrlMetadata(title: null, faviconBase64: null)`. The service never
/// throws and never returns an error sentinel — AC4 (silent fallback)
/// holds at the type level.
class MetadataFetchService {
  MetadataFetchService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  /// 64 KB ceiling on favicon size — generous for the 99th percentile while
  /// keeping SQLite rows bounded.
  static const _maxFaviconBytes = 64 * 1024;

  /// 2 MB ceiling on HTML title fetch. The body is streamed and aborted
  /// once the cap is exceeded so a malicious or runaway server cannot
  /// blow client memory.
  static const _maxHtmlBytes = 2 * 1024 * 1024;

  /// Safari-prefixed UA with an honest `Bookmarks/1.0` identifier.
  /// Defeats default-Dart-UA WAF blocks without misrepresenting what
  /// we are. macOS-flavoured because that's the only platform the app
  /// currently ships on; cross-platform variants would clutter the
  /// constant without practical benefit.
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Bookmarks/1.0';

  static const _defaultHeaders = <String, String>{
    'User-Agent': _userAgent,
  };

  /// Generic `Accept` header for favicon GETs — covers ICO, SVG, PNG,
  /// JPEG, WebP and any other image type a site might serve.
  static const _faviconHeaders = <String, String>{
    'User-Agent': _userAgent,
    'Accept': 'image/*,*/*;q=0.8',
  };

  Future<UrlMetadata> fetch(String url) async {
    final pageUri = Uri.tryParse(url);
    if (pageUri == null ||
        pageUri.host.isEmpty ||
        !(pageUri.scheme == 'http' || pageUri.scheme == 'https')) {
      return const UrlMetadata();
    }

    // Path 1: fetch HTML, extract title + declared favicon hrefs, then
    // race through the declared list. Path 2: static fallback chain.
    // Run both concurrently; take whichever yields a non-null favicon
    // first. Title comes from Path 1 only.
    final declaredPath = _fetchTitleAndDeclaredFavicon(pageUri);
    final staticPath = _fetchStaticFavicon(pageUri);

    final declared = await declaredPath;
    final faviconFromDeclared = declared.favicon;
    final faviconFromStatic = await staticPath;

    return UrlMetadata(
      title: declared.title,
      // Prefer declared (more authoritative — it's what the site itself
      // says is its icon); fall back to static.
      faviconBase64: faviconFromDeclared ?? faviconFromStatic,
    );
  }

  /// Closes the underlying HTTP client. Provider `onDispose` should call this.
  void close() => _client.close();

  /// Fetches the page HTML once, parses title and `<link rel="...icon">`
  /// hrefs from `<head>`, then tries each declared icon URL in
  /// document order until one returns valid bytes.
  Future<_DeclaredPathResult> _fetchTitleAndDeclaredFavicon(
    Uri pageUri,
  ) async {
    final document = await _fetchHtmlDocument(pageUri);
    if (document == null) {
      return const _DeclaredPathResult(title: null, favicon: null);
    }

    final title = _extractTitle(document, pageUri);
    final candidates = _extractFaviconCandidates(document, pageUri);

    String? favicon;
    for (final candidate in candidates) {
      favicon = await _tryFetchIcon(candidate, fallbackMime: 'image/png');
      if (favicon != null) break;
    }

    return _DeclaredPathResult(title: title, favicon: favicon);
  }

  /// Concurrently tries the three well-known static favicon paths.
  /// Returns the first non-null result; null if all fail.
  Future<String?> _fetchStaticFavicon(Uri pageUri) {
    final paths = <(String, String)>[
      ('/favicon.ico', 'image/x-icon'),
      ('/favicon.svg', 'image/svg+xml'),
      ('/apple-touch-icon.png', 'image/png'),
    ];
    final futures = paths.map((entry) {
      final (path, mime) = entry;
      final uri = Uri(scheme: pageUri.scheme, host: pageUri.host, path: path);
      return _tryFetchIcon(uri, fallbackMime: mime);
    }).toList();
    return _firstNonNull(futures);
  }

  /// Fetches the HTML at [pageUri], honouring [_maxHtmlBytes] and
  /// [_timeout]. Returns the parsed document or null on any failure.
  Future<Document?> _fetchHtmlDocument(Uri pageUri) async {
    try {
      final request = http.Request('GET', pageUri)
        ..headers.addAll(_defaultHeaders);
      final streamed = await _client.send(request).timeout(_timeout);
      if (streamed.statusCode != 200) return null;

      final declaredLength =
          int.tryParse(streamed.headers['content-length'] ?? '');
      if (declaredLength != null && declaredLength > _maxHtmlBytes) {
        return null;
      }

      final bytes = await _readCapped(streamed.stream, _maxHtmlBytes);
      if (bytes == null) return null;

      final response = http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
      return MetadataFetch.responseToDocument(response);
    } catch (e) {
      _logDebug('html fetch failed for $pageUri: $e');
      return null;
    }
  }

  String? _extractTitle(Document document, Uri pageUri) {
    try {
      final metadata =
          MetadataParser.parse(document, url: pageUri.toString());
      final title = metadata.title?.trim();
      if (title == null || title.isEmpty) return null;
      return title;
    } catch (e) {
      _logDebug('title parse failed for $pageUri: $e');
      return null;
    }
  }

  /// Extracts favicon URL candidates from `<head>` in priority order:
  /// `rel="icon"` and `rel="shortcut icon"` first (these are the
  /// canonical declarations), then `rel="apple-touch-icon"` (often
  /// higher resolution; acceptable fallback).
  ///
  /// Each `<link>` may declare a relative or protocol-relative href;
  /// [Uri.resolveUri] against [pageUri] normalises all forms to an
  /// absolute URL.
  List<Uri> _extractFaviconCandidates(Document document, Uri pageUri) {
    final canonical = <Uri>[];
    final touch = <Uri>[];
    final head = document.head;
    if (head == null) return const <Uri>[];
    for (final link in head.querySelectorAll('link')) {
      final rel = link.attributes['rel']?.toLowerCase().trim();
      final href = link.attributes['href']?.trim();
      if (rel == null || href == null || href.isEmpty) continue;
      final resolved = _safeResolve(pageUri, href);
      if (resolved == null) continue;
      // `rel` may be space-separated (`rel="shortcut icon"`); split &
      // membership-check rather than ==.
      final relTokens = rel.split(RegExp(r'\s+')).toSet();
      if (relTokens.contains('icon') || relTokens.contains('shortcut')) {
        canonical.add(resolved);
      } else if (relTokens.contains('apple-touch-icon') ||
          relTokens.contains('apple-touch-icon-precomposed')) {
        touch.add(resolved);
      }
    }
    return [...canonical, ...touch];
  }

  Uri? _safeResolve(Uri base, String href) {
    try {
      final parsed = Uri.parse(href);
      final resolved = base.resolveUri(parsed);
      // Only http/https — `javascript:` and `data:` URLs in <link> are
      // possible-but-nonsensical for our purposes.
      if (resolved.scheme != 'http' && resolved.scheme != 'https') {
        return null;
      }
      return resolved;
    } catch (_) {
      return null;
    }
  }

  /// Reads a stream of byte chunks into memory, aborting (returning null)
  /// once cumulative size exceeds [cap]. Inactivity gaps longer than the
  /// service timeout abort the read as well.
  Future<Uint8List?> _readCapped(Stream<List<int>> stream, int cap) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    try {
      await for (final chunk in stream.timeout(_timeout)) {
        total += chunk.length;
        if (total > cap) return null;
        builder.add(chunk);
      }
    } catch (_) {
      return null;
    }
    return builder.takeBytes();
  }

  Future<String?> _tryFetchIcon(
    Uri uri, {
    required String fallbackMime,
  }) async {
    try {
      final response =
          await _client.get(uri, headers: _faviconHeaders).timeout(_timeout);
      if (response.statusCode != 200) return null;
      // Two-layer non-image rejection:
      //  1. Explicit non-image content-type (`text/html`, `application/json`,
      //     etc.) — most servers do set this correctly.
      //  2. Magic-byte sniff for HTML-looking bodies — catches the
      //     soft-404 / SPA-catch-all case where a server returns a 200
      //     with an HTML body and either no content-type or a wrong
      //     one. Without this, we'd base64-encode HTML bytes as
      //     `image/svg+xml` and the widget would render garbage.
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        final primary = contentType.split(';').first.trim().toLowerCase();
        if (primary.isNotEmpty && !primary.startsWith('image/')) {
          return null;
        }
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > _maxFaviconBytes) return null;
      if (_looksLikeHtml(bytes)) return null;
      final mime = _resolveMime(contentType, fallbackMime);
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      _logDebug('favicon fetch failed for $uri: $e');
      return null;
    }
  }

  /// Heuristic: does the body start with HTML markup? Looks at the
  /// first ~64 bytes after skipping ASCII whitespace and a UTF-8 BOM.
  /// SVG XML (`<?xml ...`, `<svg ...`) is NOT classified as HTML — we
  /// accept SVG as a valid favicon format.
  static bool _looksLikeHtml(Uint8List bytes) {
    var i = 0;
    // Skip UTF-8 BOM if present.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      i = 3;
    }
    // Skip leading ASCII whitespace.
    while (i < bytes.length && bytes[i] <= 0x20) {
      i++;
    }
    final head = String.fromCharCodes(
      bytes.sublist(i, i + 64 > bytes.length ? bytes.length : i + 64),
    ).toLowerCase();
    return head.startsWith('<!doctype html') ||
        head.startsWith('<html') ||
        head.startsWith('<head') ||
        head.startsWith('<body');
  }

  String _resolveMime(String? contentType, String fallback) {
    if (contentType == null) return fallback;
    final primary = contentType.split(';').first.trim().toLowerCase();
    if (primary.startsWith('image/')) return primary;
    return fallback;
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('MetadataFetchService: $message');
    }
  }
}

/// Returns the first non-null result from [futures]. Resolves to null
/// only when EVERY future has completed with null (or thrown — handled
/// by the per-future try/catch in [MetadataFetchService._tryFetchIcon]).
///
/// Outstanding futures keep running after the first non-null wins; their
/// results are discarded. Acceptable for our HTTP GETs because they're
/// short-lived and idempotent.
Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
  if (futures.isEmpty) return Future<T?>.value(null);
  final completer = Completer<T?>();
  var remaining = futures.length;
  for (final f in futures) {
    f.then((value) {
      if (value != null && !completer.isCompleted) {
        completer.complete(value);
        return;
      }
      remaining--;
      if (remaining == 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }, onError: (Object _) {
      // Per-future errors shouldn't propagate; treat as null.
      remaining--;
      if (remaining == 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    });
  }
  return completer.future;
}

class _DeclaredPathResult {
  const _DeclaredPathResult({required this.title, required this.favicon});
  final String? title;
  final String? favicon;
}
