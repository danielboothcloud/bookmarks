import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BookmarkRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = BookmarkRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Bookmark make({
    required String id,
    String url = 'https://example.com',
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    return Bookmark(
      id: id,
      url: url,
      title: title ?? url,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  test('save persists a new bookmark and getById returns it', () async {
    final bookmark = make(id: 'abc-1');

    final saveResult = await repository.save(bookmark);
    expect(saveResult, isA<Ok<Bookmark, Object>>());

    final getResult = await repository.getById('abc-1');
    expect(getResult, isA<Ok<Bookmark, Object>>());
    final fetched = (getResult as Ok<Bookmark, Object>).value;
    expect(fetched.id, 'abc-1');
    expect(fetched.url, 'https://example.com');
  });

  test('save upserts on conflict (same id replaces row)', () async {
    final initial = make(id: 'abc-1', title: 'first');
    await repository.save(initial);

    final updated = make(id: 'abc-1', title: 'second');
    await repository.save(updated);

    final result = await repository.getById('abc-1');
    final bookmark = (result as Ok<Bookmark, Object>).value;
    expect(bookmark.title, 'second');

    // Still only one row in DB.
    final all = await db.select(db.bookmarks).get();
    expect(all.length, 1);
  });

  test('watchAll emits new entries in createdAt desc order', () async {
    final older = make(
      id: 'older',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final newer = make(
      id: 'newer',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final stream = repository.watchAll();
    final emissions = <List<Bookmark>>[];
    final sub = stream.listen(emissions.add);

    await repository.save(older);
    await repository.save(newer);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final last = emissions.last;
    expect(last.map((b) => b.id).toList(), ['newer', 'older']);

    await sub.cancel();
  });

  test('getById returns Err for missing id', () async {
    final result = await repository.getById('does-not-exist');
    expect(result, isA<Err<Bookmark, Object>>());
  });

  test('delete removes the row and getById returns Err(NotFoundError)',
      () async {
    final bookmark = make(id: 'to-remove');
    await repository.save(bookmark);

    final deleteResult = await repository.delete('to-remove');
    expect(deleteResult, isA<Ok<void, Object>>());

    final getResult = await repository.getById('to-remove');
    expect(getResult, isA<Err<Bookmark, Object>>());
    final all = await db.select(db.bookmarks).get();
    expect(all, isEmpty);
  });

  test(
      'delete cascade-cleans bookmark_tags junction rows '
      '(no orphan junctions left behind)', () async {
    // Architectural decision: bookmark_tags has no FK enforcement, so the
    // repo MUST clean junctions on bookmark delete -- otherwise the sidebar
    // tag count (TagRepository.watchAllWithCounts) inflates with orphans.
    await repository.save(make(id: 'b1'));
    // Two tag links, both reference b1.
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t2'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    expect((await db.select(db.bookmarkTags).get()).length, 2);

    await repository.delete('b1');

    expect((await db.select(db.bookmarkTags).get()), isEmpty,
        reason: 'orphan junctions must be cleaned on bookmark delete');
  });

  test(
      'delete also hard-deletes tag rows whose last junction was just '
      'removed (revised FR16, v5)', () async {
    await repository.save(make(id: 'b1'));
    // Seed a tag row + junction. After the bookmark delete, the junction is
    // cleaned (existing test) AND the now-orphan tag row is also cleaned.
    await db.into(db.tags).insert(
          const TagsCompanion(
            id: Value('t1'),
            name: Value('alone'),
            createdAt: Value(0),
            updatedAt: Value(0),
          ),
        );
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    expect((await db.select(db.tags).get()).length, 1);

    await repository.delete('b1');

    expect((await db.select(db.tags).get()), isEmpty,
        reason: 'tag with no remaining junctions must be hard-deleted');
  });

  test(
      'delete preserves tag rows that are still linked to OTHER bookmarks',
      () async {
    await repository.save(make(id: 'b1'));
    await repository.save(make(id: 'b2'));
    await db.into(db.tags).insert(
          const TagsCompanion(
            id: Value('t1'),
            name: Value('shared'),
            createdAt: Value(0),
            updatedAt: Value(0),
          ),
        );
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b2'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );

    await repository.delete('b1');

    final tags = await db.select(db.tags).get();
    expect(tags.single.id, 't1',
        reason:
            'tag still linked via b2 -- must not be removed when b1 is deleted');
  });

  test(
      'delete leaves OTHER bookmarks junction rows untouched '
      '(scoped cascade)', () async {
    await repository.save(make(id: 'b1'));
    await repository.save(make(id: 'b2'));
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b2'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );

    await repository.delete('b1');

    final remaining = await db.select(db.bookmarkTags).get();
    expect(remaining.length, 1);
    expect(remaining.single.bookmarkId, 'b2');
  });

  test(
      'delete atomicity: junction cleanup rolls back when bookmark DELETE '
      'fails mid-transaction', () async {
    await repository.save(make(id: 'b1'));
    await db.into(db.bookmarkTags).insert(
          BookmarkTagsCompanion(
            bookmarkId: const Value('b1'),
            tagId: const Value('t1'),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );

    // BEFORE DELETE trigger on bookmarks aborts the bookmark delete inside
    // the transaction. The junction DELETE (statement 1) succeeded; without
    // the transaction wrapper it would persist as data loss with the bookmark
    // still present. Assert rollback restores both.
    await db.customStatement(
      'CREATE TRIGGER block_bm_delete BEFORE DELETE ON bookmarks '
      "BEGIN SELECT RAISE(ABORT, 'simulated mid-transaction failure'); END;",
    );

    final result = await repository.delete('b1');
    expect(result, isA<Err<void, Object>>());

    expect((await db.select(db.bookmarks).get()).length, 1,
        reason: 'bookmark survives the rolled-back transaction');
    expect((await db.select(db.bookmarkTags).get()).length, 1,
        reason: 'junction cleanup must roll back too -- no half-cascade');

    await db.customStatement('DROP TRIGGER block_bm_delete');
  });

  test(
      'delete with unknown id returns Err(NotFoundError) and leaves other '
      'rows untouched', () async {
    await repository.save(make(id: 'keep-1'));
    await repository.save(make(id: 'keep-2'));

    final result = await repository.delete('does-not-exist');
    expect(result, isA<Err<void, Object>>());
    final err = (result as Err<void, Object>).error;
    expect(err, isA<NotFoundError>());

    final all = await db.select(db.bookmarks).get();
    expect(all.map((r) => r.id).toSet(), {'keep-1', 'keep-2'});
  });

  test('IDs are preserved as strings (not auto-increment ints)', () async {
    final bookmark = make(id: 'string-uuid-v4-shape');
    await repository.save(bookmark);

    final raw = await db.select(db.bookmarks).getSingle();
    expect(raw.id, 'string-uuid-v4-shape');
    expect(raw.id, isA<String>());
  });

  group('watchByTagId', () {
    Future<void> insertJunction(String bookmarkId, String tagId) {
      return db.into(db.bookmarkTags).insert(
            BookmarkTagsCompanion(
              bookmarkId: Value(bookmarkId),
              tagId: Value(tagId),
              createdAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    }

    test('emits empty list for unknown tag id', () async {
      final list = await repository.watchByTagId('does-not-exist').first;
      expect(list, isEmpty);
    });

    test('emits empty list for tag with no junctions', () async {
      // Tag exists but no junctions linked.
      await db.into(db.tags).insert(
            const TagsCompanion(
              id: Value('t1'),
              name: Value('Lonely'),
              createdAt: Value(0),
              updatedAt: Value(0),
            ),
          );
      final list = await repository.watchByTagId('t1').first;
      expect(list, isEmpty);
    });

    test('emits bookmarks linked to the tag, in createdAt desc order',
        () async {
      await repository.save(make(
        id: 'b1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ));
      await repository.save(make(
        id: 'b2',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ));
      await repository.save(make(
        id: 'b3',
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ));
      await insertJunction('b1', 't1');
      await insertJunction('b2', 't1');
      await insertJunction('b3', 't1');

      final list = await repository.watchByTagId('t1').first;
      expect(list.map((b) => b.id).toList(), ['b3', 'b2', 'b1']);
    });

    test('filters out bookmarks not linked to the tag', () async {
      for (final id in ['b1', 'b2', 'b3', 'b4', 'b5']) {
        await repository.save(make(id: id));
      }
      // Only b2 and b4 linked to t1.
      await insertJunction('b2', 't1');
      await insertJunction('b4', 't1');
      // b1 linked to a different tag.
      await insertJunction('b1', 't2');

      final list = await repository.watchByTagId('t1').first;
      expect(list.map((b) => b.id).toSet(), {'b2', 'b4'});
    });

    test('re-emits when junction added', () async {
      await repository.save(make(id: 'b1'));

      final emissions = <List<Bookmark>>[];
      final sub = repository.watchByTagId('t1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await insertJunction('b1', 't1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last.single.id, 'b1');
      await sub.cancel();
    });

    test('re-emits when junction removed', () async {
      await repository.save(make(id: 'b1'));
      await insertJunction('b1', 't1');

      final emissions = <List<Bookmark>>[];
      final sub = repository.watchByTagId('t1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // customUpdate (not customStatement) so Drift propagates the table
      // change to in-flight stream subscribers via `updates`.
      await db.customUpdate(
        'DELETE FROM bookmark_tags '
        "WHERE bookmark_id = 'b1' AND tag_id = 't1'",
        updates: {db.bookmarkTags},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last, isEmpty);
      await sub.cancel();
    });

    test(
        're-emits when bookmark itself is updated (bookmarks table is in '
        'readsFrom)', () async {
      await repository.save(make(id: 'b1', title: 'first'));
      await insertJunction('b1', 't1');

      final emissions = <List<Bookmark>>[];
      final sub = repository.watchByTagId('t1').listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repository.save(make(id: 'b1', title: 'second'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last.single.title, 'second');
      await sub.cancel();
    });

    test(
        'orphan junction (bookmarkId references a deleted/missing bookmark) '
        'is hidden by INNER JOIN', () async {
      // Junction whose bookmarkId is not present in the bookmarks table.
      // The INNER JOIN must drop this row so the user-visible filter list
      // doesn't bleed orphans (the count query in TagRepository deliberately
      // counts orphans -- see watchAllWithCounts orphan test).
      await insertJunction('ghost-bookmark', 't1');

      final list = await repository.watchByTagId('t1').first;
      expect(list, isEmpty);
    });
  });
}
