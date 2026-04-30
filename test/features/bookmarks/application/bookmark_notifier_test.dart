import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_notifier.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRepository implements IBookmarkRepository {
  final List<Bookmark> savedBookmarks = <Bookmark>[];
  Result<Bookmark, AppError> Function(Bookmark)? saveResult;

  Bookmark? get lastSaved =>
      savedBookmarks.isEmpty ? null : savedBookmarks.last;

  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(StorageError('not impl'));

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    savedBookmarks.add(bookmark);
    return (saveResult ?? Ok<Bookmark, AppError>.new)(bookmark);
  }
}

/// Fake service that returns whatever the test sets up. Default is "no-op
/// success" -- both fields null -- so existing tests don't need to think
/// about the metadata fetch path.
class _FakeMetadataFetchService implements MetadataFetchService {
  UrlMetadata Function(String url) handler = (_) => const UrlMetadata();
  Completer<void>? gate;
  final List<String> requestedUrls = <String>[];

  @override
  Future<UrlMetadata> fetch(String url) async {
    requestedUrls.add(url);
    if (gate != null) await gate!.future;
    return handler(url);
  }

  @override
  void close() {}
}

ProviderContainer _container(
  IBookmarkRepository repo, {
  MetadataFetchService? metadataService,
}) {
  return ProviderContainer(overrides: [
    bookmarkRepositoryProvider.overrideWithValue(repo),
    metadataFetchServiceProvider
        .overrideWithValue(metadataService ?? _FakeMetadataFetchService()),
  ]);
}

