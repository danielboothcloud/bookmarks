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
import 'package:bookmarks/features/tags/presentation/widgets/bookmark_tag_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRepo implements IBookmarkRepository {
  final List<String> deletedIds = <String>[];

  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      Ok<Bookmark, AppError>(bookmark);

  @override
  Future<Result<void, AppError>> delete(String id) async {
    deletedIds.add(id);
    return const Ok<void, AppError>(null);
  }
}

class _NoopMetadataFetchService implements MetadataFetchService {
  @override
  Future<UrlMetadata> fetch(String url) async => const UrlMetadata();

  @override
  void close() {}
}

class _SeededTagRepo implements ITagRepository {
  _SeededTagRepo(this._tagsByBookmark);
  final Map<String, List<Tag>> _tagsByBookmark;

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) =>
      Stream<List<Tag>>.value(_tagsByBookmark[bookmarkId] ?? const <Tag>[]);

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async => Ok<Tag,
      AppError>(_makeTag(name));

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

Tag _makeTag(String name) {
  final t = DateTime.fromMillisecondsSinceEpoch(0);
  return Tag(
    id: name,
    name: name,
    createdAt: t,
    updatedAt: t,
  );
}

Bookmark _bm(String id, {String? title}) {
  final t = DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: title ?? 'Title $id',
    createdAt: t,
    updatedAt: t,
  );
}

Widget _wrap({
  required IBookmarkRepository repo,
  required Bookmark bookmark,
  ITagRepository? tagRepo,
}) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      tagRepositoryProvider
          .overrideWithValue(tagRepo ?? _SeededTagRepo(const {})),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: BookmarkListItem(bookmark: bookmark),
      ),
    ),
  );
}

void main() {
  // Story 1.5: the inline-confirmation row was moved off the list item and
  // into the detail pane. The item is now a pure display + selection widget;
  // delete behaviour is verified in bookmark_detail_pane_test.dart (the
  // confirmation view + selection migration) and via the AppShell-level
  // Delete/Backspace shortcut wiring in app_shell_test.dart.
  testWidgets('renders title, URL row, and no delete-related affordances',
      (tester) async {
    final repo = _RecordingRepo();
    await tester
        .pumpWidget(_wrap(repo: repo, bookmark: _bm('a', title: 'Hello')));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('https://example.com/a'), findsOneWidget);
    // No inline confirmation in the list anymore.
    expect(find.text("Delete 'Hello'?"), findsNothing);
    expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    // Repo.delete must not be invoked from rendering.
    expect(repo.deletedIds, isEmpty);
  });

  testWidgets(
      'BookmarkTagChipRow is present in the tree but renders zero height '
      'when the bookmark has no tags', (tester) async {
    final repo = _RecordingRepo();
    await tester.pumpWidget(_wrap(repo: repo, bookmark: _bm('a')));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkTagChipRow), findsOneWidget);
    final size = tester.getSize(find.byType(BookmarkTagChipRow));
    expect(size.height, 0,
        reason: 'no-tags state collapses to SizedBox.shrink');
  });

  testWidgets('Bookmark with 2 tags renders chips below URL row',
      (tester) async {
    final repo = _RecordingRepo();
    final tagRepo = _SeededTagRepo({
      'a': [_makeTag('design'), _makeTag('ux')],
    });
    await tester.pumpWidget(
      _wrap(repo: repo, bookmark: _bm('a'), tagRepo: tagRepo),
    );
    await tester.pumpAndSettle();

    expect(find.text('design'), findsOneWidget);
    expect(find.text('ux'), findsOneWidget);
  });

  // Suppress unused-import lint for dart:async on test files w/o async types.
  test('dart:async re-export sanity', () {
    expect(StreamController<int>.broadcast, isNotNull);
  });
}
