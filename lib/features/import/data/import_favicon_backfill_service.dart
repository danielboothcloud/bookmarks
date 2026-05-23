import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../../../core/error/result.dart';
import '../../bookmarks/data/metadata_fetch_service.dart';
import '../../bookmarks/domain/i_bookmark_repository.dart';

/// Fetches favicons in the background for bookmarks that landed via the
/// HTML import path (Story 5.1). Wraps [MetadataFetchService] — the
/// single-URL discovery primitive overhauled in commit 6788ed2 — with
/// a bounded worker pool, cancellation, and idempotency.
///
/// **Lifecycle.** Fire-and-forget from the notifier's perspective: the
/// `ImportNotifier` calls `unawaited(backfill(ids))` after
/// `ImportSucceeded`. The service returns when all workers settle
/// (queue drained OR cancelled).
///
/// **Concurrency.** `_maxConcurrent = 6` workers share a single
/// `Queue<String>` of bookmark IDs. The cap sits in the 4–8 band the
/// Epic 4 retro §3 prescribed — 500 simultaneous favicon GETs would
/// saturate the local network and trigger per-host rate limits.
///
/// **Cancellation.** Each `backfill(...)` call mints a fresh
/// `_currentRun` token; workers check the token before every `await`
/// and before every `save()`. `cancel()` (called at the top of
/// `pickAndImport` per AC7) replaces the token; the next `backfill`
/// call does the same. In-flight HTTP requests are allowed to complete
/// — we don't surgically abort the `http.Client.send` — but their
/// results are discarded.
///
/// **Idempotency.** Before fetching, the worker reads the current
/// bookmark and skips if `faviconBase64 != null`. Protects against
/// re-runs against the same IDs, future `<ICON>` extraction in the
/// parser, and any other path that populated the favicon between
/// import and backfill.
///
/// **Title upgrade.** Mirrors Story 1.3's `_fetchMetadata` heuristic:
/// the imported title is overwritten only when it equals the URL
/// (the URL-fallback case from Story 5.1 AC6 for empty-titled HTML
/// entries). Otherwise the imported title is preserved as
/// authoritative.
///
/// **Failure semantics.** `MetadataFetchService.fetch` is
/// failure-as-data: every failure returns `UrlMetadata(title: null,
/// faviconBase64: null)`. The backfill makes no `save()` call on a
/// null favicon — placeholder remains. `save()` errors are
/// debug-logged and skipped; the next bookmark proceeds.
///
/// **No retry on relaunch.** State is in-memory; if the app closes
/// mid-backfill, pending IDs are dropped. AC5 explicit.
class ImportFaviconBackfillService {
  ImportFaviconBackfillService({
    required IBookmarkRepository bookmarkRepo,
    required MetadataFetchService metadataFetchService,
    DateTime Function()? now,
  })  : _bookmarkRepo = bookmarkRepo,
        _metadataFetchService = metadataFetchService,
        _now = now ?? DateTime.now;

  final IBookmarkRepository _bookmarkRepo;
  final MetadataFetchService _metadataFetchService;
  final DateTime Function() _now;

  /// Epic 4 retro §3 prescribed 4–8 simultaneous fetches; 6 is the median.
  static const int _maxConcurrent = 6;

  /// Cancellation token. Replaced per `backfill` call and on `cancel()`.
  /// Worker iterations check `identical(_currentRun, myToken)` before
  /// every cross-await side-effect.
  Object? _currentRun;

  /// Backfill favicons for [bookmarkIds]. Cancels any previously-running
  /// backfill before starting. Returns when all workers settle.
  Future<void> backfill(List<String> bookmarkIds) async {
    if (bookmarkIds.isEmpty) return;

    final runToken = Object();
    _currentRun = runToken;

    final queue = Queue<String>.from(bookmarkIds);
    final workers = <Future<void>>[
      for (var i = 0; i < _maxConcurrent; i++) _worker(queue, runToken),
    ];
    await Future.wait(workers);
  }

  /// Cancels the in-flight backfill (if any). In-flight HTTP requests
  /// are allowed to complete but their results are discarded.
  void cancel() {
    _currentRun = null;
  }

  Future<void> _worker(Queue<String> queue, Object runToken) async {
    while (queue.isNotEmpty && identical(_currentRun, runToken)) {
      final id = queue.removeFirst();

      final getResult = await _bookmarkRepo.getById(id);
      if (!identical(_currentRun, runToken)) return;
      final current = switch (getResult) {
        Ok(:final value) => value,
        // Bookmark deleted between import and backfill, or some other
        // storage error — skip silently.
        Err() => null,
      };
      if (current == null) continue;
      if (current.faviconBase64 != null) {
        // Idempotency: already has a favicon — skip without fetching.
        continue;
      }

      final fetched = await _metadataFetchService.fetch(current.url);
      if (!identical(_currentRun, runToken)) return;

      final favicon = fetched.faviconBase64;
      if (favicon == null) {
        // Failure-as-data: placeholder remains, no save.
        continue;
      }

      // Title upgrade — mirror Story 1.3's `_fetchMetadata` heuristic:
      // overwrite the imported title only when it equals the URL
      // (Story 5.1 AC6 URL-fallback case).
      final fetchedTitle = fetched.title;
      final nextTitle = (current.title == current.url && fetchedTitle != null)
          ? fetchedTitle
          : current.title;

      final updated = current.copyWith(
        title: nextTitle,
        faviconBase64: favicon,
        updatedAt: _now(),
      );

      final saveResult = await _bookmarkRepo.save(updated);
      if (!identical(_currentRun, runToken)) return;
      switch (saveResult) {
        case Ok():
          break;
        case Err(:final error):
          if (kDebugMode) {
            debugPrint(
              'ImportFaviconBackfillService: save failed for ${current.id}: '
              '$error',
            );
          }
      }
    }
  }
}
