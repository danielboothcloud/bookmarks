import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StreamingTagRepository implements ITagRepository {
  final StreamController<List<Tag>> allController =
      StreamController<List<Tag>>.broadcast();
  final Map<String, StreamController<List<Tag>>> perBookmarkControllers =
      <String, StreamController<List<Tag>>>{};

  @override
  Stream<List<Tag>> watchAll() => allController.stream;

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() =>
      const Stream<List<TagWithCount>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) {
    final controller = perBookmarkControllers.putIfAbsent(
      bookmarkId,
      StreamController<List<Tag>>.broadcast,
    );
    return controller.stream;
  }

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async => Ok<Tag,
      AppError>(Tag(
    id: name,
    name: name,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  ));

  @override
  Future<Result<void, AppError>> linkBookmarkTag(
          String bookmarkId, String tagId) async =>
      const Ok<void, AppError>(null);

  @override
  Future<Result<void, AppError>> unlinkBookmarkTag(
          String bookmarkId, String tagId) async =>
      const Ok<void, AppError>(null);

  @override
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  }) async =>
      const Ok<List<Tag>, AppError>(<Tag>[]);
}

void main() {
  // tagInputDraftProvider was removed in the 2.5 code review (dead code:
  // _TagsRow never wired to it; draft clearing is now handled by
  // ValueKey(bookmarkId) forcing fresh ConsumerState on bookmark switch).

  test('watchAllTagsProvider stream forwards values from the repo', () async {
    final repo = _StreamingTagRepository();
    final container = ProviderContainer(overrides: [
      tagRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    addTearDown(repo.allController.close);

    container.listen<AsyncValue<List<Tag>>>(watchAllTagsProvider, (_, _) {});

    final emitted = [
      Tag(
        id: 't',
        name: 't',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
    repo.allController.add(emitted);
    await Future<void>.delayed(Duration.zero);

    final value = container.read(watchAllTagsProvider).value;
    expect(value, isNotNull);
    expect(value!.single.name, 't');
  });

  test(
      'watchTagsForBookmarkProvider family is keyed by bookmark id — '
      'two ids subscribe to two distinct streams (no crosstalk)', () async {
    final repo = _StreamingTagRepository();
    final container = ProviderContainer(overrides: [
      tagRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    addTearDown(() {
      for (final c in repo.perBookmarkControllers.values) {
        c.close();
      }
    });

    container.listen<AsyncValue<List<Tag>>>(
      watchTagsForBookmarkProvider('b1'),
      (_, _) {},
    );
    container.listen<AsyncValue<List<Tag>>>(
      watchTagsForBookmarkProvider('b2'),
      (_, _) {},
    );

    repo.perBookmarkControllers['b1']!.add([
      Tag(
        id: 'x',
        name: 'x',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ]);
    repo.perBookmarkControllers['b2']!.add(<Tag>[]);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(watchTagsForBookmarkProvider('b1')).value?.single.name,
      'x',
    );
    expect(
      container.read(watchTagsForBookmarkProvider('b2')).value,
      isEmpty,
    );
  });

  group('selectedTagIdProvider', () {
    test('defaults to null on fresh build', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedTagIdProvider), isNull);
    });

    test('select(id) sets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedTagIdProvider.notifier).select('t-1');
      expect(container.read(selectedTagIdProvider), 't-1');
    });

    test('clear() resets state to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedTagIdProvider.notifier).select('t-1');
      container.read(selectedTagIdProvider.notifier).clear();
      expect(container.read(selectedTagIdProvider), isNull);
    });

    test('multiple select calls overwrite', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedTagIdProvider.notifier).select('t-1');
      container.read(selectedTagIdProvider.notifier).select('t-2');
      expect(container.read(selectedTagIdProvider), 't-2');
    });
  });

  group('watchBookmarksForTagProvider', () {
    test(
        'family-keyed: two listeners on different tag ids see different lists',
        () async {
      final repo = _StreamingBookmarkRepo();
      final container = ProviderContainer(overrides: [
        bookmarkRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      container.listen<AsyncValue<List<Bookmark>>>(
        watchBookmarksForTagProvider('t1'),
        (_, _) {},
      );
      container.listen<AsyncValue<List<Bookmark>>>(
        watchBookmarksForTagProvider('t2'),
        (_, _) {},
      );

      repo.emit('t1', [_bm('b1')]);
      repo.emit('t2', [_bm('b2'), _bm('b3')]);
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(watchBookmarksForTagProvider('t1'))
            .value
            ?.map((b) => b.id)
            .toList(),
        ['b1'],
      );
      expect(
        container
            .read(watchBookmarksForTagProvider('t2'))
            .value
            ?.map((b) => b.id)
            .toList(),
        ['b2', 'b3'],
      );
    });

    test(
        'family-keyed: same tag id shares a stream subscription (single emit '
        'reaches both listeners)', () async {
      final repo = _StreamingBookmarkRepo();
      final container = ProviderContainer(overrides: [
        bookmarkRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      addTearDown(repo.dispose);

      final aValues = <AsyncValue<List<Bookmark>>>[];
      final bValues = <AsyncValue<List<Bookmark>>>[];
      container.listen<AsyncValue<List<Bookmark>>>(
        watchBookmarksForTagProvider('t1'),
        (_, next) => aValues.add(next),
        fireImmediately: true,
      );
      container.listen<AsyncValue<List<Bookmark>>>(
        watchBookmarksForTagProvider('t1'),
        (_, next) => bValues.add(next),
        fireImmediately: true,
      );

      repo.emit('t1', [_bm('b1')]);
      await Future<void>.delayed(Duration.zero);

      expect(aValues.last.value?.single.id, 'b1');
      expect(bValues.last.value?.single.id, 'b1');
      // One controller created -- the family memoised the family-keyed
      // provider, so both listeners share a single subscription.
      expect(repo.controllerCount, 1);
    });
  });
}

Bookmark _bm(String id) => Bookmark(
      id: id,
      url: 'https://example.com/$id',
      title: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

class _StreamingBookmarkRepo implements IBookmarkRepository {
  final Map<String, StreamController<List<Bookmark>>> _per =
      <String, StreamController<List<Bookmark>>>{};

  int get controllerCount => _per.length;

  void emit(String tagId, List<Bookmark> bookmarks) {
    final c = _per[tagId];
    if (c != null && !c.isClosed) c.add(bookmarks);
  }

  Future<void> dispose() async {
    for (final c in _per.values) {
      await c.close();
    }
  }

  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) {
    final controller = _per.putIfAbsent(
      tagId,
      StreamController<List<Bookmark>>.broadcast,
    );
    return controller.stream;
  }

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      Ok<Bookmark, AppError>(bookmark);

  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Ok<void, AppError>(null);
}
