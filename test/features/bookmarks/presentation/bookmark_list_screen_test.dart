import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/presentation/bookmark_list_screen.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/inline_add_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IBookmarkRepository {
  _FakeRepo(this._controller);

  final StreamController<List<Bookmark>> _controller;
  final List<Bookmark> _items = [];
  Result<Bookmark, AppError> Function(Bookmark)? saveResult;

  @override
  Stream<List<Bookmark>> watchAll() => _controller.stream;

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    final result = (saveResult ?? Ok<Bookmark, AppError>.new)(bookmark);
    if (result is Ok<Bookmark, AppError>) {
      _items.insert(0, bookmark);
      _controller.add(List.unmodifiable(_items));
    }
    return result;
  }
}

Bookmark _bm(String id, {String? title, DateTime? createdAt}) {
  final now = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: title ?? 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
  );
}

Widget _wrap(IBookmarkRepository repo) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(body: BookmarkListScreen()),
    ),
  );
}

void main() {
  testWidgets('empty stream shows EmptyState.noBookmarks (AC4 negative)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(find.byType(BookmarkListItem), findsNothing);
  });

  testWidgets('non-empty stream renders BookmarkListItem rows (AC4)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    final newer =
        _bm('newer', createdAt: DateTime.fromMillisecondsSinceEpoch(2000));
    final older =
        _bm('older', createdAt: DateTime.fromMillisecondsSinceEpoch(1000));

    await tester.pumpWidget(_wrap(repo));
    // Repository orders by createdAt desc — emit in that order.
    controller.add([newer, older]);
    await tester.pumpAndSettle();

    final items = tester
        .widgetList<BookmarkListItem>(find.byType(BookmarkListItem))
        .toList();
    expect(items.length, 2);
    expect(items.first.bookmark.id, 'newer');
    expect(items.last.bookmark.id, 'older');
  });

  testWidgets('addFormVisibleProvider true shows InlineAddForm above list (AC1)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('one')]);
    await tester.pumpAndSettle();
    expect(find.byType(InlineAddForm), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    expect(find.byType(InlineAddForm), findsOneWidget);
    final formY = tester.getTopLeft(find.byType(InlineAddForm)).dy;
    final listY = tester.getTopLeft(find.byType(BookmarkListItem).first).dy;
    expect(formY, lessThan(listY));
  });

  testWidgets('Esc while form visible flips provider false (AC3)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    // URL field auto-focuses; send Esc.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(container.read(addFormVisibleProvider), isFalse);
    expect(find.byType(InlineAddForm), findsNothing);
  });

  testWidgets(
      'Save with non-empty URL closes the form and the new bookmark appears (AC2)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    final urlField = find.widgetWithText(TextField, 'Paste a URL');
    await tester.enterText(urlField, 'https://example.com/new');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(InlineAddForm), findsNothing);
    expect(container.read(addFormVisibleProvider), isFalse);
    expect(find.byType(BookmarkListItem), findsOneWidget);
    final item = tester.widget<BookmarkListItem>(find.byType(BookmarkListItem));
    expect(item.bookmark.url, 'https://example.com/new');
  });

  testWidgets('save Err surfaces inline calm error banner (H1)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller)
      ..saveResult = (_) => const Err<Bookmark, AppError>(StorageError('boom'));
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Paste a URL'),
      'https://example.com/x',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save bookmark — try again."), findsOneWidget);
  });

  testWidgets('URL field auto-focuses when form opens (AC1)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    final urlField = find.widgetWithText(TextField, 'Paste a URL');
    expect(urlField, findsOneWidget);
    final focusNode = (tester.widget<TextField>(urlField)).focusNode;
    expect(focusNode?.hasFocus, isTrue);
  });
}
