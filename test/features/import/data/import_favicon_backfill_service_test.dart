import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/import/data/import_favicon_backfill_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory `IBookmarkRepository` backed by a Map.
///
/// Tracks every `save()` call (order + payload) and lets each test
/// pre-seed the store via [put]. `getById` returns `Err(StorageError)`
/// for unknown IDs — matches the production repository's behaviour
/// when a bookmark has been deleted between import and backfill.
class _FakeBookmarkRepository implements IBookmarkRepository {
  final Map<String, Bookmark> _store = <String, Bookmark>{};
  final List<Bookmark> savedBookmarks = <Bookmark>[];

  /// If non-null, every save() returns this Result instead of writing.
  /// Use for the "save returns Err — continue" test case.
  Result<Bookmark, AppError> Function(Bookmark)? saveOverride;

  void put(Bookmark bookmark) {
    _store[bookmark.id] = bookmark;
  }

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async {
    final found = _store[id];
    if (found == null) {
      return const Err<Bookmark, AppError>(StorageError('not found'));
    }
    return Ok<Bookmark, AppError>(found);
  }

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    savedBookmarks.add(bookmark);
    if (saveOverride != null) return saveOverride!(bookmark);
    _store[bookmark.id] = bookmark;
    return Ok<Bookmark, AppError>(bookmark);
  }

  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Err(StorageError('unused'));

  @override
  Stream<List<Bookmark>> watchAll() => const Stream.empty();

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) => const Stream.empty();
}

/// Fake `MetadataFetchService` that records every URL it sees and
/// returns whatever [handler] dictates. Tracks the peak observed
/// in-flight call count — used by the concurrency-cap test.
class _FakeMetadataFetchService implements MetadataFetchService {
  /// Called per-URL. If null, returns `UrlMetadata()` (both null).
  UrlMetadata Function(String url)? handler;

  /// Optional async hold per call (test-controlled). When set, every
  /// call awaits this Future before returning — lets tests freeze the
  /// pool to observe concurrency.
  Future<void> Function(String url)? gate;

  final List<String> requestedUrls = <String>[];
  int inFlight = 0;
  int peakInFlight = 0;

  @override
  Future<UrlMetadata> fetch(String url) async {
    requestedUrls.add(url);
    inFlight++;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    try {
      if (gate != null) await gate!(url);
      return handler?.call(url) ?? const UrlMetadata();
    } finally {
      inFlight--;
    }
  }

  @override
  void close() {}
}

