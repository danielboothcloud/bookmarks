import 'package:bookmarks/core/database/app_database.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('schema v4 -> v5 migration produces the expected v5 schema', () async {
    final connection = await verifier.startAt(4);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 5);
    await db.close();
  });

  test(
      'v4 -> v5 cleanup deletes orphan junction rows '
      '(bookmark_id with no matching bookmark)', () async {
    final schema = await verifier.schemaAt(4);
    // Seed: one bookmark, one tag, one valid junction, one ORPHAN junction.
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('alive-bm', 'https://e.com', 'X', NULL, NULL, NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t1', 'flutter', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('alive-bm', 't1', 1)",
    );
    // Orphan junction: bookmark_id references a non-existent bookmark.
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('ghost-bm', 't1', 1)",
    );

    // Trigger the v4 -> v5 migration.
    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final junctions = await db.select(db.bookmarkTags).get();
    expect(junctions.length, 1,
        reason: 'orphan junction must be cleaned by the v5 migration');
    expect(junctions.single.bookmarkId, 'alive-bm');

    // The tag still has a valid junction, so it survives.
    final tags = await db.select(db.tags).get();
    expect(tags.single.id, 't1');

    await db.close();
  });

  test(
      'v4 -> v5 cleanup deletes orphan tag rows '
      '(no remaining junction references) -- revised FR16', () async {
    final schema = await verifier.schemaAt(4);
    // Seed: one tag with NO junctions (pre-v5 unlinkBookmarkTag preserved
    // the tag per the original FR16 reading; v5 cleans these on upgrade).
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('lonely', 'lonely', 1, 1)",
    );
    // A second tag WITH a junction to a real bookmark -- must survive.
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-1', 'https://e.com', 'X', NULL, NULL, NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('linked', 'linked', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('bm-1', 'linked', 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.id).toList(), ['linked'],
        reason: 'orphan "lonely" tag must be cleaned; "linked" survives');

    await db.close();
  });

  test(
      'v4 -> v5 cleanup is correctly ordered: orphan junctions are removed '
      'BEFORE the orphan-tag sweep, so a tag whose only junction was an '
      'orphan junction is also removed', () async {
    final schema = await verifier.schemaAt(4);
    // Seed: a tag whose ONLY junction references a non-existent bookmark.
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('orphan-only', 'orphaned', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('ghost-bm', 'orphan-only', 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    expect(await db.select(db.bookmarkTags).get(), isEmpty);
    expect(await db.select(db.tags).get(), isEmpty,
        reason:
            'orphan junction cleanup must run BEFORE the orphan-tag sweep, '
            'so the tag becomes orphan and is then itself swept');

    await db.close();
  });
}
