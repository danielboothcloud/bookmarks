import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_folder_field.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/inline_add_form.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IBookmarkRepository {
  final List<Bookmark> savedBookmarks = [];

  @override
  Stream<List<Bookmark>> watchAll() =>
      Stream<List<Bookmark>>.value(const <Bookmark>[]);

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    savedBookmarks.add(bookmark);
    return Ok<Bookmark, AppError>(bookmark);
  }

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

Folder _folder(String id, String name) => Folder(
      id: id,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

/// `SelectedFolderIdNotifier` whose `build()` returns a pre-seeded value.
/// Used to inject an initial selection BEFORE [InlineAddForm.initState] runs
/// (which is when the form reads the provider for its pre-fill). Modifying
/// the provider from a widget life-cycle is rejected by Riverpod, so we
/// override the notifier instead.
class _PreseededFolderIdNotifier extends SelectedFolderIdNotifier {
  _PreseededFolderIdNotifier(this._initial);
  final String? _initial;
  @override
  String? build() => _initial;
}

Widget _wrap({
  required IBookmarkRepository repo,
  required VoidCallback onClose,
  String? initialSelectedFolderId,
  List<Folder> folders = const [],
}) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
      watchFoldersProvider
          .overrideWith((ref) => Stream<List<Folder>>.value(folders)),
      selectedFolderIdProvider.overrideWith(
        () => _PreseededFolderIdNotifier(initialSelectedFolderId),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: _Eager(child: InlineAddForm(onClose: onClose)),
      ),
    ),
  );
}

/// Eagerly subscribes to the folders stream so its emission lands before
/// `BookmarkFolderField` materialises.
class _Eager extends ConsumerWidget {
  const _Eager({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchFoldersProvider);
    return child;
  }
}

void main() {
  testWidgets(
      'opens with no pre-fill when selectedFolderIdProvider is null',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkFolderField), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'opens with pre-filled folder when selectedFolderIdProvider is set',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      initialSelectedFolderId: 'a',
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('Personal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting a folder in the picker updates the field label',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      folders: [_folder('a', 'Personal'), _folder('b', 'Work')],
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('Work'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Save dispatches addBookmark with the picked folderId',
      (tester) async {
    final repo = _FakeRepo();
    var closed = false;
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () => closed = true,
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    // Type a URL.
    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.pumpAndSettle();

    // Pick a folder.
    await tester.tap(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();

    // Save.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, hasLength(1));
    expect(repo.savedBookmarks.last.folderId, 'a');
    expect(repo.savedBookmarks.last.url, 'https://example.com');
    expect(closed, isTrue);
  });

  testWidgets('Save with no folder picked dispatches folderId == null',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, hasLength(1));
    expect(repo.savedBookmarks.last.folderId, isNull);
  });

  testWidgets(
      'selecting "No folder" clears a pre-fill so save lands unfiled',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      initialSelectedFolderId: 'a',
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    // Open picker via the field's "Personal" label.
    await tester.tap(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('Personal'),
      ),
    );
    await tester.pumpAndSettle();

    // Pick "No folder".
    await tester.tap(find.text('No folder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, hasLength(1));
    expect(repo.savedBookmarks.last.folderId, isNull);
  });

  testWidgets('pressing Enter in URL field saves with current folderId',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      initialSelectedFolderId: 'a',
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    final urlField = find.byType(TextField).first;
    await tester.enterText(urlField, 'https://example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, hasLength(1));
    expect(repo.savedBookmarks.last.folderId, 'a');
  });

  testWidgets('pressing Esc cancels without saving', (tester) async {
    final repo = _FakeRepo();
    var closed = false;
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () => closed = true,
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, isEmpty);
    expect(closed, isTrue);
  });

  testWidgets('empty URL surfaces the URL error and does NOT save',
      (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_wrap(
      repo: repo,
      onClose: () {},
      initialSelectedFolderId: 'a',
      folders: [_folder('a', 'Personal')],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, isEmpty,
        reason: 'empty URL must block save even when a folder is pre-filled');
    // Confirm the URL field still has focus (the error path requests it).
    final urlField =
        tester.widget<TextField>(find.byType(TextField).first);
    expect(urlField.focusNode!.hasFocus, isTrue);
  });

}