Bookmark _bookmark({
  required String id,
  String? url,
  String? title,
  String? faviconBase64,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.utc(2026, 5, 23);
  return Bookmark(
    id: id,
    url: url ?? 'https://example.com/$id',
    title: title ?? 'Bookmark $id',
    faviconBase64: faviconBase64,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  late _FakeBookmarkRepository repo;
  late _FakeMetadataFetchService fetcher;

  setUp(() {
    repo = _FakeBookmarkRepository();
    fetcher = _FakeMetadataFetchService();
  });

  test('empty ID list → returns immediately, no fetches, no saves',
      () async {
    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>[]);
    expect(fetcher.requestedUrls, isEmpty);
    expect(repo.savedBookmarks, isEmpty);
  });

  test('single bookmark, fetch succeeds → saved with new favicon '
      'and bumped updatedAt; title preserved (title != url)', () async {
    final created = DateTime.utc(2026, 5, 20);
    final bookmark = _bookmark(
      id: 'a',
      url: 'https://a.example',
      title: 'A site',
      createdAt: created,
      updatedAt: created,
    );
    repo.put(bookmark);
    fetcher.handler = (_) => const UrlMetadata(
          title: 'Live title',
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final now = DateTime.utc(2026, 5, 23, 10);
    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
      now: () => now,
    );
    await service.backfill(<String>['a']);

    expect(repo.savedBookmarks.length, 1);
    final saved = repo.savedBookmarks.single;
    expect(saved.id, 'a');
    expect(saved.title, 'A site',
        reason: 'title preserved when title != url');
    expect(saved.faviconBase64, 'data:image/png;base64,AAAA');
    expect(saved.updatedAt, now,
        reason: 'updatedAt bumped to the injected clock');
  });

  test('title overwritten when title == url AND fetch returns title',
      () async {
    final bookmark = _bookmark(
      id: 'a',
      url: 'https://a.example',
      title: 'https://a.example',
    );
    repo.put(bookmark);
    fetcher.handler = (_) => const UrlMetadata(
          title: 'Real title',
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>['a']);

    expect(repo.savedBookmarks.single.title, 'Real title');
  });

  test('title NOT overwritten when title == url AND fetch returns '
      'null title (favicon still applied)', () async {
    final bookmark = _bookmark(
      id: 'a',
      url: 'https://a.example',
      title: 'https://a.example',
    );
    repo.put(bookmark);
    fetcher.handler = (_) => const UrlMetadata(
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>['a']);

    expect(repo.savedBookmarks.single.title, 'https://a.example',
        reason: 'no fetched title → URL-as-title preserved');
    expect(repo.savedBookmarks.single.faviconBase64,
        'data:image/png;base64,AAAA');
  });

  test('bookmark already has non-null faviconBase64 → skipped '
      '(no fetch, no save)', () async {
    final bookmark = _bookmark(
      id: 'a',
      faviconBase64: 'data:image/png;base64,EXISTING',
    );
    repo.put(bookmark);

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>['a']);

    expect(fetcher.requestedUrls, isEmpty,
        reason: 'idempotency: no fetch when favicon already present');
    expect(repo.savedBookmarks, isEmpty);
  });

  test('bookmark not found in repo (getById → Err) → skipped silently',
      () async {
    // Don't seed the repo — getById returns Err.
    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>['ghost']);

    expect(fetcher.requestedUrls, isEmpty);
    expect(repo.savedBookmarks, isEmpty);
  });

  test('fetch returns null favicon → no save; placeholder remains',
      () async {
    repo.put(_bookmark(id: 'a'));
    fetcher.handler = (_) => const UrlMetadata();

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    await service.backfill(<String>['a']);

    expect(fetcher.requestedUrls.length, 1);
    expect(repo.savedBookmarks, isEmpty,
        reason: 'null favicon → no save (failure-as-data, placeholder stays)');
  });

  test('save returns Err → continues to next bookmark (no throw)',
      () async {
    repo.put(_bookmark(id: 'a'));
    repo.put(_bookmark(id: 'b'));
    fetcher.handler = (_) => const UrlMetadata(
          faviconBase64: 'data:image/png;base64,AAAA',
        );
    repo.saveOverride =
        (_) => const Err<Bookmark, AppError>(StorageError('disk full'));

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    // Should NOT throw.
    await service.backfill(<String>['a', 'b']);

    expect(repo.savedBookmarks.length, 2,
        reason: 'save was attempted for both even after the first Err');
    expect(fetcher.requestedUrls, ['https://example.com/a', 'https://example.com/b']);
  });

  test('concurrency: 20 bookmarks → peak in-flight ≤ 6', () async {
    for (var i = 0; i < 20; i++) {
      repo.put(_bookmark(id: '$i'));
    }
    // Single global gate. Every fetch awaits it. Workers will stack
    // up against the gate so the peak count reflects the pool size.
    // Once we release, all fetches resolve and the pool drains
    // normally.
    final releaseGate = Completer<void>();
    fetcher.gate = (_) => releaseGate.future;
    fetcher.handler = (_) => const UrlMetadata(
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    final running =
        service.backfill(List.generate(20, (i) => '$i'));

    // Drain microtasks so all 6 workers reach their first fetch().
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(fetcher.peakInFlight, 6,
        reason: 'six workers should all be parked at the gate');

    releaseGate.complete();
    await running;

    expect(fetcher.peakInFlight, 6,
        reason: 'cap holds for the lifetime of the run');
    expect(repo.savedBookmarks.length, 20);
  });

  test('cancellation: cancel() mid-run discards outstanding fetch '
      'results — no save for cancelled IDs', () async {
    for (var i = 0; i < 10; i++) {
      repo.put(_bookmark(id: '$i'));
    }
    final gates = <String, Completer<void>>{};
    fetcher.gate = (url) {
      final completer = Completer<void>();
      gates[url] = completer;
      return completer.future;
    };
    fetcher.handler = (_) => const UrlMetadata(
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );
    final running = service.backfill(List.generate(10, (i) => '$i'));

    // Wait until at least some workers are parked at the gate.
    for (var i = 0; i < 10 && fetcher.inFlight < 1; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(fetcher.inFlight, greaterThanOrEqualTo(1));

    service.cancel();

    // Release the parked fetches — their results should be discarded.
    for (final c in gates.values.toList()) {
      if (!c.isCompleted) c.complete();
    }
    await running;

    expect(repo.savedBookmarks, isEmpty,
        reason:
            'cancel() invalidated the run token → no saves after the cancel');
  });

  test('re-entry: backfill(B) before backfill(A) finishes → A '
      "aborts, B's IDs are processed", () async {
    for (var i = 0; i < 10; i++) {
      repo.put(_bookmark(id: 'A$i'));
      repo.put(_bookmark(id: 'B$i'));
    }
    final gates = <String, Completer<void>>{};
    fetcher.gate = (url) {
      final completer = Completer<void>();
      gates[url] = completer;
      return completer.future;
    };
    fetcher.handler = (_) => const UrlMetadata(
          faviconBase64: 'data:image/png;base64,AAAA',
        );

    final service = ImportFaviconBackfillService(
      bookmarkRepo: repo,
      metadataFetchService: fetcher,
    );

    // First run.
    final aRunning =
        service.backfill(List.generate(10, (i) => 'A$i'));
    for (var i = 0; i < 5 && fetcher.inFlight == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // Second run before the first drains. Per spec, this cancels A
    // and starts B fresh.
    final bRunning =
        service.backfill(List.generate(10, (i) => 'B$i'));

    // Release every gate. A's results should be discarded; B should
    // drive all 10 saves.
    while (!_isQueueIdle(gates) || fetcher.inFlight > 0) {
      await Future<void>.delayed(Duration.zero);
      for (final c in gates.values.toList()) {
        if (!c.isCompleted) c.complete();
      }
    }
    await Future.wait([aRunning, bRunning]);

    final savedIds = repo.savedBookmarks.map((b) => b.id).toSet();
    final bIds = {for (var i = 0; i < 10; i++) 'B$i'};
    expect(savedIds.containsAll(bIds), isTrue,
        reason: 'every B-id should land a save');
    expect(savedIds.intersection({for (var i = 0; i < 10; i++) 'A$i'}),
        isEmpty,
        reason: "A's results were discarded after cancellation");
  });
}

/// True when every completer in [gates] is done — i.e. no fetch is
/// parked at the gate any more.
bool _isQueueIdle(Map<String, Completer<void>> gates) {
  for (final c in gates.values) {
    if (!c.isCompleted) return false;
  }
  return true;
}
