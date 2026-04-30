import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/favicon_widget.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_detail_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IBookmarkRepository {
  _FakeRepo(this._controller);

  final StreamController<List<Bookmark>> _controller;
  final List<Bookmark> savedBookmarks = [];
  final List<String> deletedIds = [];
  Result<Bookmark, AppError> Function(Bookmark)? saveResult;

  @override
  Stream<List<Bookmark>> watchAll() => _controller.stream;

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    savedBookmarks.add(bookmark);
    return (saveResult ?? Ok<Bookmark, AppError>.new)(bookmark);
  }

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

Bookmark _bm(
  String id, {
  String title = 'Title',
  String url = 'https://example.com',
  String? notes,
  String? faviconBase64,
}) {
  final t = DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: url,
    title: title,
    notes: notes,
    faviconBase64: faviconBase64,
    createdAt: t,
    updatedAt: t,
  );
}

Widget _wrap(IBookmarkRepository repo) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(
        body: _EagerSubscribe(child: BookmarkDetailPane()),
      ),
    ),
  );
}

/// Subscribes to [watchBookmarksProvider] for the entire test so the broadcast
/// emission lands BEFORE the detail pane conditionally watches it. Mirrors the
/// real app where [BookmarkListScreen] is always present.
class _EagerSubscribe extends ConsumerWidget {
  const _EagerSubscribe({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchBookmarksProvider);
    return child;
  }
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(BookmarkDetailPane)),
  );
}

