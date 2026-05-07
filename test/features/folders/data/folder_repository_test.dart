import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
// Drift's `Value` symbol clashes with matcher's `isNull` via re-exports;
// import drift with a prefix and use Value() qualified.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FolderRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FolderRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Folder make({
    required String id,
    String name = 'New folder',
    String? parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now =
        createdAt ?? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  test('save persists a new folder and getById returns it', () async {
    final folder = make(id: 'f-1', name: 'Personal');

    final saveResult = await repository.save(folder);
    expect(saveResult, isA<Ok<Folder, AppError>>());

    final getResult = await repository.getById('f-1');
    expect(getResult, isA<Ok<Folder, AppError>>());
    final fetched = (getResult as Ok<Folder, AppError>).value;
    expect(fetched.id, 'f-1');
    expect(fetched.name, 'Personal');
    expect(fetched.parentId, isNull);
  });

  test('save upserts on conflict (same id replaces row)', () async {
    final initial = make(id: 'f-1', name: 'first');
    await repository.save(initial);

    final updated = make(id: 'f-1', name: 'second');
    await repository.save(updated);

    final result = await repository.getById('f-1');
    final folder = (result as Ok<Folder, AppError>).value;
    expect(folder.name, 'second');

    final all = await db.select(db.folders).get();
    expect(all.length, 1);
  });

  test('watchAll emits new entries in createdAt asc order (oldest first)',
      () async {
    final older = make(
      id: 'older',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final newer = make(
      id: 'newer',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final stream = repository.watchAll();
    final emissions = <List<Folder>>[];
    final sub = stream.listen(emissions.add);

    await repository.save(older);
    await repository.save(newer);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final last = emissions.last;
    expect(last.map((f) => f.id).toList(), ['older', 'newer']);

    await sub.cancel();
  });

  test('getById returns Err(NotFoundError) for missing id', () async {
    final result = await repository.getById('does-not-exist');
    expect(result, isA<Err<Folder, AppError>>());
    final err = (result as Err<Folder, AppError>).error;
    expect(err, isA<NotFoundError>());
  });

  test('parentId round-trips correctly through save/getById', () async {
    final folder = make(id: 'child-1', name: 'Child', parentId: 'root-x');

    await repository.save(folder);
    final result = await repository.getById('child-1');

    final fetched = (result as Ok<Folder, AppError>).value;
    expect(fetched.parentId, 'root-x');
  });

  group('deleteCascade', () {
    Future<void> insertBookmark({
      required String id,
      String? folderId,
    }) async {
      // Raw insert via the same db instance keeps the test scoped to
      // FolderRepository.deleteCascade -- avoids cross-feature entanglement
      // through BookmarkRepository.
      await db.into(db.bookmarks).insert(
            BookmarksCompanion.insert(
              id: id,
              url: 'https://example.com/$id',
              title: 'b-$id',
              folderId: Value(folderId),
              createdAt: 0,
              updatedAt: 0,
            ),
          );
    }

    test('empty set returns Ok((0, 0)) and writes nothing', () async {
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');

      final result = await repository.deleteCascade(<String>{});

      expect(result, isA<Ok<({int folders, int bookmarks}), AppError>>());
      final counts =
          (result as Ok<({int folders, int bookmarks}), AppError>).value;
      expect(counts.folders, 0);
      expect(counts.bookmarks, 0);
      // Confirm no writes happened.
      expect((await db.select(db.folders).get()).length, 1);
      expect((await db.select(db.bookmarks).get()).length, 1);
    });

    test('single root folder with no bookmarks deletes 1 folder, 0 bookmarks',
        () async {
      await repository.save(make(id: 'a'));

      final result = await repository.deleteCascade({'a'});

      final counts =
          (result as Ok<({int folders, int bookmarks}), AppError>).value;
      expect(counts.folders, 1);
      expect(counts.bookmarks, 0);
      expect((await db.select(db.folders).get()), isEmpty);
    });

    test('single folder with 3 bookmarks deletes 1 folder + 3 bookmarks',
        () async {
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');
      await insertBookmark(id: 'b-2', folderId: 'a');
      await insertBookmark(id: 'b-3', folderId: 'a');

      final result = await repository.deleteCascade({'a'});

      final counts =
          (result as Ok<({int folders, int bookmarks}), AppError>).value;
      expect(counts.folders, 1);
      expect(counts.bookmarks, 3);
      expect((await db.select(db.folders).get()), isEmpty);
      expect((await db.select(db.bookmarks).get()), isEmpty);
    });

    test('three-deep nesting A>B>C with bookmarks at each level cascades',
        () async {
      await repository.save(make(id: 'a'));
      await repository.save(make(id: 'b', parentId: 'a'));
      await repository.save(make(id: 'c', parentId: 'b'));
      await insertBookmark(id: 'b-a', folderId: 'a');
      await insertBookmark(id: 'b-b', folderId: 'b');
      await insertBookmark(id: 'b-c', folderId: 'c');

      // Caller passes the full descendant set (collected via
      // collectFolderDescendants in the notifier).
      final result = await repository.deleteCascade({'a', 'b', 'c'});

      final counts =
          (result as Ok<({int folders, int bookmarks}), AppError>).value;
      expect(counts.folders, 3);
      expect(counts.bookmarks, 3);
      expect((await db.select(db.folders).get()), isEmpty);
      expect((await db.select(db.bookmarks).get()), isEmpty);
    });

    test(
        'cascade-cleans bookmark_tags junction rows for the deleted '
        'bookmarks (no orphan junctions left behind)', () async {
      // The folder cascade hard-deletes bookmarks. Without explicit junction
      // cleanup those bookmarks' tag links would orphan -- inflating the
      // sidebar tag count. Architectural decision matches
      // BookmarkRepository.delete: maintain referential integrity at the
      // application layer in lieu of FKs.
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');
      await insertBookmark(id: 'b-2', folderId: 'a');
      await insertBookmark(id: 'unrelated');
      Future<void> insertJunction(String bookmarkId, String tagId) =>
          db.into(db.bookmarkTags).insert(
                BookmarkTagsCompanion(
                  bookmarkId: Value(bookmarkId),
                  tagId: Value(tagId),
                  createdAt: const Value(0),
                ),
              );
      await insertJunction('b-1', 't1');
      await insertJunction('b-2', 't1');
      await insertJunction('unrelated', 't2');

      await repository.deleteCascade({'a'});

      final remaining = await db.select(db.bookmarkTags).get();
      expect(remaining.map((r) => r.bookmarkId).toList(), ['unrelated'],
          reason:
              'junctions for cascade-deleted bookmarks must be cleaned; '
              'junctions for unrelated bookmarks survive');
    });

    test(
        'cascade also hard-deletes tag rows whose last junction was just '
        'removed (revised FR16, v5)', () async {
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');
      await insertBookmark(id: 'unrelated');
      // Seed two tags: one only linked to b-1 (will be cleaned), one linked
      // to the unrelated bookmark (must survive).
      Future<void> insertTag(String id, String name) =>
          db.into(db.tags).insert(
                TagsCompanion(
                  id: Value(id),
                  name: Value(name),
                  createdAt: const Value(0),
                  updatedAt: const Value(0),
                ),
              );
      await insertTag('t-doomed', 'doomed');
      await insertTag('t-survivor', 'survivor');
      Future<void> insertJunction(String bookmarkId, String tagId) =>
          db.into(db.bookmarkTags).insert(
                BookmarkTagsCompanion(
                  bookmarkId: Value(bookmarkId),
                  tagId: Value(tagId),
                  createdAt: const Value(0),
                ),
              );
      await insertJunction('b-1', 't-doomed');
      await insertJunction('unrelated', 't-survivor');

      await repository.deleteCascade({'a'});

      final tags = await db.select(db.tags).get();
      expect(tags.map((t) => t.id).toList(), ['t-survivor'],
          reason:
              'cascade hard-deletes tags whose last junction was removed; '
              'tags still linked to surviving bookmarks remain');
    });

    test('bookmarks in folders OUTSIDE the descendant set are preserved',
        () async {
      await repository.save(make(id: 'a'));
      await repository.save(make(id: 'sibling'));
      await insertBookmark(id: 'in-a', folderId: 'a');
      await insertBookmark(id: 'in-sibling', folderId: 'sibling');
      await insertBookmark(id: 'unfiled');

      await repository.deleteCascade({'a'});

      final remaining = await db.select(db.bookmarks).get();
      expect(remaining.map((b) => b.id).toSet(), {'in-sibling', 'unfiled'});
      expect((await db.select(db.folders).get()).length, 1);
    });

    test('folder with parentId in deleted set but own id NOT in set survives',
        () async {
      // Contract test: the repo deletes EXACTLY the ids it's given, no
      // recursive expansion. The notifier is responsible for collecting
      // descendants.
      await repository.save(make(id: 'a'));
      await repository.save(make(id: 'b', parentId: 'a'));

      await repository.deleteCascade({'a'});

      final remaining = await db.select(db.folders).get();
      expect(remaining.map((f) => f.id).toList(), ['b']);
    });

    test('returns Err on storage failure (closed db) -- error surface',
        () async {
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');

      // Close the db -- subsequent statements fail. This proves the Err
      // surface; rollback semantics are exercised by the next test.
      await db.close();

      final result = await repository.deleteCascade({'a'});
      expect(result, isA<Err<({int folders, int bookmarks}), AppError>>());
      final err =
          (result as Err<({int folders, int bookmarks}), AppError>).error;
      expect(err, isA<StorageError>());

      // Re-open a fresh db so tearDown's close() is well-formed.
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    test(
        'atomicity: bookmarks DELETE rolls back when folders DELETE fails '
        'mid-transaction (architectural FR9 guarantee)', () async {
      // Seed a folder + bookmark that would both be deleted on a clean run.
      await repository.save(make(id: 'a'));
      await insertBookmark(id: 'b-1', folderId: 'a');

      // Install a BEFORE DELETE trigger on `folders` that raises ABORT.
      // The bookmarks DELETE (statement 1) succeeds inside the transaction;
      // the folders DELETE (statement 2) fires the trigger, which aborts.
      // Drift rethrows from `transaction()` and rolls back -- the bookmarks
      // delete must vanish too. Without `_db.transaction()` wrapping the
      // pair, the bookmark would be gone here, leaving the database in a
      // half-cascade state the cascade-aware UI cannot detect.
      await db.customStatement(
        'CREATE TRIGGER block_folder_delete BEFORE DELETE ON folders '
        "BEGIN SELECT RAISE(ABORT, 'simulated mid-transaction failure'); END;",
      );

      final result = await repository.deleteCascade({'a'});

      expect(result, isA<Err<({int folders, int bookmarks}), AppError>>());

      final bookmarks = await db.select(db.bookmarks).get();
      expect(
        bookmarks.map((b) => b.id).toList(),
        ['b-1'],
        reason: 'bookmarks DELETE must roll back when folders DELETE fails',
      );
      final folders = await db.select(db.folders).get();
      expect(
        folders.map((f) => f.id).toList(),
        ['a'],
        reason: 'folders are untouched (their DELETE was aborted)',
      );

      // Drop the trigger so a follow-on test could reuse this db.
      await db.customStatement('DROP TRIGGER block_folder_delete');
    });
  });
}
