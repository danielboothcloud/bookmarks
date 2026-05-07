import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/favicon_widget.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_card.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:bookmarks/features/tags/presentation/widgets/bookmark_tag_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopRepo implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

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

class _SeededTagRepo implements ITagRepository {
  _SeededTagRepo(this._tagsByBookmark);
  final Map<String, List<Tag>> _tagsByBookmark;

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() =>
      const Stream<List<TagWithCount>>.empty();

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

Tag _tag(String name) {
  final t = DateTime.fromMillisecondsSinceEpoch(0);
  return Tag(id: name, name: name, createdAt: t, updatedAt: t);
}

Bookmark _bm(String id, {String? title, String? url}) {
  final t = DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: url ?? 'https://example.com/$id',
    title: title ?? 'Title $id',
    createdAt: t,
    updatedAt: t,
  );
}

Widget _wrap({
  required Bookmark bookmark,
  ProviderContainer? container,
  ITagRepository? tagRepo,
}) {
  final theme = AppTheme.build();
  final body = MaterialApp(
    theme: theme,
    home: Scaffold(
      // Constrain so the card has bounded space (it lives in a grid normally).
      body: SizedBox(
        width: 220,
        height: 200,
        child: BookmarkCard(bookmark: bookmark),
      ),
    ),
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: body);
  }
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_NoopRepo()),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      tagRepositoryProvider
          .overrideWithValue(tagRepo ?? _SeededTagRepo(const {})),
    ],
    child: body,
  );
}

void main() {
  testWidgets('renders title, domain (not full URL), and FaviconWidget at 28',
      (tester) async {
    await tester.pumpWidget(_wrap(
      bookmark: _bm('a',
          title: 'Hello', url: 'https://example.com/some/long/path?q=1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget,
        reason: 'card shows the domain only, not the full URL');
    expect(find.text('https://example.com/some/long/path?q=1'), findsNothing);

    final favicon = tester.widget<FaviconWidget>(find.byType(FaviconWidget));
    expect(favicon.size, 28.0);
  });

  testWidgets('single-tap calls selectedBookmarkIdProvider.select(id)',
      (tester) async {
    final container = ProviderContainer(overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_NoopRepo()),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      tagRepositoryProvider.overrideWithValue(_SeededTagRepo(const {})),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(bookmark: _bm('a'), container: container));
    await tester.pumpAndSettle();

    expect(container.read(selectedBookmarkIdProvider), isNull);

    await tester.tap(find.byType(BookmarkCard));
    // GestureDetector(onDoubleTap:) defers single-tap delivery to the
    // InkWell.onTap until the double-tap timeout elapses (~300ms). Advance
    // the fake clock past it so the single-tap selection fires.
    await tester.pump(const Duration(milliseconds: 350));

    expect(container.read(selectedBookmarkIdProvider), 'a');
  });

  testWidgets('selected card border is accent (2px); unselected is 1px',
      (tester) async {
    final container = ProviderContainer(overrides: [
      bookmarkRepositoryProvider.overrideWithValue(_NoopRepo()),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      tagRepositoryProvider.overrideWithValue(_SeededTagRepo(const {})),
    ]);
    addTearDown(container.dispose);

    // Unselected first.
    await tester.pumpWidget(_wrap(bookmark: _bm('a'), container: container));
    await tester.pumpAndSettle();

    Material readMaterial() {
      final materials = tester
          .widgetList<Material>(find.descendant(
            of: find.byType(BookmarkCard),
            matching: find.byType(Material),
          ))
          .toList();
      // The outer Material is the one with a RoundedRectangleBorder shape.
      return materials.firstWhere(
        (m) => m.shape is RoundedRectangleBorder,
      );
    }

    final unselected = readMaterial();
    final unselectedBorder =
        (unselected.shape! as RoundedRectangleBorder).side;
    expect(unselectedBorder.width, 1.0);
    expect(unselectedBorder.color.toARGB32(),
        AppColors.border.toARGB32());

    // Now select.
    container.read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pump();

    final selected = readMaterial();
    final selectedBorder = (selected.shape! as RoundedRectangleBorder).side;
    expect(selectedBorder.width, 2.0);
    expect(selectedBorder.color.toARGB32(),
        AppColors.accent.toARGB32());
  });

  testWidgets('title uses maxLines: 2 with ellipsis overflow',
      (tester) async {
    await tester.pumpWidget(_wrap(
      bookmark: _bm('a',
          title:
              'A very long title that absolutely will not fit in a single '
              'line when constrained to 220px because it just keeps going'),
    ));
    await tester.pumpAndSettle();

    final titles = tester.widgetList<Text>(find.descendant(
      of: find.byType(BookmarkCard),
      matching: find.byType(Text),
    ));
    final titleText = titles.firstWhere(
      (t) => (t.data ?? '').startsWith('A very long title'),
    );
    expect(titleText.maxLines, 2);
    expect(titleText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('domain falls back to raw URL when host is empty',
      (tester) async {
    // A URL with no host -> `_domain` should fall back to the raw string.
    await tester.pumpWidget(
      _wrap(bookmark: _bm('a', url: 'not-a-url')),
    );
    await tester.pumpAndSettle();

    expect(find.text('not-a-url'), findsOneWidget);
  });

  testWidgets('card with no tags renders the chip-row widget at zero height',
      (tester) async {
    await tester.pumpWidget(_wrap(bookmark: _bm('a')));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkTagChipRow), findsOneWidget);
    final size = tester.getSize(find.byType(BookmarkTagChipRow));
    expect(size.height, 0,
        reason: 'no-tags state collapses to SizedBox.shrink');
  });

  testWidgets('card with 2 tags renders the chip names below the URL row',
      (tester) async {
    final tagRepo = _SeededTagRepo({
      'a': [_tag('design'), _tag('ux')],
    });
    await tester.pumpWidget(_wrap(bookmark: _bm('a'), tagRepo: tagRepo));
    await tester.pumpAndSettle();

    expect(find.text('design'), findsOneWidget);
    expect(find.text('ux'), findsOneWidget);
  });
}
