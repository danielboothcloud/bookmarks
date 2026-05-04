import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/presentation/widgets/bookmark_tag_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StreamingTagRepo implements ITagRepository {
  final Map<String, StreamController<List<Tag>>> _per =
      <String, StreamController<List<Tag>>>{};
  final Map<String, List<Tag>> _latest = <String, List<Tag>>{};

  void emit(String bookmarkId, List<Tag> tags) {
    _latest[bookmarkId] = tags;
    final c = _per[bookmarkId];
    if (c != null && !c.isClosed) c.add(tags);
  }

  Future<void> dispose() async {
    for (final c in _per.values) {
      await c.close();
    }
  }

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) {
    final controller = _per.putIfAbsent(
      bookmarkId,
      StreamController<List<Tag>>.broadcast,
    );
    final seeded = _latest[bookmarkId];
    if (seeded != null) {
      return Stream<List<Tag>>.multi((sub) {
        sub.add(seeded);
        sub.addStream(controller.stream);
      });
    }
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
      AppError>(_tag(name));

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

Tag _tag(String name) {
  final t = DateTime.fromMillisecondsSinceEpoch(0);
  return Tag(id: name, name: name, createdAt: t, updatedAt: t);
}

Widget _wrap(_StreamingTagRepo repo, String bookmarkId) {
  return ProviderScope(
    overrides: [tagRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: BookmarkTagChipRow(bookmarkId: bookmarkId),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('with no tags renders SizedBox.shrink (zero size)',
      (tester) async {
    final repo = _StreamingTagRepo();
    repo.emit('b1', const <Tag>[]);
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkTagChipRow), findsOneWidget);
    final size = tester.getSize(find.byType(BookmarkTagChipRow));
    expect(size.height, 0);

    await repo.dispose();
  });

  testWidgets('with 1 tag renders the tag name verbatim', (tester) async {
    final repo = _StreamingTagRepo();
    repo.emit('b1', [_tag('design')]);
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();

    expect(find.text('design'), findsOneWidget);

    await repo.dispose();
  });

  testWidgets('with 5 tags renders all 5 chip Texts', (tester) async {
    final repo = _StreamingTagRepo();
    repo.emit('b1', [
      _tag('one'),
      _tag('two'),
      _tag('three'),
      _tag('four'),
      _tag('five'),
    ]);
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    expect(find.text('four'), findsOneWidget);
    expect(find.text('five'), findsOneWidget);

    await repo.dispose();
  });

  testWidgets('long tag name uses TextOverflow.ellipsis; layout stays valid',
      (tester) async {
    final repo = _StreamingTagRepo();
    repo.emit('b1', [_tag('a' * 50)]);
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('a' * 50));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);

    await repo.dispose();
  });

  testWidgets(
      'overflow: "+N" badge appears when chips cannot all fit in the row',
      (tester) async {
    final repo = _StreamingTagRepo();
    // 5 tags with 20-char names. Heuristic: _chipWidth = 12 + 20*7 = 152px.
    // First chip (152px) + overflow reserve (4 + 26 = 30px) = 182 ≤ 300 → fits.
    // Second chip check: 152 + 4 + 152 + 30 = 338 > 300 → break.
    // Result: 1 visible chip + "+4" badge.
    repo.emit('b1', [
      _tag('average-long-name-00'),
      _tag('average-long-name-01'),
      _tag('average-long-name-02'),
      _tag('average-long-name-03'),
      _tag('average-long-name-04'),
    ]);
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();

    expect(find.text('average-long-name-00'), findsOneWidget);
    expect(find.text('average-long-name-04'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('+') ?? false),
      ),
      findsOneWidget,
    );

    await repo.dispose();
  });

  testWidgets('stream update: 0 -> 1 chip appears via the family stream',
      (tester) async {
    final repo = _StreamingTagRepo();
    // Start empty (no seed).
    await tester.pumpWidget(_wrap(repo, 'b1'));
    await tester.pumpAndSettle();
    repo.emit('b1', const <Tag>[]);
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);

    repo.emit('b1', [_tag('appeared')]);
    await tester.pumpAndSettle();

    expect(find.text('appeared'), findsOneWidget);

    await repo.dispose();
  });
}
