import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/merge_applier.dart';
import 'package:bookmarks/core/drive/models/drive_bookmark.dart';
import 'package:bookmarks/core/drive/models/drive_bookmarks_file.dart';
import 'package:bookmarks/core/drive/models/drive_folder.dart';
import 'package:bookmarks/core/drive/models/drive_tag.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

DriveBookmark _dB(
  String id, {
  int updatedMs = 1000,
  int createdMs = 500,
  List<String> tagIds = const <String>[],
  String? folderId,
}) {
  return DriveBookmark(
    id: id,
    url: 'https://example.com/$id',
    title: 'Title $id',
    folderId: folderId,
    tagIds: tagIds,
    createdAt: _iso(createdMs),
    updatedAt: _iso(updatedMs),
  );
}

DriveFolder _dF(String id, {int updatedMs = 1000, String? parentId}) {
  return DriveFolder(
    id: id,
    name: 'Folder $id',
    parentId: parentId,
    createdAt: _iso(500),
    updatedAt: _iso(updatedMs),
  );
}

DriveTag _dT(String id, {int updatedMs = 1000}) {
  return DriveTag(
    id: id,
    name: 'Tag $id',
    createdAt: _iso(500),
    updatedAt: _iso(updatedMs),
  );
}

DriveBookmarksFile _envelope({
  required int lastModifiedMs,
  List<DriveBookmark> bookmarks = const <DriveBookmark>[],
  List<DriveFolder> folders = const <DriveFolder>[],
  List<DriveTag> tags = const <DriveTag>[],
}) {
  return DriveBookmarksFile(
    version: 1,
    lastModified: _iso(lastModifiedMs),
    bookmarks: bookmarks,
    folders: folders,
    tags: tags,
  );
}