/// Pump until the microtask queue drains -- gives fire-and-forget the chance
/// to write its second `repo.save(...)` before assertions.
Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('addBookmark generates UUID v4 and stamps createdAt/updatedAt', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await notifier.addBookmark(url: 'https://example.com');
    final afterMs = DateTime.now().millisecondsSinceEpoch;
    await _drain();

    final saved = repo.savedBookmarks.first;
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(saved.id), isTrue,
        reason: 'expected UUID v4, got ${saved.id}');
    expect(
      saved.createdAt.millisecondsSinceEpoch,
      inInclusiveRange(beforeMs, afterMs),
    );
    expect(saved.updatedAt, saved.createdAt);
  });

  test('addBookmark falls back title to url when title empty (AC5)', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    await notifier.addBookmark(url: 'https://example.com', title: '   ');
    expect(repo.savedBookmarks.first.title, 'https://example.com');

    await notifier.addBookmark(url: 'https://other.com');
    expect(repo.savedBookmarks[1].title, 'https://other.com');
    await _drain();
  });

  test('addBookmark with explicit title preserves it', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(bookmarkNotifierProvider.notifier)
        .addBookmark(url: 'https://example.com', title: 'Custom');
    await _drain();
    expect(repo.savedBookmarks.first.title, 'Custom');
  });

  test('addBookmark sets AsyncValue.error on Err without throwing', () async {
    final repo = _RecordingRepository()
      ..saveResult = (_) => const Err<Bookmark, AppError>(StorageError('boom'));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    await notifier.addBookmark(url: 'https://example.com');

    final state = container.read(bookmarkNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StorageError>());
  });

  group('metadata fetch orchestration (Story 1.3)', () {
    test(
        'after addBookmark resolves, metadataFetchInFlightProvider contains the '
        'new bookmark id (verified before fetch completes)', () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService()..gate = Completer<void>();
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com');

      final inFlight = container.read(metadataFetchInFlightProvider);
      expect(inFlight, contains(repo.savedBookmarks.first.id));

      // Release the gate so the fire-and-forget cleanup runs before disposal.
      fake.gate!.complete();
      await _drain();
    });

    test(
        'after fetch resolves with title+favicon, repository.save is called a '
        'second time with the fetched values', () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService()
        ..handler = (_) => const UrlMetadata(
              title: 'Real Title',
              faviconBase64: 'data:image/png;base64,abc',
            );
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com');
      await _drain();

      expect(repo.savedBookmarks.length, 2);
      final updated = repo.savedBookmarks[1];
      expect(updated.title, 'Real Title');
      expect(updated.faviconBase64, 'data:image/png;base64,abc');
      expect(updated.id, repo.savedBookmarks.first.id);
    });

    test(
        'fetched title does NOT overwrite a user-provided custom title (H4)',
        () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService()
        ..handler = (_) => const UrlMetadata(
              title: 'Fetched Page Title',
              faviconBase64: 'data:image/png;base64,abc',
            );
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com', title: 'My Title');
      await _drain();

      expect(repo.savedBookmarks.length, 2);
      final updated = repo.savedBookmarks[1];
      expect(updated.title, 'My Title',
          reason: 'user-supplied title must survive the post-fetch save');
      expect(updated.faviconBase64, 'data:image/png;base64,abc',
          reason: 'favicon should still be applied even when title is preserved');
    });

    test('after fetch resolves, the bookmark id is removed from in-flight set',
        () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService();
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com');
      await _drain();

      expect(container.read(metadataFetchInFlightProvider), isEmpty);
    });

    test(
        'fetch resolves with both fields null -> repo.save NOT called a second '
        'time (no-op when nothing useful was fetched)', () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService(); // default: both null
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com');
      await _drain();

      expect(repo.savedBookmarks.length, 1,
          reason: 'no metadata to apply, second save would be wasteful');
    });

    test(
        'updateBookmark writes through repo with bumped updatedAt and clears '
        'AsyncValue error (Story 1.4)', () async {
      final repo = _RecordingRepository();
      final container = _container(repo);
      addTearDown(container.dispose);

      final original = Bookmark(
        id: 'fixed-id',
        url: 'https://example.com',
        title: 'Old Title',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final beforeMs = DateTime.now().millisecondsSinceEpoch;
      await container
          .read(bookmarkNotifierProvider.notifier)
          .updateBookmark(original.copyWith(title: 'New Title'));
      await _drain();

      final saved = repo.savedBookmarks.single;
      expect(saved.id, 'fixed-id');
      expect(saved.title, 'New Title');
      expect(saved.createdAt, original.createdAt,
          reason: 'updateBookmark must not touch createdAt');
      expect(
        saved.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(beforeMs),
        reason: 'updatedAt must be bumped to "now" by the notifier',
      );

      final state = container.read(bookmarkNotifierProvider);
      expect(state.hasError, isFalse);
      expect(state.hasValue, isTrue);
    });

    test(
        'updateBookmark on Err sets AsyncValue.error so _SaveErrorBanner '
        'surfaces (Story 1.4)', () async {
      final repo = _RecordingRepository()
        ..saveResult = (_) => const Err<Bookmark, AppError>(StorageError('boom'));
      final container = _container(repo);
      addTearDown(container.dispose);

      final original = Bookmark(
        id: 'fixed-id',
        url: 'https://example.com',
        title: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await container
          .read(bookmarkNotifierProvider.notifier)
          .updateBookmark(original.copyWith(title: 'New'));

      final state = container.read(bookmarkNotifierProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StorageError>());
    });

    test(
        'updateBookmark does NOT trigger a metadata fetch (Story 1.4: edits '
        'are corrections, not fresh captures)', () async {
      final repo = _RecordingRepository();
      final fake = _FakeMetadataFetchService();
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      final original = Bookmark(
        id: 'id-1',
        url: 'https://example.com',
        title: 'Old',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await container
          .read(bookmarkNotifierProvider.notifier)
          .updateBookmark(original.copyWith(title: 'New'));
      await _drain();

      expect(repo.savedBookmarks.length, 1,
          reason: 'no second save: metadata fetch must not run on update');
      expect(fake.requestedUrls, isEmpty,
          reason: 'metadata service must not be called on edit');
    });

    test(
        'post-fetch save Err does NOT pollute bookmarkNotifierProvider state '
        '(M3 + Story 1.2 _SaveErrorBanner contract)', () async {
      var saveCalls = 0;
      final repo = _RecordingRepository()
        ..saveResult = (b) {
          saveCalls += 1;
          // First save (addBookmark) succeeds; second save (post-fetch) errs.
          return saveCalls == 1
              ? Ok<Bookmark, AppError>(b)
              : const Err<Bookmark, AppError>(StorageError('disk full'));
        };
      final fake = _FakeMetadataFetchService()
        ..handler = (_) => const UrlMetadata(
              title: 'Real Title',
              faviconBase64: 'data:image/png;base64,abc',
            );
      final container = _container(repo, metadataService: fake);
      addTearDown(container.dispose);

      await container
          .read(bookmarkNotifierProvider.notifier)
          .addBookmark(url: 'https://example.com');
      await _drain();

      final notifierState = container.read(bookmarkNotifierProvider);
      expect(notifierState.hasError, isFalse,
          reason: 'post-fetch save failure must not surface as save error');
    });
  });
}

