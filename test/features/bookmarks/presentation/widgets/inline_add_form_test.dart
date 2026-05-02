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
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IBookmarkRepository {
  final List<Bookmark> savedBookmarks = [];
  int saveAttempts = 0;
  bool failNextSave = false;

  @override
  Stream<List<Bookmark>> watchAll() =>
      Stream<List<Bookmark>>.value(const <Bookmark>[]);

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    saveAttempts++;
    if (failNextSave) {
      failNextSave = false;
      return const Err<Bookmark, AppError>(StorageError('boom'));
    }
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

  // ------------------------------------------------------------------
  // Self-heal tests (Story 2.4 -- closes Story 2.3 deferred M4)
  // ------------------------------------------------------------------

  Widget wrapStream({
    required IBookmarkRepository repo,
    required Stream<List<Folder>> foldersStream,
    String? initialSelectedFolderId,
  }) {
    return ProviderScope(
      overrides: [
        bookmarkRepositoryProvider.overrideWithValue(repo),
        metadataFetchServiceProvider
            .overrideWithValue(_NoopMetadataFetchService()),
        watchFoldersProvider.overrideWith((ref) => foldersStream),
        selectedFolderIdProvider.overrideWith(
          () => _PreseededFolderIdNotifier(initialSelectedFolderId),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: _Eager(child: InlineAddForm(onClose: () {})),
        ),
      ),
    );
  }

  testWidgets(
      'self-heal: when the pre-filled folder is removed, _pendingFolderId '
      'resets to null and Save dispatches folderId == null', (tester) async {
    final repo = _FakeRepo();
    final controller = StreamController<List<Folder>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(wrapStream(
      repo: repo,
      foldersStream: controller.stream,
      initialSelectedFolderId: 'a',
    ));
    controller.add([_folder('a', 'Personal')]);
    await tester.pumpAndSettle();

    // Sanity: pre-fill is "Personal".
    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('Personal'),
      ),
      findsOneWidget,
    );

    // Folder vanishes (cascade-delete).
    controller.add(<Folder>[]);
    await tester.pumpAndSettle();

    // Field renders defensive "No folder".
    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
      findsOneWidget,
    );

    // Save -- the SAVED bookmark must use folderId == null, not the dead id.
    await tester.enterText(
        find.byType(TextField).first, 'https://example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedBookmarks, hasLength(1));
    expect(repo.savedBookmarks.single.folderId, isNull);
  });

  testWidgets(
      'self-heal: emission containing a DIFFERENT folder set also resets',
      (tester) async {
    final repo = _FakeRepo();
    final controller = StreamController<List<Folder>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(wrapStream(
      repo: repo,
      foldersStream: controller.stream,
      initialSelectedFolderId: 'a',
    ));
    controller.add([_folder('a', 'Personal')]);
    await tester.pumpAndSettle();

    // Different set: 'a' replaced with 'b'.
    controller.add([_folder('b', 'Work')]);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'self-heal: emission with the same folder still present does NOT '
      'reset _pendingFolderId', (tester) async {
    final repo = _FakeRepo();
    final controller = StreamController<List<Folder>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(wrapStream(
      repo: repo,
      foldersStream: controller.stream,
      initialSelectedFolderId: 'a',
    ));
    controller.add([_folder('a', 'Personal')]);
    await tester.pumpAndSettle();

    // Re-emit same membership (e.g. unrelated folder edit).
    controller.add([_folder('a', 'Personal')]);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('Personal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'self-heal: when _pendingFolderId is null, an emission with no '
      'matching id does not reset / spuriously rebuild', (tester) async {
    final repo = _FakeRepo();
    final controller = StreamController<List<Folder>>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(wrapStream(
      repo: repo,
      foldersStream: controller.stream,
      // initialSelectedFolderId: null (default) -> _pendingFolderId starts null.
    ));
    controller.add([_folder('a', 'Personal')]);
    await tester.pumpAndSettle();

    // Field shows "No folder" and remains so after another emission.
    controller.add(<Folder>[]);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.text('No folder'),
      ),
      findsOneWidget,
    );
  });

  group('Story 2.5: tags field', () {
    Widget wrapWithTagRepo({
      required IBookmarkRepository repo,
      required ITagRepository tagRepo,
      required VoidCallback onClose,
    }) {
      return ProviderScope(
        overrides: [
          bookmarkRepositoryProvider.overrideWithValue(repo),
          metadataFetchServiceProvider
              .overrideWithValue(_NoopMetadataFetchService()),
          watchFoldersProvider
              .overrideWith((ref) => Stream<List<Folder>>.value(const [])),
          tagRepositoryProvider.overrideWithValue(tagRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: _Eager(child: InlineAddForm(onClose: onClose)),
          ),
        ),
      );
    }

    Finder addTagsInput() => find.byWidgetPredicate((w) =>
        w is TextField &&
        w.decoration?.hintText == 'Add tags (comma to separate)');

    testWidgets('opens with no pending tags; field present', (tester) async {
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: _FakeRepo(),
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      expect(addTagsInput(), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('Type "design" Enter -> chip appears in the form',
        (tester) async {
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: _FakeRepo(),
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'design');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('design'), findsOneWidget);
    });

    testWidgets('Type "ux, design" -> two chips appear', (tester) async {
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: _FakeRepo(),
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      // Type the whole thing then commit by pressing Enter so both parts
      // (split on the comma) are committed together.
      await tester.enterText(addTagsInput(), 'ux, design');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('ux'), findsOneWidget);
      expect(find.text('design'), findsOneWidget);
    });

    testWidgets('Type "Flutter" then "flutter" -> dedup; only one chip',
        (tester) async {
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: _FakeRepo(),
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'Flutter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(addTagsInput(), 'flutter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('Tap "x" on a chip removes it from form-local state',
        (tester) async {
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: _FakeRepo(),
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'todo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);

      final chip = tester.widget<InputChip>(find.byType(InputChip));
      chip.onDeleted!.call();
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets(
        'Save with URL + 2 tags -> bookmark saved, then upsertAndLinkAll '
        'called with those tags', (tester) async {
      final repo = _FakeRepo();
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: repo,
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      // Add tags first.
      await tester.enterText(addTagsInput(), 'design, ux');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // URL field is the autofocused TextField at order 1; find by hintText.
      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Paste a URL',
      );
      await tester.enterText(urlField, 'https://example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // Notifier dispatches save async; let it run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(repo.savedBookmarks.length, 1);
      expect(repo.savedBookmarks.single.url, 'https://example.com');
      expect(tagRepo.upsertAndLinkAllCalls.length, 1);
      expect(
        tagRepo.upsertAndLinkAllCalls.single.tagNames,
        ['design', 'ux'],
      );
      expect(
        tagRepo.upsertAndLinkAllCalls.single.bookmarkId,
        repo.savedBookmarks.single.id,
      );
    });

    testWidgets(
        'Save with URL only (no tags) -> NO upsertAndLinkAll dispatch',
        (tester) async {
      final repo = _FakeRepo();
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: repo,
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Paste a URL',
      );
      await tester.enterText(urlField, 'https://example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(repo.savedBookmarks.length, 1);
      expect(tagRepo.upsertAndLinkAllCalls, isEmpty,
          reason: 'empty tagNames short-circuits the dispatch');
    });

    testWidgets('Esc with pending tags closes the form; no repo dispatch',
        (tester) async {
      var closed = false;
      final repo = _FakeRepo();
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: repo,
        tagRepo: tagRepo,
        onClose: () => closed = true,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'todo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);

      // Focus the URL field (a descendant of the form's Shortcuts subtree)
      // before sending Esc so the DismissIntent activator fires.
      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Paste a URL',
      );
      await tester.tap(urlField);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(repo.savedBookmarks, isEmpty);
      expect(tagRepo.upsertAndLinkAllCalls, isEmpty);
    });

    testWidgets(
        'Save when bookmark.save returns Err: tag dispatch does NOT run',
        (tester) async {
      final repo = _FakeRepo()..failNextSave = true;
      final tagRepo = _RecordingTagRepo();
      await tester.pumpWidget(wrapWithTagRepo(
        repo: repo,
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'design');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Paste a URL',
      );
      await tester.enterText(urlField, 'https://example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // bookmarkRepository.save was attempted but failed.
      expect(repo.saveAttempts, 1);
      // tag dispatch is GATED by Ok save; never runs.
      expect(tagRepo.upsertAndLinkAllCalls, isEmpty);
    });

    testWidgets(
        'Save when tag link returns Err: bookmark survives; tag failure '
        'recorded on repo (notifier-level surfacing tested elsewhere)',
        (tester) async {
      final repo = _FakeRepo();
      final tagRepo = _RecordingTagRepo()..failUpsertAndLink = true;
      await tester.pumpWidget(wrapWithTagRepo(
        repo: repo,
        tagRepo: tagRepo,
        onClose: () {},
      ));
      await tester.pumpAndSettle();

      await tester.enterText(addTagsInput(), 'design');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Paste a URL',
      );
      await tester.enterText(urlField, 'https://example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(repo.savedBookmarks.length, 1, reason: 'bookmark survived');
      expect(tagRepo.upsertAndLinkAllCalls.length, 1);
    });
  });
}

class _RecordingTagRepo implements ITagRepository {
  final List<({String bookmarkId, List<String> tagNames})>
      upsertAndLinkAllCalls = <({String bookmarkId, List<String> tagNames})>[];
  bool failUpsertAndLink = false;

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) =>
      const Stream<List<Tag>>.empty();

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
  }) async {
    upsertAndLinkAllCalls
        .add((bookmarkId: bookmarkId, tagNames: tagNames));
    if (failUpsertAndLink) {
      return const Err<List<Tag>, AppError>(StorageError('boom'));
    }
    return const Ok<List<Tag>, AppError>(<Tag>[]);
  }
}
