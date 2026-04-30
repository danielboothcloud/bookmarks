import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
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
}) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
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
}
