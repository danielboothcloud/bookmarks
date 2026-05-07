import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:bookmarks/features/tags/presentation/tags_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopBookmarkRepo implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() =>
      Stream<List<Bookmark>>.value(const <Bookmark>[]);

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) =>
      Stream<List<Bookmark>>.value(const <Bookmark>[]);

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

class _NoopTagRepo implements ITagRepository {
  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() =>
      const Stream<List<TagWithCount>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) =>
      Stream<List<Tag>>.value(const <Tag>[]);

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async {
    final t = DateTime.fromMillisecondsSinceEpoch(0);
    return Ok<Tag, AppError>(
      Tag(id: name, name: name, createdAt: t, updatedAt: t),
    );
  }

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

class _NoopMetadataFetchService implements MetadataFetchService {
  @override
  Future<UrlMetadata> fetch(String url) async => const UrlMetadata();

  @override
  void close() {}
}

Bookmark _bm(String id, {DateTime? createdAt, String? title}) {
  final t = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: title ?? 'Title $id',
    createdAt: t,
    updatedAt: t,
  );
}

Tag _tag(String id, String name) => Tag(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

TagWithCount _twc(String id, String name, int count) =>
    TagWithCount(tag: _tag(id, name), count: count);

ProviderContainer _makeContainer({
  Stream<List<TagWithCount>>? tagsStream,
  Stream<List<Bookmark>>? bookmarksStream,
  String? bookmarksStreamForTagId,
  IBookmarkRepository? bookmarkRepo,
}) {
  return ProviderContainer(overrides: [
    bookmarkRepositoryProvider
        .overrideWithValue(bookmarkRepo ?? _NoopBookmarkRepo()),
    tagRepositoryProvider.overrideWithValue(_NoopTagRepo()),
    metadataFetchServiceProvider
        .overrideWithValue(_NoopMetadataFetchService()),
    if (tagsStream != null)
      watchTagsWithCountsProvider.overrideWith((ref) => tagsStream),
    if (bookmarksStream != null && bookmarksStreamForTagId != null)
      watchBookmarksForTagProvider(bookmarksStreamForTagId)
          .overrideWith((ref) => bookmarksStream),
  ]);
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: TagsScreen()),
    ),
  ).withTheme();
}

extension on Widget {
  Widget withTheme() {
    return Theme(data: AppTheme.build(), child: this);
  }
}

void main() {
  testWidgets('renders placeholder when no tag selected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final container = _makeContainer(
      tagsStream: Stream.value(const <TagWithCount>[]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Select a tag from the sidebar'), findsOneWidget);
  });

  testWidgets(
      'renders empty placeholder when tag selected but no bookmarks linked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final container = _makeContainer(
      tagsStream: Stream.value([_twc('t1', 'flutter', 0)]),
      bookmarksStream: Stream.value(const <Bookmark>[]),
      bookmarksStreamForTagId: 't1',
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t1');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks with this tag'), findsOneWidget);
  });

  testWidgets(
      'renders bookmark list when bookmarks exist for the selected tag',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final bookmarks = [
      _bm('b1', createdAt: DateTime.fromMillisecondsSinceEpoch(3000)),
      _bm('b2', createdAt: DateTime.fromMillisecondsSinceEpoch(2000)),
      _bm('b3', createdAt: DateTime.fromMillisecondsSinceEpoch(1000)),
    ];
    final container = _makeContainer(
      tagsStream: Stream.value([_twc('t1', 'flutter', 3)]),
      bookmarksStream: Stream.value(bookmarks),
      bookmarksStreamForTagId: 't1',
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t1');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsNWidgets(3));
    expect(find.text('No bookmarks with this tag'), findsNothing);
  });

  testWidgets('bookmark list preserves the stream ordering', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final bookmarks = [
      _bm('b1', title: 'Newest'),
      _bm('b2', title: 'Middle'),
      _bm('b3', title: 'Oldest'),
    ];
    final container = _makeContainer(
      tagsStream: Stream.value([_twc('t1', 'flutter', 3)]),
      bookmarksStream: Stream.value(bookmarks),
      bookmarksStreamForTagId: 't1',
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t1');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final newestY = tester.getTopLeft(find.text('Newest')).dy;
    final middleY = tester.getTopLeft(find.text('Middle')).dy;
    final oldestY = tester.getTopLeft(find.text('Oldest')).dy;
    expect(newestY, lessThan(middleY));
    expect(middleY, lessThan(oldestY));
  });

  testWidgets('error placeholder when bookmark stream errors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final container = _makeContainer(
      tagsStream: Stream.value([_twc('t1', 'flutter', 3)]),
      bookmarksStream: Stream<List<Bookmark>>.error(StateError('boom')),
      bookmarksStreamForTagId: 't1',
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t1');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Could not load bookmarks'), findsOneWidget);
  });

  testWidgets(
      'falls back to placeholder when selectedTagId points to a non-existent '
      'tag (defensive guard mirrors FoldersScreen.folderExists)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final container = _makeContainer(
      // Tags stream emits a list NOT containing the selected id.
      tagsStream: Stream.value([_twc('t-other', 'other', 0)]),
      bookmarksStream: Stream.value(const <Bookmark>[]),
      bookmarksStreamForTagId: 't-deleted',
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t-deleted');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Select a tag from the sidebar'), findsOneWidget);
    expect(find.text('No bookmarks with this tag'), findsNothing);
  });

  testWidgets('switches lists when selectedTagId changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    final aBookmarks = [
      _bm('a1', title: 'In tag A'),
      _bm('a2', title: 'Also A'),
      _bm('a3', title: 'Third A'),
    ];
    final bBookmarks = [_bm('b1', title: 'Solo in B')];

    final container = ProviderContainer(overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_NoopBookmarkRepo()),
      tagRepositoryProvider.overrideWithValue(_NoopTagRepo()),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      watchTagsWithCountsProvider.overrideWith(
        (ref) => Stream.value([
          _twc('tA', 'A', 3),
          _twc('tB', 'B', 1),
        ]),
      ),
      watchBookmarksForTagProvider('tA')
          .overrideWith((ref) => Stream.value(aBookmarks)),
      watchBookmarksForTagProvider('tB')
          .overrideWith((ref) => Stream.value(bBookmarks)),
    ]);
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('tA');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsNWidgets(3));
    expect(find.text('In tag A'), findsOneWidget);

    container.read(selectedTagIdProvider.notifier).select('tB');
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(find.text('Solo in B'), findsOneWidget);
    expect(find.text('In tag A'), findsNothing);
  });
}
