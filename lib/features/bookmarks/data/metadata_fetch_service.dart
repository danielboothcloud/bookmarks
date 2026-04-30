import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:metadata_fetch/metadata_fetch.dart';

import '../domain/url_metadata.dart';

/// Fetches the page title (via metadata_fetch) and favicon bytes (direct
/// host request) for a given URL. Privacy-aligned: no third-party favicon
/// proxies; only the host the user is already bookmarking is contacted.
///
/// Failure is modelled as data: every failure path (404, timeout, parse
/// error, malformed URL, oversized body) yields
/// `UrlMetadata(title: null, faviconBase64: null)`. The service never
/// throws and never returns an error sentinel -- AC4 (silent fallback)
/// holds at the type level.
class MetadataFetchService {
  MetadataFetchService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  /// 64 KB ceiling on favicon size -- generous for the 99th percentile while
  /// keeping SQLite rows bounded.
  static const _maxFaviconBytes = 64 * 1024;

  /// 2 MB ceiling on HTML title fetch. The body is streamed and aborted
  /// once the cap is exceeded so a malicious or runaway server cannot
  /// blow client memory.
  static const _maxHtmlBytes = 2 * 1024 * 1024;

  Future<UrlMetadata> fetch(String url) async {
    final pageUri = Uri.tryParse(url);
    if (pageUri == null ||
        pageUri.host.isEmpty ||
        !(pageUri.scheme == 'http' || pageUri.scheme == 'https')) {
      return const UrlMetadata();
    }

    // Title and favicon fetches are independent -- run concurrently so the
    // worst-case wall time is one timeout, not two.
    final results = await Future.wait<Object?>([
      _fetchTitle(pageUri),
      _fetchFavicon(pageUri),
    ]);
    return UrlMetadata(
      title: results[0] as String?,
      faviconBase64: results[1] as String?,
    );
  }

  /// Closes the underlying HTTP client. Provider `onDispose` should call this.
  void close() => _client.close();

  Future<String?> _fetchTitle(Uri pageUri) async {
    try {
      final request = http.Request('GET', pageUri);
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
      final document = MetadataFetch.responseToDocument(response);
      if (document == null) return null;
      final metadata = MetadataParser.parse(document, url: pageUri.toString());
      final title = metadata.title?.trim();
      if (title == null || title.isEmpty) return null;
      return title;
    } catch (e) {
      _logDebug('title fetch failed: $e');
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

  Future<String?> _fetchFavicon(Uri pageUri) async {
    final primary = await _tryFetchIcon(
      Uri(scheme: 'https', host: pageUri.host, path: '/favicon.ico'),
      fallbackMime: 'image/x-icon',
    );
    if (primary != null) return primary;
    return _tryFetchIcon(
      Uri(scheme: 'https', host: pageUri.host, path: '/apple-touch-icon.png'),
      fallbackMime: 'image/png',
    );
  }

  Future<String?> _tryFetchIcon(
    Uri uri, {
    required String fallbackMime,
  }) async {
    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > _maxFaviconBytes) return null;
      final mime = _resolveMime(response.headers['content-type'], fallbackMime);
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e) {
      _logDebug('favicon fetch failed for $uri: $e');
      return null;
    }
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
