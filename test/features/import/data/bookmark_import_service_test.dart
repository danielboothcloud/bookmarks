import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/import/data/bookmark_import_service.dart';
import 'package:bookmarks/features/import/domain/import_progress.dart';
import 'package:bookmarks/features/import/domain/parsed_bookmarks_tree.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// UUID v4 canonical form: 8-4-4-4-12 hex chars, version nibble = 4,
// variant nibble in {8,9,a,b}.
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class _ExplodingBookmarkRepo implements IBookmarkRepository {
  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Err(StorageError('not used'));
  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err(StorageError('not used'));
  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      const Err(StorageError('disk full'));
  @override
  Stream<List<Bookmark>> watchAll() => const Stream.empty();
  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late FolderRepository folderRepo;
  late BookmarkRepository bookmarkRepo;
  late BookmarkImportService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    folderRepo = FolderRepository(db);
    bookmarkRepo = BookmarkRepository(db);
    service = BookmarkImportService(
      folderRepo: folderRepo,
      bookmarkRepo: bookmarkRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('empty tree → returns zero counts and writes nothing', () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    final result = await service.importTree(tree);
    final ok = switch (result) {
      Ok(:final value) => value,
      Err(:final error) => fail('expected Ok, got $error'),
    };
    expect(ok.bookmarksImported, 0);
    expect(ok.foldersCreated, 0);
    expect(ok.itemsSkipped, 0);
    final bookmarks = await db.select(db.bookmarks).get();
    final folders = await db.select(db.folders).get();
    expect(bookmarks, isEmpty);
    expect(folders, isEmpty);
  });

  test('single root-level bookmark → one bookmark row, zero folders', () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[],
      rootBookmarks: <ParsedBookmark>[
        ParsedBookmark(url: 'https://a.example', title: 'A'),
      ],
      unparseableItems: 0,
    );
    final result = await service.importTree(tree);
    final ok = switch (result) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };
    expect(ok.bookmarksImported, 1);
    expect(ok.foldersCreated, 0);
    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks.length, 1);
    expect(bookmarks.single.url, 'https://a.example');
    expect(bookmarks.single.folderId, isNull,
        reason: 'root-level bookmark has no parent folder');
  });

  test('folder containing a bookmark → child references parent folder id',
      () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[
        ParsedFolderNode(
          name: 'Tools',
          subfolders: <ParsedFolderNode>[],
          bookmarks: <ParsedBookmark>[
            ParsedBookmark(url: 'https://flutter.dev', title: 'Flutter'),
          ],
        ),
      ],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    final result = await service.importTree(tree);
    final ok = switch (result) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };
    expect(ok.foldersCreated, 1);
    expect(ok.bookmarksImported, 1);
    final folders = await db.select(db.folders).get();
    final bookmarks = await db.select(db.bookmarks).get();
    expect(folders.single.name, 'Tools');
    expect(bookmarks.single.folderId, folders.single.id,
        reason: 'bookmark.folderId must resolve to the just-created folder');
  });

  test('nested folder hierarchy is preserved — parent ids resolve down '
      'the chain', () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[
        ParsedFolderNode(
          name: 'Top',
          subfolders: <ParsedFolderNode>[
            ParsedFolderNode(
              name: 'Mid',
              subfolders: <ParsedFolderNode>[
                ParsedFolderNode(
                  name: 'Leaf',
                  subfolders: <ParsedFolderNode>[],
                  bookmarks: <ParsedBookmark>[
                    ParsedBookmark(url: 'https://deep.example', title: 'Deep'),
                  ],
                ),
              ],
              bookmarks: <ParsedBookmark>[],
            ),
          ],
          bookmarks: <ParsedBookmark>[],
        ),
      ],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    await service.importTree(tree);
    final folders = await db.select(db.folders).get();
    expect(folders.length, 3);
    final byName = {for (final f in folders) f.name: f};
    expect(byName['Top']!.parentId, isNull);
    expect(byName['Mid']!.parentId, byName['Top']!.id);
    expect(byName['Leaf']!.parentId, byName['Mid']!.id);
    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks.single.folderId, byName['Leaf']!.id);
  });

  test('progress callback fires per-batch and reports monotonic counts',
      () async {
    // Build a flat tree of 120 bookmarks → 2 mid-import yields (at 50,
    // 100) plus a terminal emit at 120.
    final bookmarks = List.generate(
      120,
      (i) => ParsedBookmark(url: 'https://x.example/$i', title: 'B $i'),
    );
    final tree = ParsedBookmarksTree(
      rootFolders: const <ParsedFolderNode>[],
      rootBookmarks: bookmarks,
      unparseableItems: 0,
    );
    final progress = <ImportProgress>[];
    await service.importTree(tree, onProgress: progress.add);
    expect(progress.length, greaterThanOrEqualTo(2),
        reason: 'at least the two mid-import yield emits');
    // Monotonic
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i].itemsWritten,
          greaterThanOrEqualTo(progress[i - 1].itemsWritten));
    }
    expect(progress.last.itemsWritten, 120);
    expect(progress.last.totalItems, 120);
  });

  test('UUID v4 IDs are assigned to every created entity', () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[
        ParsedFolderNode(
          name: 'F',
          subfolders: <ParsedFolderNode>[],
          bookmarks: <ParsedBookmark>[
            ParsedBookmark(url: 'https://x.example', title: 'X'),
          ],
        ),
      ],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    await service.importTree(tree);
    final folders = await db.select(db.folders).get();
    final bookmarks = await db.select(db.bookmarks).get();
    for (final f in folders) {
      expect(_uuidV4.hasMatch(f.id), isTrue,
          reason: 'folder id ${f.id} is not UUID v4');
    }
    for (final b in bookmarks) {
      expect(_uuidV4.hasMatch(b.id), isTrue,
          reason: 'bookmark id ${b.id} is not UUID v4');
    }
  });

  test('createdAt == updatedAt for every imported entity', () async {
    final fixedNow = DateTime.utc(2026, 5, 20, 12, 0, 0);
    final svc = BookmarkImportService(
      folderRepo: folderRepo,
      bookmarkRepo: bookmarkRepo,
      now: () => fixedNow,
    );
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[
        ParsedFolderNode(
          name: 'F',
          subfolders: <ParsedFolderNode>[],
          bookmarks: <ParsedBookmark>[
            ParsedBookmark(url: 'https://x.example', title: 'X'),
          ],
        ),
      ],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    await svc.importTree(tree);
    final folders = await db.select(db.folders).get();
    final bookmarks = await db.select(db.bookmarks).get();
    for (final f in folders) {
      expect(f.createdAt, f.updatedAt);
      expect(f.createdAt, fixedNow.millisecondsSinceEpoch);
    }
    for (final b in bookmarks) {
      expect(b.createdAt, b.updatedAt);
      expect(b.createdAt, fixedNow.millisecondsSinceEpoch);
    }
  });

  test('storage error propagates as Err(StorageError); partial writes '
      'are NOT rolled back', () async {
    final exploding = _ExplodingBookmarkRepo();
    final svc = BookmarkImportService(
      folderRepo: folderRepo,
      bookmarkRepo: exploding,
    );
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[
        ParsedFolderNode(
          name: 'F',
          subfolders: <ParsedFolderNode>[],
          bookmarks: <ParsedBookmark>[
            ParsedBookmark(url: 'https://x.example', title: 'X'),
          ],
        ),
      ],
      rootBookmarks: <ParsedBookmark>[],
      unparseableItems: 0,
    );
    final result = await svc.importTree(tree);
    expect(result, isA<Err<dynamic, AppError>>());
    final err = (result as Err<dynamic, AppError>).error;
    expect(err, isA<StorageError>());
    // Folder DID land — partial writes survive.
    final folders = await db.select(db.folders).get();
    expect(folders.length, 1,
        reason: 'folder write succeeded before the bookmark write blew up');
  });

  test('empty-URL bookmark increments itemsSkipped without writing',
      () async {
    const tree = ParsedBookmarksTree(
      rootFolders: <ParsedFolderNode>[],
      rootBookmarks: <ParsedBookmark>[
        ParsedBookmark(url: '   ', title: 'Whitespace url'),
        ParsedBookmark(url: 'https://ok.example', title: 'OK'),
      ],
      unparseableItems: 0,
    );
    final result = await service.importTree(tree);
    final ok = switch (result) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };
    expect(ok.bookmarksImported, 1);
    expect(ok.itemsSkipped, 1);
    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks.length, 1);
    expect(bookmarks.single.url, 'https://ok.example');
  });

  test('importing the 500-bookmark fixture into in-memory drift '
      'completes in under 5 seconds (NFR5 smoke)', () async {
    // Synthesise the tree shape the parser produces for the
    // large_bookmarks fixture (5×5 nested folders, 20 bookmarks each).
    final tree = ParsedBookmarksTree(
      rootFolders: [
        ParsedFolderNode(
          name: 'Generated',
          subfolders: List.generate(5, (t) {
            return ParsedFolderNode(
              name: 'Folder $t',
              subfolders: List.generate(5, (s) {
                return ParsedFolderNode(
                  name: 'Folder $t.$s',
                  subfolders: const <ParsedFolderNode>[],
                  bookmarks: List.generate(20, (i) {
                    return ParsedBookmark(
                      url: 'https://example.com/$t/$s/$i',
                      title: 'Bookmark $t.$s.$i',
                    );
                  }),
                );
              }),
              bookmarks: const <ParsedBookmark>[],
            );
          }),
          bookmarks: const <ParsedBookmark>[],
        ),
      ],
      rootBookmarks: const <ParsedBookmark>[],
      unparseableItems: 0,
    );
    final stopwatch = Stopwatch()..start();
    final result = await service.importTree(tree);
    stopwatch.stop();
    final ok = switch (result) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };
    expect(ok.bookmarksImported, 500);
    expect(ok.foldersCreated, 31);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'NFR5 ceiling — 500 imports must complete in <5s');
  });
}
