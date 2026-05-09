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

/// Cross-cutting invariant: no application code path is allowed to write to
/// `sync_queue`. The table is reserved for SQL triggers (Story 4.2). This
/// test exercises a representative set of bookmark / folder / tag mutations
/// and asserts the queue stays empty throughout — catching accidental
/// repository-layer writes before sync ships.
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

  Bookmark _bookmark({
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

  Folder _folder({required String id, String? parentId, String name = 'F'}) {
    final now = DateTime.now();
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('sync_queue stays empty across bookmark / folder / tag mutations',
      () async {
    expect(await syncQueueRowCount(), 0,
        reason: 'fresh DB should have no sync_queue rows');

    // Folders: insert, rename, then leave for cascade-delete below.
    await folderRepo.save(_folder(id: 'f-root'));
    await folderRepo.save(_folder(id: 'f-child', parentId: 'f-root'));
    await folderRepo.save(_folder(
      id: 'f-root',
      name: 'Renamed Root',
    )); // upsert / rename
    expect(await syncQueueRowCount(), 0,
        reason: 'folder insert / rename must not enqueue');

    // Bookmarks: insert into root and child, update one (move to child),
    // delete one. The delete path also wipes bookmark_tags in the same
    // transaction — neither should enqueue.
    await bookmarkRepo.save(_bookmark(id: 'bm-1', folderId: 'f-root'));
    await bookmarkRepo.save(_bookmark(id: 'bm-2'));
    await bookmarkRepo
        .save(_bookmark(id: 'bm-1', folderId: 'f-child', title: 'Updated'));
    expect(await syncQueueRowCount(), 0,
        reason: 'bookmark insert / update / move must not enqueue');

    // Tags: upsert (insert), link, unlink (idempotent), upsert again
    // (case-insensitive reuse of the same row).
    final tagResult = await tagRepo.upsertByName('Flutter');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);
    await tagRepo.linkBookmarkTag('bm-2', tag.id);
    await tagRepo.unlinkBookmarkTag('bm-2', tag.id);
    await tagRepo.upsertByName('flutter'); // case-insensitive: same row
    expect(await syncQueueRowCount(), 0,
        reason: 'tag upsert / link / unlink must not enqueue');

    // Bookmark delete (also cascades bookmark_tags cleanup).
    await bookmarkRepo.delete('bm-1');
    expect(await syncQueueRowCount(), 0,
        reason: 'bookmark delete (with tag-junction cleanup) must not enqueue');

    // Folder cascade delete (removes f-root + f-child + any bookmarks under
    // them + any junctions for those bookmarks). Re-seed something to
    // delete first.
    await bookmarkRepo.save(_bookmark(id: 'bm-3', folderId: 'f-child'));
    await tagRepo.linkBookmarkTag('bm-3', tag.id);
    await folderRepo.deleteCascade({'f-root', 'f-child'});
    expect(await syncQueueRowCount(), 0,
        reason: 'folder cascade delete must not enqueue');
  });
}