void main() {
  setUp(FaviconWidget.debugClearCache);

  testWidgets('empty state renders Select a bookmark placeholder (AC7)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    expect(find.text('Select a bookmark'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('populated state renders 3 fields, 36px favicon, Open button (AC1)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', title: 'Hello', notes: 'a note')]);
    await tester.pumpAndSettle();

    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);
    final favicon = tester.widget<FaviconWidget>(find.byType(FaviconWidget));
    expect(favicon.size, 36);
  });

  testWidgets('title edit + onEditingComplete saves new title (AC2, AC3)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', title: 'Old')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    await tester.enterText(titleField, 'New Title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, isNotEmpty);
    expect(repo.savedBookmarks.last.title, 'New Title');
  });

  testWidgets('URL edit on blur saves new URL (AC3)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', url: 'https://example.com')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final urlField = find.byType(TextField).at(1);
    await tester.tap(urlField);
    await tester.pumpAndSettle();
    await tester.enterText(urlField, 'https://changed.com');
    // Blur by tapping the title field (different focus target).
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks.last.url, 'https://changed.com');
  });

  testWidgets('notes edit on blur saves new notes (AC5)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final notesField = find.byType(TextField).at(2);
    await tester.tap(notesField);
    await tester.pumpAndSettle();
    await tester.enterText(notesField, 'Hello\nWorld');
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks.last.notes, 'Hello\nWorld');
  });

  testWidgets('blur without changes does not call save (no-op guard)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', title: 'Old')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    // Blur immediately, no edits.
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, isEmpty);
  });

  testWidgets('clearing URL field reverts to original on blur (no-save)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', url: 'https://example.com')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final urlField = find.byType(TextField).at(1);
    await tester.tap(urlField);
    await tester.pumpAndSettle();
    await tester.enterText(urlField, '');
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, isEmpty);
    final field = tester.widget<TextField>(urlField);
    expect(field.controller!.text, 'https://example.com');
  });

  testWidgets('clearing title saves with URL fallback (matches addBookmark)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', title: 'Old', url: 'https://example.com')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    await tester.enterText(titleField, '   ');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks.last.title, 'https://example.com');
  });

  testWidgets(
      'half-typed title is preserved when an external bookmark update arrives '
      '(stale-controller guard via _lastBookmarkId)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', title: 'Old')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    await tester.tap(titleField);
    await tester.pumpAndSettle();
    await tester.enterText(titleField, 'half-typed');
    // Do NOT blur. Simulate an external update (e.g. favicon fetch landing).
    controller.add([_bm('a', title: 'Old', faviconBase64: 'data:image/png;base64,xx')]);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(titleField);
    expect(field.controller!.text, 'half-typed',
        reason: 'controllers must NOT reset when the same id re-emits');
  });

  testWidgets('Tab traverses title -> URL -> notes in logical order (AC6)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('a', notes: 'n')]);
    await tester.pumpAndSettle();
    _container(tester).read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    final urlField = find.byType(TextField).at(1);
    final notesField = find.byType(TextField).at(2);

    await tester.tap(titleField);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(titleField).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(urlField).focusNode!.hasFocus, isTrue,
        reason: 'Tab from title must focus URL');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(notesField).focusNode!.hasFocus, isTrue,
        reason: 'Tab from URL must focus notes');
  });

  group('delete flow (Story 1.5 -- moved into detail pane)', () {
    testWidgets('trash icon prompts pendingDeleteIdProvider', (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('a', title: 'Hello')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('a');
      await tester.pumpAndSettle();

      expect(c.read(pendingDeleteIdProvider), isNull);
      await tester.tap(find.byTooltip('Delete bookmark'));
      await tester.pumpAndSettle();

      expect(c.read(pendingDeleteIdProvider), 'a');
    });

    testWidgets(
        'confirmation view shows title preview and Cancel-before-Delete button order',
        (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('a', title: 'My Bookmark')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('a');
      c.read(pendingDeleteIdProvider.notifier).prompt('a');
      await tester.pumpAndSettle();

      expect(find.text('Delete this bookmark?'), findsOneWidget);
      expect(find.text('My Bookmark'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'editing fields hide while confirming');

      final cancelRect =
          tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      final deleteRect =
          tester.getRect(find.widgetWithText(TextButton, 'Delete'));
      expect(cancelRect.left, lessThan(deleteRect.left));
    });

    testWidgets('Cancel clears pendingDeleteIdProvider, returns to populated body',
        (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('a', title: 'Hello')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('a');
      c.read(pendingDeleteIdProvider.notifier).prompt('a');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(c.read(pendingDeleteIdProvider), isNull);
      expect(find.byType(TextField), findsNWidgets(3),
          reason: 'editing fields return after cancel');
    });

    testWidgets(
        'Delete dispatches deleteBookmark, clears confirmation, migrates '
        'selection to next item', (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('a'), _bm('b'), _bm('c')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('a');
      c.read(pendingDeleteIdProvider.notifier).prompt('a');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['a']);
      expect(c.read(pendingDeleteIdProvider), isNull);
      expect(c.read(selectedBookmarkIdProvider), 'b',
          reason: 'selection migrates to the immediate successor');
    });

    testWidgets('Enter on the confirmation view confirms delete', (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('a'), _bm('b')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('a');
      c.read(pendingDeleteIdProvider.notifier).prompt('a');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['a']);
      expect(c.read(pendingDeleteIdProvider), isNull);
    });

    testWidgets('Delete on the last item clears selection (no successor)',
        (tester) async {
      final controller = StreamController<List<Bookmark>>.broadcast();
      addTearDown(controller.close);
      final repo = _FakeRepo(controller);

      await tester.pumpWidget(_wrap(repo));
      controller.add([_bm('only')]);
      await tester.pumpAndSettle();
      final c = _container(tester);
      c.read(selectedBookmarkIdProvider.notifier).select('only');
      c.read(pendingDeleteIdProvider.notifier).prompt('only');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['only']);
      expect(c.read(selectedBookmarkIdProvider), isNull);
    });
  });

  testWidgets('selection swap re-initialises controllers to the new bookmark',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    addTearDown(controller.close);
    final repo = _FakeRepo(controller);

    await tester.pumpWidget(_wrap(repo));
    controller.add([
      _bm('a', title: 'Alpha', url: 'https://a.com'),
      _bm('b', title: 'Beta', url: 'https://b.com'),
    ]);
    await tester.pumpAndSettle();
    final c = _container(tester);
    c.read(selectedBookmarkIdProvider.notifier).select('a');
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField).first;
    expect(tester.widget<TextField>(titleField).controller!.text, 'Alpha');

    c.read(selectedBookmarkIdProvider.notifier).select('b');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(titleField).controller!.text, 'Beta');
  });
}
