import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/tags/data/tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-cutting invariant: every user-initiated repository mutation must
/// produce a `sync_queue` row via the SQL triggers installed by Story 4.2
/// (schema v7). FTS-only mutations must NOT produce queue rows. The
/// existing `sync_queue` "stays empty" assertion (Epic 2 T5, Epic 3 AC10)
/// is inverted here for the positive side of the contract: triggers fire
/// when they should, and don't fire when they shouldn't.
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

  Future<int> syncQueueRowCount() async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_queue',
          variables: <Variable<Object>>[],
        )
        .get();
    return rows.single.read<int>('c');
  }

  Future<List<Map<String, Object?>>> syncQueueRows() async {
    final rows = await db.customSelect(
      'SELECT id, operation, entity_type, entity_id, payload '
      'FROM sync_queue ORDER BY id',
      variables: <Variable<Object>>[],
    ).get();
    return rows
        .map((r) => <String, Object?>{
              'operation': r.read<String>('operation'),
              'entity_type': r.read<String>('entity_type'),
              'entity_id': r.read<String>('entity_id'),
              'payload': r.readNullable<String>('payload'),
            })
        .toList();
  }

  Future<void> clearSyncQueue() async {
    await db.customStatement('DELETE FROM sync_queue');
  }

  Bookmark makeBookmark({
    required String id,
    String? folderId,
    String title = 'Title',
  }) {
    final now = DateTime.now();
    return Bookmark(
      id: id,
      url: 'https://example.com/$id',
      title: title,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Folder makeFolder({required String id, String? parentId, String name = 'F'}) {
    final now = DateTime.now();
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Sync triggers write to sync_queue on user mutations (Story 4.2)', () {
    test('fresh DB has no queue rows', () async {
      expect(await syncQueueRowCount(), 0);
    });

    test('folder insert/rename/delete each enqueue one row', () async {
      await folderRepo.save(makeFolder(id: 'f-root'));
      expect((await syncQueueRows()).last, {
        'operation': 'upsert',
        'entity_type': 'folder',
        'entity_id': 'f-root',
        'payload': null,
      });

      await clearSyncQueue();
      await folderRepo.save(makeFolder(id: 'f-root', name: 'Renamed'));
      // FolderRepository.save uses insertOnConflictUpdate (an UPSERT, not a
      // REPLACE), so the second save of an existing PK fires AU exactly
      // once -> one folder-upsert row.
      expect(await syncQueueRows(), [
        {
          'operation': 'upsert',
          'entity_type': 'folder',
          'entity_id': 'f-root',
          'payload': null,
        },
      ]);

      await clearSyncQueue();
      await folderRepo.deleteCascade({'f-root'});
      // deleteCascade also deletes the child f-child via FK semantics in
      // the same transaction; both produce delete rows.
      final rows = await syncQueueRows();
      final deletes = rows.where((r) => r['operation'] == 'delete').toList();
      expect(
        deletes
            .where((r) => r['entity_type'] == 'folder')
            .map((r) => r['entity_id'])
            .toSet()
            .contains('f-root'),
        isTrue,
      );
    });

    test('bookmark insert / update / delete each enqueue rows', () async {
      await bookmarkRepo.save(makeBookmark(id: 'bm-1'));
      expect((await syncQueueRows()).last, {
        'operation': 'upsert',
        'entity_type': 'bookmark',
        'entity_id': 'bm-1',
        'payload': null,
      });

      await clearSyncQueue();
      await bookmarkRepo.save(makeBookmark(id: 'bm-1', title: 'Updated'));
      // BookmarkRepository.save uses insertOnConflictUpdate -> the second
      // save of an existing PK fires AU exactly once.
      expect(await syncQueueRows(), [
        {
          'operation': 'upsert',
          'entity_type': 'bookmark',
          'entity_id': 'bm-1',
          'payload': null,
        },
      ]);

      await clearSyncQueue();
      await bookmarkRepo.delete('bm-1');
      final deleteRows = await syncQueueRows();
      // BookmarkRepository.delete clears bookmark_tags first (which would
      // fire bookmark_tags_sync_ad as bookmark-upsert if there were any
      // junction rows). With no tags here, only bookmarks_sync_ad fires.
      expect(deleteRows, [
        {
          'operation': 'delete',
          'entity_type': 'bookmark',
          'entity_id': 'bm-1',
          'payload': null,
        },
      ]);
    });

    test('tag link / unlink each enqueue a bookmark-upsert row', () async {
      await bookmarkRepo.save(makeBookmark(id: 'bm-tag'));
      final upsertResult = await tagRepo.upsertByName('flutter');
      final tag = (upsertResult as Ok<Tag, dynamic>).value;

      await clearSyncQueue();
      await tagRepo.linkBookmarkTag('bm-tag', tag.id);
      // Two rows are expected, both bookmark-upsert for bm-tag:
      //   1) bookmark_tags_sync_ai   -> from the junction insert.
      //   2) bookmarks_sync_au       -> from the updated_at bump that
      //      linkBookmarkTag now performs so the per-record LWW merge
      //      keeps the local tag link on the next pull (Story 4.5 smoke
      //      regression — see tag_repository.dart `_bumpBookmarkUpdatedAt`).
      // Both reference the same bookmark; the push coalesces them into
      // a single snapshot.
      final linkRows = await syncQueueRows();
      expect(linkRows, hasLength(2));
      for (final row in linkRows) {
        expect(row, {
          'operation': 'upsert',
          'entity_type': 'bookmark',
          'entity_id': 'bm-tag',
          'payload': null,
        });
      }

      await clearSyncQueue();
      await tagRepo.unlinkBookmarkTag('bm-tag', tag.id);
      // unlinkBookmarkTag fires three triggers:
      //   1) bookmark_tags_sync_ad   -> upsert bookmark bm-tag
      //   2) tags_sync_ad            -> delete tag <tag.id>
      //   3) bookmarks_sync_au       -> upsert bookmark bm-tag (the
      //      updated_at bump, same rationale as linkBookmarkTag).
      final unlinkRows = await syncQueueRows();
      expect(unlinkRows, hasLength(3));
      final upsertRows =
          unlinkRows.where((r) => r['operation'] == 'upsert').toList();
      expect(upsertRows, hasLength(2),
          reason: 'one upsert per bookmark_tags AD + one from the bump');
      for (final row in upsertRows) {
        expect(row, {
          'operation': 'upsert',
          'entity_type': 'bookmark',
          'entity_id': 'bm-tag',
          'payload': null,
        });
      }
      final deleteRows =
          unlinkRows.where((r) => r['operation'] == 'delete').toList();
      expect(deleteRows, hasLength(1));
      expect(deleteRows.single, {
        'operation': 'delete',
        'entity_type': 'tag',
        'entity_id': tag.id,
        'payload': null,
      });
    });

    test('tag upsertByName (first time) enqueues a tag-upsert row', () async {
      await clearSyncQueue();
      await tagRepo.upsertByName('NewTag');
      final rows = await syncQueueRows();
      expect(rows, hasLength(1));
      expect(rows.single['operation'], 'upsert');
      expect(rows.single['entity_type'], 'tag');
    });

    test('cascade folder delete enqueues rows for every affected row',
        () async {
      await folderRepo.save(makeFolder(id: 'f-root'));
      await folderRepo.save(makeFolder(id: 'f-child', parentId: 'f-root'));
      await bookmarkRepo.save(makeBookmark(id: 'bm-c1', folderId: 'f-child'));
      await bookmarkRepo.save(makeBookmark(id: 'bm-c2', folderId: 'f-root'));

      await clearSyncQueue();
      await folderRepo.deleteCascade({'f-root', 'f-child'});

      final rows = await syncQueueRows();
      // We get a row per deletion: 2 bookmark deletes + 2 folder deletes,
      // minimum. (The order is the DB's, not ours.)
      final deletes = rows.where((r) => r['operation'] == 'delete').toList();
      expect(deletes.length, greaterThanOrEqualTo(4));
      expect(
        deletes
            .where((r) => r['entity_type'] == 'bookmark')
            .map((r) => r['entity_id'])
            .toSet(),
        {'bm-c1', 'bm-c2'},
      );
      expect(
        deletes
            .where((r) => r['entity_type'] == 'folder')
            .map((r) => r['entity_id'])
            .toSet(),
        {'f-root', 'f-child'},
      );
    });
  });

  group('FTS triggers must NOT write to sync_queue (Epic 3 invariant)', () {
    test('FTS rebuild on populated DB produces zero sync_queue rows',
        () async {
      // Populate via repository (which fires sync triggers) -- clear queue
      // -- then run an FTS-only rebuild and assert nothing else enqueued.
      await bookmarkRepo.save(makeBookmark(id: 'bm-fts'));
      await clearSyncQueue();

      await db.customStatement(
        "INSERT INTO bookmarks_fts(bookmarks_fts) VALUES('rebuild')",
      );

      expect(await syncQueueRowCount(), 0,
          reason: 'FTS rebuild is not a user mutation and must not enqueue');
    });

    test('FTS-internal optimize produces zero sync_queue rows', () async {
      await bookmarkRepo.save(makeBookmark(id: 'bm-opt'));
      await clearSyncQueue();
      await db.customStatement(
        "INSERT INTO bookmarks_fts(bookmarks_fts) VALUES('optimize')",
      );
      expect(await syncQueueRowCount(), 0);
    });
  });
}
