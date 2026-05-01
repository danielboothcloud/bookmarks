import 'dart:async';

import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_card.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/folders/presentation/folders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Folder _f(String id, {String name = 'F', String? parentId, int t = 1000}) =>
    Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t),
    );

Bookmark _b(
  String id, {
  String? folderId,
  String url = 'https://example.com',
  String title = 'T',
}) =>
    Bookmark(
      id: id,
      url: url,
      title: title,
      folderId: folderId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

/// Builds a [ProviderContainer] with eager Stream.value-based overrides so
/// the FoldersScreen always sees AsyncValue.data on first build (no timing
/// races between folder/bookmark stream emissions and the screen's gated
/// subscriptions).
ProviderContainer _container({
  String? selectedFolderId,
  List<Folder> folders = const <Folder>[],
  List<Bookmark>? bookmarks,
  Object? bookmarksError,
}) {
  Stream<List<Bookmark>> bookmarksStream() {
    if (bookmarksError != null) {
      // async* generator that throws -- Riverpod transitions the
      // StreamProvider through `AsyncLoading -> AsyncError`. (A bare
      // StreamController.addError keeps the provider in
      // `AsyncLoading(error:)` because the stream is still open; .when
      // dispatches by runtime subtype, so AsyncLoading would route to the
      // loading branch even though an error is attached.)
      Stream<List<Bookmark>> erroring() async* {
        throw bookmarksError;
      }
      return erroring();
    }
    return Stream.value(bookmarks ?? const <Bookmark>[]);
  }

  final container = ProviderContainer(
    // Disable Riverpod's automatic retry-on-error so the error-case test
    // doesn't loop a 200ms retry timer indefinitely (each retry re-runs the
    // throwing async* stream and reschedules another retry, blocking
    // pumpAndSettle and tripping the binding's pending-timer invariant).
    retry: (_, _) => null,
    overrides: [
      watchFoldersProvider.overrideWith((ref) => Stream.value(folders)),
      watchBookmarksProvider.overrideWith((ref) => bookmarksStream()),
    ],
  );
  if (selectedFolderId != null) {
    container.read(selectedFolderIdProvider.notifier).select(selectedFolderId);
  }
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FoldersScreen())),
    );

void main() {
  testWidgets('No selection -> "Select a folder from the sidebar" placeholder',
      (tester) async {
    final c = _container();

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.text('Select a folder from the sidebar'), findsOneWidget);
    expect(find.byType(BookmarkCard), findsNothing);
  });

  testWidgets(
      'Selected folder with one bookmark -> exactly one BookmarkCard '
      'rendered', (tester) async {
    final c = _container(
      selectedFolderId: 'a',
      folders: [_f('a')],
      bookmarks: [_b('bm1', folderId: 'a')],
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkCard), findsOneWidget);
    expect(find.text('Select a folder from the sidebar'), findsNothing);
  });

  testWidgets(
      'Selected folder with NESTED bookmarks -> grid includes nested '
      '(FR12)', (tester) async {
    // a -> b; bm1 in a, bm2 in b. Selecting 'a' should show both.
    final c = _container(
      selectedFolderId: 'a',
      folders: [
        _f('a', parentId: null),
        _f('b', parentId: 'a'),
      ],
      bookmarks: [
        _b('bm1', folderId: 'a', title: 'TopLevel'),
        _b('bm2', folderId: 'b', title: 'Nested'),
      ],
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkCard), findsNWidgets(2));
  });

  testWidgets(
      'Selected folder with no bookmarks (own or nested) -> empty state',
      (tester) async {
    final c = _container(
      selectedFolderId: 'a',
      folders: [_f('a')],
      bookmarks: const <Bookmark>[],
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks in this folder'), findsOneWidget);
    expect(find.byType(BookmarkCard), findsNothing);
  });

  testWidgets(
      'Selected folder no longer exists -> falls back to no-selection '
      'placeholder (defensive)', (tester) async {
    final c = _container(
      selectedFolderId: 'gone',
      folders: [_f('other')],
      bookmarks: const <Bookmark>[],
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.text('Select a folder from the sidebar'), findsOneWidget);
    expect(find.text('No bookmarks in this folder'), findsNothing);
  });

  testWidgets(
      'Bookmarks load error -> inline "Could not load bookmarks" message',
      (tester) async {
    final c = _container(
      selectedFolderId: 'a',
      folders: [_f('a')],
      bookmarksError: 'boom',
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();
    // Capture the zone-uncaught error so the test framework doesn't fail
    // post-assertion (the provider transitions to AsyncError correctly).
    tester.takeException();

    expect(find.text('Could not load bookmarks'), findsOneWidget);
  });

  testWidgets(
      'Bookmarks in OTHER folders are filtered out (only descendants of '
      'selected are shown)', (tester) async {
    final c = _container(
      selectedFolderId: 'a',
      folders: [_f('a'), _f('z')],
      bookmarks: [
        _b('bm1', folderId: 'a'),
        _b('bm-other', folderId: 'z'), // unrelated folder
        _b('bm-none', folderId: null), // no folder
      ],
    );

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkCard), findsOneWidget);
  });
}
