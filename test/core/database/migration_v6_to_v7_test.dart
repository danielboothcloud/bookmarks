import 'package:bookmarks/core/database/app_database.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/migrations/schema.dart';

/// Story 4.2: validates the v6 -> v7 schema migration that installs the 11
/// outbox triggers populating `sync_queue` on user mutations of bookmarks /
/// folders / tags / bookmark_tags. drift_dev's `migrateAndValidate` covers
/// matching the snapshot but triggers do not appear in the snapshot, so
/// these tests assert their existence + correct firing via runtime
/// sqlite_master + sync_queue inspection.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  Future<List<String>> _allSyncTriggerNames(AppDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type='trigger' AND name LIKE '%_sync_%' ORDER BY name",
      variables: <Variable<Object>>[],
    ).get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<List<Map<String, Object?>>> _syncQueueRows(AppDatabase db) async {
    final rows = await db.customSelect(
      'SELECT id, operation, entity_type, entity_id, payload, created_at '
      'FROM sync_queue ORDER BY id',
      variables: <Variable<Object>>[],
    ).get();
    return rows
        .map((r) => <String, Object?>{
              'id': r.read<int>('id'),
              'operation': r.read<String>('operation'),
              'entity_type': r.read<String>('entity_type'),
              'entity_id': r.read<String>('entity_id'),
              'payload': r.readNullable<String>('payload'),
              'created_at': r.read<int>('created_at'),
            })
        .toList();
  }

  test('schema v6 -> v7 migration produces the expected v7 schema (snapshot)',
      () async {
    // Triggers do not appear in the schema snapshot dumper output (same gap
    // documented for FTS triggers in Story 3.1), so this only validates the
    // table-shape consistency. The trigger-specific assertions live below.
    final connection = await verifier.startAt(6);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 7);
    await db.close();
  });

  test('v6 -> v7 with empty database: 11 sync triggers exist', () async {
    final schema = await verifier.schemaAt(6);
    final db = AppDatabase.forTesting(schema.newConnection());
    // Touch the DB once so onUpgrade runs.
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final triggers = await _allSyncTriggerNames(db);
    expect(triggers, [
      'bookmark_tags_sync_ad',
      'bookmark_tags_sync_ai',
      'bookmarks_sync_ad',
      'bookmarks_sync_ai',
      'bookmarks_sync_au',
      'folders_sync_ad',
      'folders_sync_ai',
      'folders_sync_au',
      'tags_sync_ad',
      'tags_sync_ai',
      'tags_sync_au',
    ]);

    expect(await _syncQueueRows(db), isEmpty,
        reason: 'migration must not seed sync_queue');

    await db.close();
  });

  test('v6 -> v7 preserves existing data (no rows disturbed by trigger install)',
      () async {
    final schema = await verifier.schemaAt(6);
    // Seed under v6 -- this does NOT fire the 4.2 triggers because they
    // haven't been installed yet (we're using the raw v6 schema connection).
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-pre', 'https://example.com/pre', 'Pre-migration', "
      'NULL, NULL, NULL, 1, 1)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO folders (id, name, parent_id, created_at, updated_at) '
      "VALUES ('f-pre', 'Pre Folder', NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t-pre', 'pre', 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final bookmarks = await db
        .customSelect(
          'SELECT id FROM bookmarks',
          variables: <Variable<Object>>[],
        )
        .get();
    expect(bookmarks.map((r) => r.read<String>('id')).toList(), ['bm-pre']);

    final folders = await db
        .customSelect(
          'SELECT id FROM folders',
          variables: <Variable<Object>>[],
        )
        .get();
    expect(folders.map((r) => r.read<String>('id')).toList(), ['f-pre']);

    final tags = await db
        .customSelect(
          'SELECT id FROM tags',
          variables: <Variable<Object>>[],
        )
        .get();
    expect(tags.map((r) => r.read<String>('id')).toList(), ['t-pre']);

    // Pre-existing rows must not have produced queue entries.
    expect(await _syncQueueRows(db), isEmpty);

    await db.close();
  });

  test('post-migration bookmark INSERT fires bookmarks_sync_ai', () async {
    final schema = await verifier.schemaAt(6);
    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-new', 'https://example.com/new', 'New', "
      'NULL, NULL, NULL, 10, 10)',
    );

    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(1));
    expect(rows.single['operation'], 'upsert');
    expect(rows.single['entity_type'], 'bookmark');
    expect(rows.single['entity_id'], 'bm-new');
    expect(rows.single['payload'], isNull);

    await db.close();
  });

  test('post-migration bookmark UPDATE fires bookmarks_sync_au', () async {
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-up', 'https://example.com', 'Old', NULL, NULL, NULL, 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      "UPDATE bookmarks SET title = 'New' WHERE id = 'bm-up'",
    );

    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(1));
    expect(rows.single['operation'], 'upsert');
    expect(rows.single['entity_type'], 'bookmark');
    expect(rows.single['entity_id'], 'bm-up');

    await db.close();
  });

  test('post-migration bookmark DELETE with junctions fires bookmark_tags_sync_ad'
      ' + bookmarks_sync_ad', () async {
    // Reproduces BookmarkRepository.delete's transactional shape: junctions
    // first, then the bookmark row.
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-d', 'https://example.com', 'Doomed', NULL, NULL, NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t-d', 'doomed', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('bm-d', 't-d', 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      "DELETE FROM bookmark_tags WHERE bookmark_id = 'bm-d'",
    );
    await db.customStatement("DELETE FROM bookmarks WHERE id = 'bm-d'");

    final rows = await _syncQueueRows(db);
    // 1 row from bookmark_tags_sync_ad (upsert bookmark) +
    // 1 row from bookmarks_sync_ad (delete bookmark) = 2 rows.
    expect(rows, hasLength(2));
    expect(rows[0]['operation'], 'upsert');
    expect(rows[0]['entity_type'], 'bookmark');
    expect(rows[0]['entity_id'], 'bm-d');
    expect(rows[1]['operation'], 'delete');
    expect(rows[1]['entity_type'], 'bookmark');
    expect(rows[1]['entity_id'], 'bm-d');

    await db.close();
  });

  test('post-migration folder INSERT / UPDATE / DELETE fire folders_sync_*',
      () async {
    final schema = await verifier.schemaAt(6);
    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO folders (id, name, parent_id, created_at, updated_at) '
      "VALUES ('f1', 'F1', NULL, 1, 1)",
    );
    await db.customStatement(
      "UPDATE folders SET name = 'F1-renamed' WHERE id = 'f1'",
    );
    await db.customStatement("DELETE FROM folders WHERE id = 'f1'");

    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(3));
    expect(rows[0]['operation'], 'upsert');
    expect(rows[0]['entity_type'], 'folder');
    expect(rows[1]['operation'], 'upsert');
    expect(rows[1]['entity_type'], 'folder');
    expect(rows[2]['operation'], 'delete');
    expect(rows[2]['entity_type'], 'folder');

    await db.close();
  });

  test('post-migration tag INSERT / UPDATE / DELETE fire tags_sync_*',
      () async {
    final schema = await verifier.schemaAt(6);
    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t1', 'name1', 1, 1)",
    );
    await db.customStatement(
      "UPDATE tags SET name = 'name1-renamed' WHERE id = 't1'",
    );
    await db.customStatement("DELETE FROM tags WHERE id = 't1'");

    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(3));
    expect(rows[0]['operation'], 'upsert');
    expect(rows[0]['entity_type'], 'tag');
    expect(rows[1]['operation'], 'upsert');
    expect(rows[1]['entity_type'], 'tag');
    expect(rows[2]['operation'], 'delete');
    expect(rows[2]['entity_type'], 'tag');

    await db.close();
  });

  test('post-migration bookmark_tags INSERT / DELETE both fire as bookmark-upsert',
      () async {
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-l', 'https://example.com', 'Linked', NULL, NULL, NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t-l', 'linked', 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('bm-l', 't-l', 5)",
    );
    await db.customStatement(
      "DELETE FROM bookmark_tags WHERE bookmark_id = 'bm-l' AND tag_id = 't-l'",
    );

    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(2));
    // Both link-insert AND link-delete are observed as a bookmark-upsert
    // because the user-visible change is "the bookmark's tag list differs".
    expect(rows[0]['operation'], 'upsert');
    expect(rows[0]['entity_type'], 'bookmark');
    expect(rows[0]['entity_id'], 'bm-l');
    expect(rows[1]['operation'], 'upsert');
    expect(rows[1]['entity_type'], 'bookmark');
    expect(rows[1]['entity_id'], 'bm-l');

    await db.close();
  });

  test('FTS-only mutation (rebuild) does NOT write to sync_queue', () async {
    // Cross-trigger isolation invariant: FTS triggers + a manual `rebuild`
    // do not collude with the new sync triggers. Use a fresh v7 install
    // via onCreate so both the FTS table and the sync triggers exist
    // (drift_dev's schemaAt(6) snapshot omits virtual tables, so the
    // FTS table would be absent if we built on top of it).
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // Insert via raw SQL so the sync triggers fire normally; then drain
    // the queue so we can assert the subsequent rebuild adds nothing.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-fts', 'https://example.com', 'FTS', NULL, NULL, NULL, 1, 1)",
    );
    await db.customStatement('DELETE FROM sync_queue');
    expect(await _syncQueueRows(db), isEmpty);

    await db.customStatement(
      "INSERT INTO bookmarks_fts(bookmarks_fts) VALUES('rebuild')",
    );

    // Rebuild is an FTS-only operation; it must not touch sync_queue.
    expect(await _syncQueueRows(db), isEmpty);

    await db.close();
  });

  test('fresh v7 install (onCreate): 11 sync triggers exist', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final triggers = await _allSyncTriggerNames(db);
    expect(triggers, hasLength(11));

    // A bookmark insert on a fresh v7 DB fires the trigger end-to-end.
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-fresh', 'https://example.com', 'Fresh', "
      'NULL, NULL, NULL, 1, 1)',
    );
    final rows = await _syncQueueRows(db);
    expect(rows, hasLength(1));
    expect(rows.single['entity_id'], 'bm-fresh');

    await db.close();
  });
}
