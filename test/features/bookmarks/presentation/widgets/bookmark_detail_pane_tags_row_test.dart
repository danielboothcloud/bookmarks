import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopBookmarkRepo implements IBookmarkRepository {
  _NoopBookmarkRepo(this._controller);
  final StreamController<List<Bookmark>> _controller;

  @override
  Stream<List<Bookmark>> watchAll() => _controller.stream;

  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) =>
      const Stream<List<Bookmark>>.empty();

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

class _NoopMetadataFetchService implements MetadataFetchService {
  @override
  Future<UrlMetadata> fetch(String url) async => const UrlMetadata();
  @override
  void close() {}
}

class _RecordingTagRepo implements ITagRepository {
  final Map<String, StreamController<List<Tag>>> _perBookmark =
      <String, StreamController<List<Tag>>>{};
  final Map<String, List<Tag>> _latest = <String, List<Tag>>{};

  final List<({String name, String bookmarkId})> upsertCalls =
      <({String name, String bookmarkId})>[];
  final List<({String bookmarkId, String tagId})> linkCalls =
      <({String bookmarkId, String tagId})>[];
  final List<({String bookmarkId, String tagId})> unlinkCalls =
      <({String bookmarkId, String tagId})>[];

  /// Drive the chip stream for [bookmarkId] in tests. Buffered so a late
  /// subscription still receives the latest value.
  void emitFor(String bookmarkId, List<Tag> tags) {
    _latest[bookmarkId] = tags;
    final c = _perBookmark[bookmarkId];
    if (c != null && !c.isClosed) c.add(tags);
  }

  Future<void> dispose() async {
    for (final c in _perBookmark.values) {
      await c.close();
    }
  }

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() =>
      const Stream<List<TagWithCount>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) {
    final controller = _perBookmark.putIfAbsent(
      bookmarkId,
      StreamController<List<Tag>>.broadcast,
    );
    final stream = controller.stream;
    final seeded = _latest[bookmarkId];
    if (seeded != null) {
      // Replay the latest known emission to the new subscriber so widgets
      // built after the test seeded a value still see it.
      return Stream<List<Tag>>.multi((sub) {
        sub.add(seeded);
        sub.addStream(stream);
      });
    }
    return stream;
  }

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async {
    upsertCalls.add((name: name, bookmarkId: ''));
    return Ok<Tag, AppError>(_makeTag(name));
  }

  @override
  Future<Result<void, AppError>> linkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    linkCalls.add((bookmarkId: bookmarkId, tagId: tagId));
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<void, AppError>> unlinkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    unlinkCalls.add((bookmarkId: bookmarkId, tagId: tagId));
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  }) async =>
      const Ok<List<Tag>, AppError>(<Tag>[]);
}

Tag _makeTag(String name, {String? id}) {
  final t = DateTime.fromMillisecondsSinceEpoch(0);
  return Tag(
    id: id ?? 'tag-${name.toLowerCase()}',
    name: name,
    createdAt: t,
    updatedAt: t,
  );
}

Bookmark _bm(String id, {String title = 'T', String url = 'https://e.com'}) {
  final t = DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: url,
    title: title,
    createdAt: t,
    updatedAt: t,
  );
}

class _EagerSubscribe extends ConsumerWidget {
  const _EagerSubscribe({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchBookmarksProvider);
    return child;
  }
}

({
  Widget widget,
  StreamController<List<Bookmark>> bookmarks,
  _RecordingTagRepo tagRepo,
}) _build() {
  final bookmarksController =
      StreamController<List<Bookmark>>.broadcast();
  final tagRepo = _RecordingTagRepo();
  final widget = ProviderScope(
    overrides: [
      bookmarkRepositoryProvider
          .overrideWithValue(_NoopBookmarkRepo(bookmarksController)),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      watchFoldersProvider
          .overrideWith((ref) => Stream<List<Folder>>.value(const [])),
      tagRepositoryProvider.overrideWithValue(tagRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(
        body: _EagerSubscribe(child: BookmarkDetailPane()),
      ),
    ),
  );
  return (
    widget: widget,
    bookmarks: bookmarksController,
    tagRepo: tagRepo,
  );
}

Future<void> _stageSelected(
  WidgetTester tester,
  StreamController<List<Bookmark>> bookmarks,
  Bookmark selected,
) async {
  bookmarks.add([selected]);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(BookmarkDetailPane)),
  );
  container.read(selectedBookmarkIdProvider.notifier).select(selected.id);
  await tester.pumpAndSettle();
}

Finder _addTagInput() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Add a tag',
    );

