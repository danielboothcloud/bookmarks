import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/bookmarks/application/bookmark_providers.dart';
import '../theme/app_colors.dart';

/// Renders a bookmark's favicon in one of three states (per UX spec):
///   - **Loaded**: decoded image from base64 data URI
///   - **Loading**: 12 px CircularProgressIndicator while metadata fetch is
///     in flight (subscribes to [metadataFetchInFlightProvider])
///   - **Placeholder**: muted public-globe icon when no favicon and not
///     loading
///
/// `size` is the slot size (20 list, 28 card, 36 detail). Decoded bytes are
/// memoised in a static FIFO cache so the base64 -> Uint8List work doesn't
/// recur on every list rebuild.
class FaviconWidget extends ConsumerWidget {
  const FaviconWidget({
    required this.bookmarkId,
    required this.faviconBase64,
    this.size = 20,
    super.key,
  });

  final String bookmarkId;
  final String? faviconBase64;
  final double size;

  /// Soft cap on the in-process decoded-bytes cache. Eviction is FIFO --
  /// adequate for the typical session (≤ a few hundred distinct favicons).
  static const _cacheLimit = 256;
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  /// Test hook -- clears the static decode cache between widget tests so
  /// state cannot leak across cases.
  @visibleForTesting
  static void debugClearCache() => _cache.clear();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = _decode(faviconBase64);
    final isInFlight = bytes == null &&
        ref.watch(metadataFetchInFlightProvider).contains(bookmarkId);

    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: _buildContent(bytes: bytes, isInFlight: isInFlight),
        ),
      ),
    );
  }

  Widget _buildContent({
    required Uint8List? bytes,
    required bool isInFlight,
  }) {
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (isInFlight) {
      // Scale the spinner with the slot. 60% matches the original 12-in-20
      // ratio so list views look unchanged; card (28) and detail (36) get
      // proportionally larger spinners instead of a stuck-looking 12px one.
      final spinnerSize = size * 0.6;
      return Center(
        child: SizedBox(
          width: spinnerSize,
          height: spinnerSize,
          child: const CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceHover,
      child: Icon(
        Icons.public,
        size: size * 0.7,
        color: AppColors.textMuted,
      ),
    );
  }

  /// Memoised base64 -> bytes decode. Returns null on invalid input so
  /// callers fall back to the placeholder state.
  static Uint8List? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final cached = _cache[raw];
    if (cached != null) return cached;
    try {
      final commaIndex = raw.indexOf(',');
      final payload = raw.startsWith('data:') && commaIndex != -1
          ? raw.substring(commaIndex + 1)
          : raw;
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) return null;
      _cache[raw] = bytes;
      if (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    } on FormatException {
      return null;
    }
  }
}