void main() {
  late AppDatabase db;
  late MergeApplier applier;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    applier = MergeApplier(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> countTable(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> countFts() async {
    return countTable('bookmarks_fts');
  }

  Future<List<int>> queueIds() async {
    final rows = await db
        .customSelect('SELECT id FROM sync_queue ORDER BY id ASC')
        .get();
    return rows.map((r) => r.read<int>('id')).toList();
  }

  test('empty remote on empty local — no-op; queue empty', () async {
    final result = await applier.apply(_envelope(lastModifiedMs: 1000));
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('bookmarks'), 0);
    expect(await countTable('folders'), 0);
    expect(await countTable('tags'), 0);
    expect(await countTable('bookmark_tags'), 0);
    expect(await queueIds(), isEmpty);
  });

  test('single remote bookmark on empty local — bookmark row, FTS row, '
      'sync_queue empty', () async {
    final result = await applier.apply(
      _envelope(
        lastModifiedMs: 5000,
        bookmarks: [_dB('b1', updatedMs: 2000)],
      ),
    );
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('bookmarks'), 1);
    expect(await countFts(), 1);
    expect(await queueIds(), isEmpty,
        reason: 'merge-produced sync_queue rows must be cleaned up');
  });

  test('remote with folders, bookmarks, tags, and junctions — all four '
      'tables populated, queue empty', () async {
    final result = await applier.apply(
      _envelope(
        lastModifiedMs: 5000,
        folders: [_dF('f1', updatedMs: 1000)],
        tags: [_dT('t1', updatedMs: 1000), _dT('t2', updatedMs: 1000)],
        bookmarks: [
          _dB('b1', updatedMs: 1000, folderId: 'f1', tagIds: const ['t1', 't2']),
        ],
      ),
    );
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('bookmarks'), 1);
    expect(await countTable('folders'), 1);
    expect(await countTable('tags'), 2);
    expect(await countTable('bookmark_tags'), 2);
    expect(await queueIds(), isEmpty);
  });

  test('remote deletes bookmark that existed locally — junction rows + '
      'bookmark + FTS gone; orphan-tag swept', () async {
    // Seed local: bookmark b1 with tag t1.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com/b1', 'Title', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['t1', 'Tag t1', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      'VALUES (?, ?, ?)',
      ['b1', 't1', 100],
    );
    // Clear pre-existing queue rows from the seeding triggers.
    await db.customStatement('DELETE FROM sync_queue');

    // Remote has lastModified > local updatedAt and no bookmark/tag.
    final result = await applier.apply(_envelope(lastModifiedMs: 5000));
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('bookmarks'), 0);
    expect(await countTable('bookmark_tags'), 0);
    expect(await countTable('tags'), 0,
        reason: 'orphan tag swept after junction removed');
    expect(await countFts(), 0);
    expect(await queueIds(), isEmpty);
  });

  test('folder cascade delete — all descendants gone; queue empty', () async {
    // Seed: folder f1, bookmark b1 in f1 with tag t1.
    await db.customStatement(
      'INSERT INTO folders (id, name, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      ['f1', 'Folder', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, folder_id, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 'f1', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['t1', 'Tag', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      'VALUES (?, ?, ?)',
      ['b1', 't1', 100],
    );
    await db.customStatement('DELETE FROM sync_queue');

    final result = await applier.apply(_envelope(lastModifiedMs: 5000));
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('folders'), 0);
    expect(await countTable('bookmarks'), 0);
    expect(await countTable('bookmark_tags'), 0);
    expect(await countTable('tags'), 0);
    expect(await queueIds(), isEmpty);
  });

  test('pre-existing queue row survives merge; only merge-produced rows '
      'are cleared', () async {
    // Seed a bookmark locally — fires bookmarks_sync_ai, creating a queue
    // row we WANT to preserve (real pending user mutation).
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b-user', 'https://example.com', 'User', 100, 9000],
    );
    final preMergeIds = await queueIds();
    expect(preMergeIds, hasLength(1),
        reason: 'sanity: one queue row from the user-seed');

    // Apply a merge whose remote has a different bookmark; the local
    // user bookmark must survive (local updatedAt > remote lastModified),
    // and the pre-existing queue row must survive too.
    final result = await applier.apply(
      _envelope(
        lastModifiedMs: 5000,
        bookmarks: [_dB('b-remote', updatedMs: 4000)],
      ),
    );
    expect(result, isA<Ok<void, AppError>>());
    expect(await countTable('bookmarks'), 2,
        reason: 'local bookmark survives because its updatedAt > '
            'remote lastModified');
    final postQueue = await queueIds();
    expect(postQueue, preMergeIds,
        reason: 'pre-existing queue rows preserved; merge-produced '
            'cleared');
  });

  test('transaction rollback on simulated exception leaves DB and queue '
      'unchanged', () async {
    // Seed local bookmark.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 100, 100],
    );
    await db.customStatement('DELETE FROM sync_queue');

    // Apply with an envelope that has a malformed ISO date — engine
    // throws when parsing remote.lastModified, applier catches and
    // returns Err(StorageError). The transaction rolls back; nothing
    // persisted.
    final result = await applier.apply(
      const DriveBookmarksFile(
        version: 1,
        lastModified: 'not-a-date',
        bookmarks: <DriveBookmark>[],
      ),
    );
    expect(result, isA<Err<void, AppError>>());
    expect(await countTable('bookmarks'), 1,
        reason: 'local DB unchanged on rollback');
    expect(await queueIds(), isEmpty);
  });

  test('topologically-sorted folder upserts on empty local — '
      'parent persisted before child', () async {
    final result = await applier.apply(
      _envelope(
        lastModifiedMs: 5000,
        folders: [
          // Engine sorts these topologically; applier writes in iteration
          // order. Verify both persist (no FK violation).
          _dF('child', updatedMs: 1000, parentId: 'parent'),
          _dF('parent', updatedMs: 1000),
        ],
      ),
    );
    expect(result, isA<Ok<void, AppError>>());
    final folderRow = await db
        .customSelect(
            "SELECT parent_id FROM folders WHERE id = 'child'")
        .getSingle();
    expect(folderRow.read<String?>('parent_id'), 'parent');
  });

  test('junction replacement: local has [t1,t3], remote has [t1,t2]; '
      'after merge junctions are [t1,t2]', () async {
    // Seed local: bookmark b1 with tags t1, t3.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      ['b1', 'https://example.com', 'T', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['t1', 'Tag1', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
      ['t3', 'Tag3', 100, 100],
    );
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      'VALUES (?, ?, ?)',
      ['b1', 't1', 100],
    );
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      'VALUES (?, ?, ?)',
      ['b1', 't3', 100],
    );
    await db.customStatement('DELETE FROM sync_queue');

    // Remote: same bookmark but newer + tags [t1, t2].
    final result = await applier.apply(
      _envelope(
        lastModifiedMs: 5000,
        tags: [_dT('t1', updatedMs: 2000), _dT('t2', updatedMs: 2000)],
        bookmarks: [
          _dB('b1', updatedMs: 2000, tagIds: const ['t1', 't2']),
        ],
      ),
    );
    expect(result, isA<Ok<void, AppError>>());

    final links = await db
        .customSelect(
            "SELECT tag_id FROM bookmark_tags WHERE bookmark_id = 'b1' "
            'ORDER BY tag_id ASC')
        .get();
    expect(links.map((r) => r.read<String>('tag_id')).toList(), ['t1', 't2']);
    // t3 should have been swept (orphan after the junction replacement).
    final tagIds = await db
        .customSelect('SELECT id FROM tags ORDER BY id ASC')
        .get();
    expect(tagIds.map((r) => r.read<String>('id')).toList(), ['t1', 't2']);
    expect(await queueIds(), isEmpty);
  });
}