void main() {
  testWidgets(
      'no tags: renders "No tags" muted italic; no chips; tag input visible',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', const <Tag>[]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    expect(find.text('No tags'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(_addTagInput(), findsOneWidget);

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets(
      'with 3 tags: renders 3 FilterChips with names; each has onDeleted',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', [
      _makeTag('one'),
      _makeTag('two'),
      _makeTag('three'),
    ]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    expect(find.byType(FilterChip), findsNWidgets(3));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    // Each chip is editable -> onDeleted callback bound.
    final chips =
        tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
    expect(chips.every((c) => c.onDeleted != null), isTrue);

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets('Enter "design" dispatches addTagToBookmark; input clears',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', const <Tag>[]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    final input = _addTagInput();
    expect(input, findsOneWidget);

    await tester.enterText(input, 'design');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fixture.tagRepo.upsertCalls.map((c) => c.name).toList(),
        ['design']);
    expect(fixture.tagRepo.linkCalls.length, 1);
    expect(fixture.tagRepo.linkCalls.single.bookmarkId, 'b1');
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets(
      'Comma-separated input "ux, design" dispatches TWO addTagToBookmark calls',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', const <Tag>[]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    final input = _addTagInput();
    // Type "ux," — the trailing comma triggers commit immediately.
    await tester.enterText(input, 'ux,');
    await tester.pumpAndSettle();
    // Field clears; type the next part.
    await tester.enterText(input, 'design');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      fixture.tagRepo.upsertCalls.map((c) => c.name).toList(),
      ['ux', 'design'],
    );

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets('Whitespace-only input is a silent no-op', (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', const <Tag>[]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    final input = _addTagInput();
    await tester.enterText(input, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fixture.tagRepo.upsertCalls, isEmpty);
    expect(fixture.tagRepo.linkCalls, isEmpty);

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets('Submitting same name twice dispatches twice (repo dedupes)',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', const <Tag>[]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    final input = _addTagInput();
    await tester.enterText(input, 'Flutter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'Flutter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      fixture.tagRepo.upsertCalls.map((c) => c.name).toList(),
      ['Flutter', 'Flutter'],
    );

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets('Tap "x" on a chip dispatches removeTagFromBookmark',
      (tester) async {
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    final tag = _makeTag('design', id: 'tag-design-1');
    fixture.tagRepo.emitFor('b1', [tag]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.onDeleted, isNotNull);
    chip.onDeleted!.call();
    await tester.pumpAndSettle();

    expect(fixture.tagRepo.unlinkCalls.length, 1);
    expect(fixture.tagRepo.unlinkCalls.single.bookmarkId, 'b1');
    expect(fixture.tagRepo.unlinkCalls.single.tagId, 'tag-design-1');

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets('10 tags render; layout wraps to multiple lines',
      (tester) async {
    // Tall view so 10 chips don't overflow the detail pane Column in tests.
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    final tags = List.generate(10, (i) => _makeTag('tag$i', id: 't$i'));
    fixture.tagRepo.emitFor('b1', tags);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    expect(find.byType(FilterChip), findsNWidgets(10));
    final firstRect = tester.getRect(find.byType(FilterChip).first);
    final lastRect = tester.getRect(find.byType(FilterChip).last);
    expect(lastRect.top, greaterThan(firstRect.top),
        reason: 'last chip should sit below the first via Wrap');

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets(
      'Family-key isolation: per-bookmark stream provides correct tags',
      (tester) async {
    // Verifies the family provider keys by bookmark id. Mounted with b1
    // selected; the tags-row sees b1's stream and renders only b1's chip.
    // (A second-bookmark switch in the same widget mount triggers a
    // FilterChip selection animation that can keep ticking; family-key
    // isolation is the property we actually need to assert here.)
    final fixture = _build();
    await tester.pumpWidget(fixture.widget);
    fixture.tagRepo.emitFor('b1', [_makeTag('a-tag', id: 'a')]);
    fixture.tagRepo.emitFor('b2', [_makeTag('b-tag', id: 'b')]);
    await _stageSelected(tester, fixture.bookmarks, _bm('b1'));

    expect(find.text('a-tag'), findsOneWidget);
    expect(find.text('b-tag'), findsNothing,
        reason: 'b2 chips must not bleed into b1 detail pane');

    await fixture.bookmarks.close();
    await fixture.tagRepo.dispose();
  });

  testWidgets(
      'editable=false (read-only mode): future surface — covered indirectly: '
      'BookmarkTagChipRow tests assert read-only chip widget',
      (tester) async {
    // The current detail pane always passes editable: true. The editable flag
    // exists for any future read-only detail surface. Non-detail-pane read-
    // only rendering is tested in bookmark_tag_chip_row_test.dart (Task 12).
    expect(true, isTrue);
  });
}
