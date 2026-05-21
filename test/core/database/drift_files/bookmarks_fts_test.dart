import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/tags/data/tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story 3.1: end-to-end correctness tests for the 5 FTS sync triggers
/// defined in `drift_files/bookmarks_fts.drift` and migrated in via
/// `app_database.dart`'s onUpgrade `from < 6` block. Operates on a fresh
/// in-memory v6 database so every test starts from a clean state.
void main() {
  late AppDatabase db;
  late BookmarkRepository bookmarkRepo;
  late FolderRepository folderRepo;
  late TagRepository tagRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookmarkRepo = BookmarkRepository(db);
    folderRepo = FolderRepository(db);
    tagRepo = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Bookmark mkBookmark({
    required String id,
    String url = 'https://example.com',
    String title = 'Title',
    String? notes,
    String? folderId,
  }) {
    final now = DateTime.now();
    return Bookmark(
      id: id,
      url: url,
      title: title,
      notes: notes,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Folder mkFolder({required String id, String name = 'F'}) {
    final now = DateTime.now();
    return Folder(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int> ftsRowsForBookmark(String bookmarkId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM bookmarks_fts WHERE rowid = '
          '(SELECT rowid FROM bookmarks WHERE id = ?)',
          variables: [Variable<String>(bookmarkId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<String?> ftsTagsForBookmark(String bookmarkId) async {
    final row = await db
        .customSelect(
          'SELECT tags FROM bookmarks_fts WHERE rowid = '
          '(SELECT rowid FROM bookmarks WHERE id = ?)',
          variables: [Variable<String>(bookmarkId)],
        )
        .getSingleOrNull();
    return row?.read<String>('tags');
  }

  Future<List<String>> matchBookmarkIds(String matchQuery) async {
    final rows = await db
        .customSelect(
          'SELECT b.id AS id FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ? '
          'ORDER BY b.created_at DESC',
          variables: [Variable<String>(matchQuery)],
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  test('runtime existence: bookmarks_fts table + 5 triggers in sqlite_master',
      () async {
    final tables = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='table' AND name='bookmarks_fts'",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(tables, hasLength(1));

    final triggerNames = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='trigger' AND name IN "
          "('bookmarks_ai','bookmarks_ad','bookmarks_au',"
          "'bookmark_tags_ai','bookmark_tags_ad') ORDER BY name",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(
      triggerNames.map((r) => r.read<String>('name')).toList(),
      [
        'bookmark_tags_ad',
        'bookmark_tags_ai',
        'bookmarks_ad',
        'bookmarks_ai',
        'bookmarks_au',
      ],
    );
  });

  test('bookmarks_ai fires on insert: FTS row created with title/url/notes',
      () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      url: 'https://flutter.dev',
      title: 'Flutter',
      notes: 'Cross-platform UI toolkit',
    ));

    expect(await ftsRowsForBookmark('bm-1'), 1);
    expect(await matchBookmarkIds('flutter'), ['bm-1']);
    expect(await matchBookmarkIds('platform'), ['bm-1']);
    expect(await matchBookmarkIds('toolkit'), ['bm-1']);
    // Tags column starts empty.
    expect(await ftsTagsForBookmark('bm-1'), '');
  });

  test('bookmarks_au fires on title update: FTS reflects new title; '
      'old-title MATCH no longer hits', () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'Original',
      url: 'https://e.com',
    ));
    expect(await matchBookmarkIds('original'), ['bm-1']);

    await bookmarkRepo
        .save(mkBookmark(id: 'bm-1', title: 'Updated', url: 'https://e.com'));

    expect(await matchBookmarkIds('updated'), ['bm-1']);
    expect(await matchBookmarkIds('original'), isEmpty);
  });

  test('bookmarks_au only fires on indexed-column changes: junction-driven '
      'tags column survives a bookmark update', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Hello'));
    final tagResult = await tagRepo.upsertByName('graphql');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);
    expect(await ftsTagsForBookmark('bm-1'), 'graphql');

    // Update the bookmark's title -- bookmarks_au should re-write
    // (title, url, notes) but NOT the tags column.
    await bookmarkRepo
        .save(mkBookmark(id: 'bm-1', title: 'New title'));

    expect(await ftsTagsForBookmark('bm-1'), 'graphql',
        reason: 'tags column is owned by bookmark_tags triggers; '
            'a bookmark UPDATE must not clobber it');
    expect(await matchBookmarkIds('graphql'), ['bm-1']);
  });

  test('bookmarks_ad fires on delete: FTS row gone after BookmarkRepository '
      'delete', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Doomed'));
    expect(await ftsRowsForBookmark('bm-1'), 1);

    await bookmarkRepo.delete('bm-1');
    expect(await ftsRowsForBookmark('bm-1'), 0);
    expect(await matchBookmarkIds('doomed'), isEmpty);
  });

  test('bookmark_tags_ai fires on junction insert: FTS tags column updated',
      () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1'));
    final tagResult = await tagRepo.upsertByName('flutter');
    final tag = (tagResult as dynamic).value as Tag;
    expect(await ftsTagsForBookmark('bm-1'), '');

    await tagRepo.linkBookmarkTag('bm-1', tag.id);

    expect(await ftsTagsForBookmark('bm-1'), 'flutter');
    expect(await matchBookmarkIds('flutter'), ['bm-1']);
  });

  test('bookmark_tags_ad fires on junction delete: FTS tags column updated',
      () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1'));
    final tagResult = await tagRepo.upsertByName('flutter');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);
    expect(await ftsTagsForBookmark('bm-1'), 'flutter');

    await tagRepo.unlinkBookmarkTag('bm-1', tag.id);

    // unlinkBookmarkTag also hard-deletes the now-orphan tag (FR16 v5),
    // but the bookmark's FTS row should have empty tags either way.
    expect(await ftsTagsForBookmark('bm-1'), '');
    expect(await matchBookmarkIds('flutter'), isEmpty);
  });

  test(
      'cascading delete from BookmarkRepository.delete cleans the FTS row '
      '(post-4.2: the user mutation enqueues sync_queue rows; the FTS '
      'triggers do not -- isolation tested in sync_queue_write_guard_test)',
      () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Doomed'));
    final tagResult = await tagRepo.upsertByName('flutter');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);
    expect(await ftsRowsForBookmark('bm-1'), 1);

    await bookmarkRepo.delete('bm-1');

    expect(await ftsRowsForBookmark('bm-1'), 0);
    final junctions = await db.select(db.bookmarkTags).get();
    expect(junctions, isEmpty);
  });

  test('cascading delete from FolderRepository.deleteCascade cleans FTS rows '
      'for every removed bookmark', () async {
    await folderRepo.save(mkFolder(id: 'f-root'));
    await bookmarkRepo
        .save(mkBookmark(id: 'bm-a', folderId: 'f-root', title: 'A'));
    await bookmarkRepo
        .save(mkBookmark(id: 'bm-b', folderId: 'f-root', title: 'B'));
    final tagResult = await tagRepo.upsertByName('flutter');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-a', tag.id);

    expect(await ftsRowsForBookmark('bm-a'), 1);
    expect(await ftsRowsForBookmark('bm-b'), 1);

    await folderRepo.deleteCascade({'f-root'});

    expect(await ftsRowsForBookmark('bm-a'), 0);
    expect(await ftsRowsForBookmark('bm-b'), 0);
    final junctions = await db.select(db.bookmarkTags).get();
    expect(junctions, isEmpty);
    // Post-4.2: user-initiated cascade delete WILL enqueue sync_queue
    // rows via the sync triggers (asserted in
    // sync_queue_write_guard_test.dart). The FTS triggers themselves
    // still must not write to sync_queue -- that cross-trigger
    // isolation invariant is asserted by both `sync_queue_write_guard_test`
    // and `migration_v6_to_v7_test` (FTS rebuild produces zero rows).
  });

  test('MATCH with prefix returns expected bookmarks', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Flutter widgets'));
    await bookmarkRepo.save(mkBookmark(id: 'bm-2', title: 'Flask routing'));
    await bookmarkRepo.save(mkBookmark(id: 'bm-3', title: 'Python lists'));

    final hits = await matchBookmarkIds('fl*');
    expect(hits, containsAll(['bm-1', 'bm-2']));
    expect(hits, isNot(contains('bm-3')));
  });
}
