import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart' show Folder;
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopBookmarkRepo implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

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

Tag _tag(String id, String name) => Tag(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

TagWithCount _twc(String id, String name, int count) =>
    TagWithCount(tag: _tag(id, name), count: count);

ProviderContainer _container({
  required Stream<List<TagWithCount>> tagsStream,
}) {
  return ProviderContainer(overrides: [
    bookmarkRepositoryProvider.overrideWithValue(_NoopBookmarkRepo()),
    watchFoldersProvider
        .overrideWith((ref) => const Stream<List<Folder>>.empty()),
    watchTagsWithCountsProvider.overrideWith((ref) => tagsStream),
  ]);
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.build(),
      routerConfig: buildRouter(),
    ),
  );
}

void main() {
  testWidgets('renders nothing when zero tags exist', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value(const <TagWithCount>[]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    // No TAGS header rendered when the list is empty.
    expect(find.text('TAGS'), findsNothing);
  });

  testWidgets('renders TAGS header and rows when tags exist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([
        _twc('t1', 'apple', 3),
        _twc('t2', 'banana', 0),
      ]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('TAGS'), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('banana'), findsOneWidget);
  });

  testWidgets('count includes tags with zero linked bookmarks (FR16)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([_twc('t1', 'lonely', 0)]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('renders rows in stream order (widget does not re-sort)',
      (tester) async {
    // The repo enforces alpha COLLATE NOCASE ordering. The widget MUST NOT
    // re-sort -- a re-sort would mask a bug in the repo.
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([
        _twc('t1', 'zebra', 1),
        _twc('t2', 'apple', 1),
      ]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final zebraTopY =
        tester.getTopLeft(find.text('zebra')).dy;
    final appleTopY =
        tester.getTopLeft(find.text('apple')).dy;
    expect(zebraTopY, lessThan(appleTopY));
  });

  testWidgets(
      'tapping a row sets selectedTagIdProvider and navigates to tags branch',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([_twc('t1', 'flutter', 2)]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(container.read(selectedTagIdProvider), isNull);

    await tester.tap(find.text('flutter'));
    await tester.pumpAndSettle();

    expect(container.read(selectedTagIdProvider), 't1');
    // Routed to /tags branch.
    expect(find.text('No bookmarks with this tag'), findsOneWidget);
  });

  testWidgets(
      'Semantics label uses singular "bookmark" when count is 1, plural otherwise',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([
        _twc('t1', 'singular', 1),
        _twc('t2', 'plural', 2),
        _twc('t3', 'zero', 0),
      ]),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final semanticsWithLabel = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((w) => w.properties.label)
        .whereType<String>()
        .toList();

    expect(
      semanticsWithLabel,
      contains('singular, 1 bookmark'),
      reason: 'count == 1 must use singular noun',
    );
    expect(
      semanticsWithLabel,
      contains('plural, 2 bookmarks'),
      reason: 'count > 1 must use plural noun',
    );
    expect(
      semanticsWithLabel,
      contains('zero, 0 bookmarks'),
      reason: 'count == 0 keeps plural ("0 bookmarks") to read naturally',
    );
  });

  testWidgets('selected row uses accent left border', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container(
      tagsStream: Stream.value([_twc('t1', 'flutter', 2)]),
    );
    addTearDown(container.dispose);

    container.read(selectedTagIdProvider.notifier).select('t1');

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
      final deco = c.decoration;
      if (deco is! BoxDecoration) return false;
      final border = deco.border;
      if (border is! Border) return false;
      return border.left.color == AppColors.accent &&
          border.left.width == 3;
    });
    expect(containers, isNotEmpty,
        reason: 'Selected tag row must render an accent left border (3px)');
  });
}
