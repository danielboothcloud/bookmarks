import 'package:bookmarks/core/database/app_database.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('schema v3 -> v4 migration produces the expected v4 schema', () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 4);
    await db.close();
  });

  test(
      'schema v1 -> v4 skip-version migration applies all three deltas '
      '(bookmarks/sync_queue + folders + tags/bookmark_tags)', () async {
    // v1 was the implicit empty schema (pre-Story 1.2). No
    // drift_schema_v1.json snapshot exists, so simulate it by stamping
    // user_version=1 on a fresh in-memory db; AppDatabase will then run
    // onUpgrade(m, 1, 4).
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 1'),
      ),
    );
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final tables = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='table' "
          "AND name IN ('bookmarks', 'sync_queue', 'folders', 'tags', "
          "'bookmark_tags') ORDER BY name",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(
      tables.map((r) => r.read<String>('name')).toList(),
      ['bookmark_tags', 'bookmarks', 'folders', 'sync_queue', 'tags'],
    );
    await db.close();
  });

  test('schema v2 -> v4 skip-version migration adds folders + tags + junction',
      () async {
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-v2', 'https://e.com', 'X', NULL, NULL, NULL, "
      '1700000000000, 1700000000000)',
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final survivors = await db.select(db.bookmarks).get();
    expect(survivors.single.id, 'bm-v2');
    final tags = await db.select(db.tags).get();
    expect(tags, isEmpty);
    final junctions = await db.select(db.bookmarkTags).get();
    expect(junctions, isEmpty);

    await db.close();
  });

  test(
      'existing bookmarks + folders survive v3 -> v4; tags + bookmark_tags '
      'tables exist and are empty', () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-1', 'https://e.com', 'X', NULL, 'f-1', NULL, "
      '1700000000000, 1700000000000)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO folders (id, name, parent_id, created_at, updated_at) '
      "VALUES ('f-1', 'Personal', NULL, 1700000000000, 1700000000000)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks.single.id, 'bm-1');
    final folders = await db.select(db.folders).get();
    expect(folders.single.id, 'f-1');
    expect(await db.select(db.tags).get(), isEmpty);
    expect(await db.select(db.bookmarkTags).get(), isEmpty);

    await db.close();
  });

  test(
      'idx_tags_lower_name UNIQUE functional index enforces case-insensitive '
      'name dedup at the SQL layer', () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase.forTesting(connection.executor);
    // Trigger v3->v4 migration.
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t1', 'Flutter', 1, 1)",
    );
    expect(
      () => db.customStatement(
        'INSERT INTO tags (id, name, created_at, updated_at) '
        "VALUES ('t2', 'flutter', 2, 2)",
      ),
      throwsA(isA<Exception>()),
      reason: 'lower(name) UNIQUE index rejects "flutter" alongside "Flutter"',
    );
    await db.close();
  });

  test('idx_bookmark_tags_tag_id reverse-direction index exists at v4',
      () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase.forTesting(connection.executor);
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final indexes = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='index' "
          "AND name = 'idx_bookmark_tags_tag_id'",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(indexes.length, 1);

    await db.close();
  });

  test(
      'composite PK on bookmark_tags: insertOrIgnore on duplicate is a no-op',
      () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase.forTesting(connection.executor);
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT OR IGNORE INTO bookmark_tags '
      "(bookmark_id, tag_id, created_at) VALUES ('b1', 't1', 1)",
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO bookmark_tags '
      "(bookmark_id, tag_id, created_at) VALUES ('b1', 't1', 2)",
    );
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM bookmark_tags',
          variables: <Variable<Object>>[],
        )
        .get();
    expect(rows.single.read<int>('c'), 1);
    await db.close();
  });

  test(
      'composite PK on bookmark_tags: plain INSERT on duplicate raises '
      '(PRIMARY KEY constraint)', () async {
    final connection = await verifier.startAt(3);
    final db = AppDatabase.forTesting(connection.executor);
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('b1', 't1', 1)",
    );
    expect(
      () => db.customStatement(
        'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
        "VALUES ('b1', 't1', 2)",
      ),
      throwsA(isA<Exception>()),
    );

    await db.close();
  });
}
