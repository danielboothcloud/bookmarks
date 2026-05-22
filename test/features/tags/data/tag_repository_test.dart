import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/tags/data/tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TagRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> tagCount() async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM tags',
          variables: <Variable<Object>>[],
        )
        .get();
    return rows.single.read<int>('c');
  }

  Future<int> junctionCount() async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM bookmark_tags',
          variables: <Variable<Object>>[],
        )
        .get();
    return rows.single.read<int>('c');
  }

  test('upsertByName inserts a new row; getById returns it', () async {
    final result = await repo.upsertByName('Flutter');
    expect(result, isA<Ok<Tag, AppError>>());
    final tag = (result as Ok<Tag, AppError>).value;
    expect(tag.name, 'Flutter');

    final fetched = await repo.getById(tag.id);
    expect((fetched as Ok<Tag, AppError>).value.id, tag.id);
    expect(await tagCount(), 1);
  });

  test('upsertByName is case-insensitive — second call reuses existing row',
      () async {
    final first = await repo.upsertByName('Flutter');
    final firstTag = (first as Ok<Tag, AppError>).value;

    final second = await repo.upsertByName('flutter');
    final secondTag = (second as Ok<Tag, AppError>).value;

    expect(secondTag.id, firstTag.id);
    expect(secondTag.name, 'Flutter',
        reason: 'createdAt-preserving: returns the original row verbatim');
    expect(await tagCount(), 1);
  });

  test('upsertByName trims whitespace; stored name has no surrounding spaces',
      () async {
    final result = await repo.upsertByName('  Dart  ');
    final tag = (result as Ok<Tag, AppError>).value;
    expect(tag.name, 'Dart');
  });

  test('upsertByName empty/whitespace returns Err(StorageError)', () async {
    final emptyRes = await repo.upsertByName('');
    expect(emptyRes, isA<Err<Tag, AppError>>());
    expect((emptyRes as Err<Tag, AppError>).error, isA<StorageError>());

    final wsRes = await repo.upsertByName('   ');
    expect(wsRes, isA<Err<Tag, AppError>>());
  });

  test('findByName resolves the same row as upsertByName (case-insensitive)',
      () async {
    final upsert = await repo.upsertByName('X');
    final created = (upsert as Ok<Tag, AppError>).value;

    final find = await repo.findByName('x');
    expect(find, isA<Ok<Tag, AppError>>());
    expect((find as Ok<Tag, AppError>).value.id, created.id);
  });

  test('linkBookmarkTag is idempotent — second identical call is a no-op',
      () async {
    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;

    final first = await repo.linkBookmarkTag('b1', tagId);
    expect(first, isA<Ok<void, AppError>>());
    expect(await junctionCount(), 1);

    final second = await repo.linkBookmarkTag('b1', tagId);
    expect(second, isA<Ok<void, AppError>>());
    expect(await junctionCount(), 1,
        reason: 'INSERT OR IGNORE on the composite PK');
  });

  test('unlinkBookmarkTag is idempotent — second call returns Ok', () async {
    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;
    await repo.linkBookmarkTag('b1', tagId);

    final first = await repo.unlinkBookmarkTag('b1', tagId);
    expect(first, isA<Ok<void, AppError>>());
    expect(await junctionCount(), 0);

    final second = await repo.unlinkBookmarkTag('b1', tagId);
    expect(second, isA<Ok<void, AppError>>(),
        reason: 'idempotent: removing-something-already-gone is success');
  });

  test(
      'unlinkBookmarkTag DELETES the Tag row when its last junction is gone '
      '(revised FR16, v5: no count=0 orphan tags)', () async {
    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;
    await repo.linkBookmarkTag('b1', tagId);

    final beforeUnlink = await tagCount();
    expect(beforeUnlink, 1);

    await repo.unlinkBookmarkTag('b1', tagId);

    expect(await tagCount(), 0,
        reason:
            'revised FR16 (v5): tag is hard-deleted when its last junction '
            'is removed -- avoids "0 (orphan)" rows in the sidebar');
  });

  test(
      'linkBookmarkTag bumps the parent bookmark updated_at so the per-record '
      'LWW merge keeps the local junction (Story 4.5 smoke regression)',
      () async {
    // Seed a bookmark with a known, deliberately old updated_at.
    const oldStamp = 1000;
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('b1', 'https://example.com', 'Title', NULL, NULL, NULL, ?, ?)",
      [oldStamp, oldStamp],
    );

    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;

    final result = await repo.linkBookmarkTag('b1', tagId);
    expect(result, isA<Ok<void, AppError>>());

    final row = await db
        .customSelect(
          'SELECT updated_at FROM bookmarks WHERE id = ?',
          variables: [Variable<String>('b1')],
        )
        .getSingle();
    expect(row.read<int>('updated_at'), greaterThan(oldStamp),
        reason: 'linkBookmarkTag must bump the parent bookmark updatedAt so '
            'the next LWW merge keeps the local tag link (Story 4.5 smoke).');
  });

  test(
      'unlinkBookmarkTag bumps the parent bookmark updated_at so the per-record '
      'LWW merge keeps the local removal (same regression as linkBookmarkTag)',
      () async {
    const oldStamp = 1000;
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('b1', 'https://example.com', 'Title', NULL, NULL, NULL, ?, ?)",
      [oldStamp, oldStamp],
    );

    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;
    await repo.linkBookmarkTag('b1', tagId);

    // Reset updated_at to the old stamp so we can observe the unlink bump
    // independently of the link bump above.
    await db.customStatement(
      'UPDATE bookmarks SET updated_at = ? WHERE id = ?',
      [oldStamp, 'b1'],
    );

    final result = await repo.unlinkBookmarkTag('b1', tagId);
    expect(result, isA<Ok<void, AppError>>());

    final row = await db
        .customSelect(
          'SELECT updated_at FROM bookmarks WHERE id = ?',
          variables: [Variable<String>('b1')],
        )
        .getSingle();
    expect(row.read<int>('updated_at'), greaterThan(oldStamp),
        reason: 'unlinkBookmarkTag must bump the parent bookmark updatedAt');
  });

  test(
      'unlinkBookmarkTag preserves the Tag row when OTHER bookmarks still '
      'reference it (only the last-junction case removes the tag)', () async {
    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;
    await repo.linkBookmarkTag('b1', tagId);
    await repo.linkBookmarkTag('b2', tagId);

    await repo.unlinkBookmarkTag('b1', tagId);

    expect(await tagCount(), 1,
        reason:
            'tag still has a junction (b2 -> tag); only the last-junction '
            'case triggers tag removal');
    expect(await junctionCount(), 1);
  });

  test('watchAll emits new tags ordered alphabetically (case-insensitive)',
      () async {
    await repo.upsertByName('Cherry');
    await repo.upsertByName('apple');
    await repo.upsertByName('Banana');

    // Drive a single emission.
    final list = await repo.watchAll().first;
    expect(list.map((t) => t.name).toList(), ['apple', 'Banana', 'Cherry']);
  });

  test('watchForBookmark emits tags in created-order (link order)', () async {
    final xRes = await repo.upsertByName('X');
    final aRes = await repo.upsertByName('A');
    final xId = (xRes as Ok<Tag, AppError>).value.id;
    final aId = (aRes as Ok<Tag, AppError>).value.id;

    // Insert junction rows with explicit created_at values instead of relying
    // on wall-clock timing (which is fragile on fast CI machines where both
    // inserts can land in the same millisecond).
    // X at t=1, A at t=2 → chip order should be [X, A], not alpha [A, X].
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('b1', '$xId', 1)",
    );
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('b1', '$aId', 2)",
    );

    final list = await repo.watchForBookmark('b1').first;
    expect(list.map((t) => t.name).toList(), ['X', 'A']);
  });

  test(
      'upsertAndLinkAll dedupes case-insensitively, preserves first-occurrence '
      'case, creates 2 tags + 2 junctions', () async {
    final result = await repo.upsertAndLinkAll(
      bookmarkId: 'b1',
      tagNames: ['Flutter', 'flutter', 'Dart'],
    );
    expect(result, isA<Ok<List<Tag>, AppError>>());
    final tags = (result as Ok<List<Tag>, AppError>).value;
    expect(tags.map((t) => t.name).toList(), ['Flutter', 'Dart']);
    expect(await tagCount(), 2);
    expect(await junctionCount(), 2);
  });

  test('upsertAndLinkAll with empty input returns Ok([]) and writes nothing',
      () async {
    final result = await repo.upsertAndLinkAll(
      bookmarkId: 'b1',
      tagNames: const <String>[],
    );
    expect((result as Ok<List<Tag>, AppError>).value, isEmpty);
    expect(await tagCount(), 0);
    expect(await junctionCount(), 0);
  });

  test(
      'upsertAndLinkAll with mixed pre-existing + new tags returns 2 tags + '
      '2 junctions, only 1 NEW row created', () async {
    // Pre-insert "Existing".
    final existingRes = await repo.upsertByName('Existing');
    final existingTag = (existingRes as Ok<Tag, AppError>).value;
    expect(await tagCount(), 1);

    final result = await repo.upsertAndLinkAll(
      bookmarkId: 'b1',
      tagNames: ['Existing', 'New'],
    );
    final tags = (result as Ok<List<Tag>, AppError>).value;
    expect(tags.length, 2);
    expect(await tagCount(), 2, reason: 'only 1 NEW tag was created');
    expect(await junctionCount(), 2);
    // Existing tag's id is preserved.
    expect(tags.firstWhere((t) => t.name == 'Existing').id, existingTag.id);
  });

  test(
      'upsertAndLinkAll atomicity: rollback on mid-transaction failure '
      '(BEFORE INSERT trigger on tags simulates failure)', () async {
    // Pre-create one tag so the second insert fires the trigger.
    await repo.upsertByName('First');
    expect(await tagCount(), 1);
    expect(await junctionCount(), 0);

    // Trigger that aborts on inserting any tag whose name is "Boom".
    await db.customStatement(
      'CREATE TRIGGER block_boom_insert BEFORE INSERT ON tags '
      "WHEN NEW.name = 'Boom' "
      "BEGIN SELECT RAISE(ABORT, 'simulated mid-transaction failure'); END;",
    );

    final result = await repo.upsertAndLinkAll(
      bookmarkId: 'b1',
      tagNames: ['Other', 'Boom'],
    );
    expect(result, isA<Err<List<Tag>, AppError>>());
    expect(await tagCount(), 1, reason: 'mid-transaction failure rolls back');
    expect(await junctionCount(), 0,
        reason: 'no junction rows partially-committed');

    await db.customStatement('DROP TRIGGER block_boom_insert');
  });

  test(
      'linkBookmarkTag with non-existent bookmarkId returns Ok '
      '(ghost-id tolerance, no FK enforcement)', () async {
    final upsert = await repo.upsertByName('Flutter');
    final tagId = (upsert as Ok<Tag, AppError>).value.id;

    final result = await repo.linkBookmarkTag('does-not-exist', tagId);
    expect(result, isA<Ok<void, AppError>>());
    expect(await junctionCount(), 1);
  });

  test('findByName trims input', () async {
    await repo.upsertByName('Flutter');
    final result = await repo.findByName('  flutter  ');
    expect(result, isA<Ok<Tag, AppError>>());
    expect((result as Ok<Tag, AppError>).value.name, 'Flutter');
  });

  test('findByName empty returns Err(NotFoundError)', () async {
    final result = await repo.findByName('');
    expect(result, isA<Err<Tag, AppError>>());
    expect((result as Err<Tag, AppError>).error, isA<NotFoundError>());
  });

  test(
      'getById returns Err(NotFoundError) for unknown id; Ok for known',
      () async {
    final missing = await repo.getById('does-not-exist');
    expect(missing, isA<Err<Tag, AppError>>());
    expect((missing as Err<Tag, AppError>).error, isA<NotFoundError>());

    // Insert via raw companion to confirm getById round-trips.
    await db.into(db.tags).insert(
          const TagsCompanion(
            id: Value('t-1'),
            name: Value('manual'),
            createdAt: Value(1),
            updatedAt: Value(2),
          ),
        );
    final found = await repo.getById('t-1');
    expect(found, isA<Ok<Tag, AppError>>());
    expect((found as Ok<Tag, AppError>).value.name, 'manual');
  });

  group('watchAllWithCounts', () {
    test('emits empty list when no tags exist', () async {
      final list = await repo.watchAllWithCounts().first;
      expect(list, isEmpty);
    });

    test('emits tags alphabetically (case-insensitive)', () async {
      await repo.upsertByName('flutter');
      await repo.upsertByName('Bookmarks');
      await repo.upsertByName('apple');

      final list = await repo.watchAllWithCounts().first;
      expect(
        list.map((twc) => twc.tag.name).toList(),
        ['apple', 'Bookmarks', 'flutter'],
      );
    });

    test('count = 0 for tags with no junctions (FR16)', () async {
      await repo.upsertByName('Lonely');

      final list = await repo.watchAllWithCounts().first;
      expect(list.single.tag.name, 'Lonely');
      expect(list.single.count, 0);
    });

    test('count reflects junction multiplicity', () async {
      final upsert = await repo.upsertByName('Flutter');
      final tagId = (upsert as Ok<Tag, AppError>).value.id;
      await repo.linkBookmarkTag('b1', tagId);
      await repo.linkBookmarkTag('b2', tagId);
      await repo.linkBookmarkTag('b3', tagId);

      final list = await repo.watchAllWithCounts().first;
      expect(list.single.count, 3);
    });

    test('re-emits on bookmark_tags insert', () async {
      final upsert = await repo.upsertByName('Flutter');
      final tagId = (upsert as Ok<Tag, AppError>).value.id;

      final emissions = <List<TagWithCount>>[];
      final sub = repo.watchAllWithCounts().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repo.linkBookmarkTag('b1', tagId);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last.single.count, 1);
      await sub.cancel();
    });

    test('re-emits on bookmark_tags delete', () async {
      final upsert = await repo.upsertByName('Flutter');
      final tagId = (upsert as Ok<Tag, AppError>).value.id;
      await repo.linkBookmarkTag('b1', tagId);
      await repo.linkBookmarkTag('b2', tagId);

      final emissions = <List<TagWithCount>>[];
      final sub = repo.watchAllWithCounts().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repo.unlinkBookmarkTag('b1', tagId);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emissions.last.single.count, 1);
      await sub.cancel();
    });

    test('re-emits on tag insert and re-orders alphabetically', () async {
      await repo.upsertByName('zebra');

      final emissions = <List<TagWithCount>>[];
      final sub = repo.watchAllWithCounts().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repo.upsertByName('apple');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        emissions.last.map((twc) => twc.tag.name).toList(),
        ['apple', 'zebra'],
      );
      await sub.cancel();
    });

    test(
        'count query still counts an orphan junction inserted out-of-band '
        '(raw SQL bypasses BookmarkRepository.delete cascade) -- documents '
        'that the count semantics deliberately do NOT join on bookmarks',
        () async {
      // The query joins on tag_id only, not on bookmarks.id. The normal
      // bookmark-delete path (BookmarkRepository.delete) cascade-cleans
      // junctions in a transaction, so users never observe the inflated
      // count. But a future sync-merge path (Story 4.3) may receive a tag
      // unlink without the corresponding bookmark write, briefly leaving an
      // orphan -- this test asserts the count includes that orphan, so the
      // sync-merge code knows it must clean orphans explicitly.
      final upsert = await repo.upsertByName('Ghosted');
      final tagId = (upsert as Ok<Tag, AppError>).value.id;
      // Insert an orphan junction directly (no corresponding bookmark row).
      await repo.linkBookmarkTag('ghost-bookmark-id', tagId);

      final list = await repo.watchAllWithCounts().first;
      expect(list.single.count, 1);
    });
  });
}
