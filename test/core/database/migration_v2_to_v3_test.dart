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

  test('schema v2 -> v3 migration produces the expected v3 schema', () async {
    // Boot the database at v2, then run AppDatabase's onUpgrade against it
    // and assert the resulting schema matches the v3 generated snapshot.
    final connection = await verifier.startAt(2);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 3);
    await db.close();
  });

  test(
      'schema v1 -> v3 skip-version migration applies BOTH deltas '
      '(bookmarks/sync_queue + folders)', () async {
    // A user who never opened the app on v2 must still receive both the
    // v1->v2 and v2->v3 schema additions when launching on v3. Equality-only
    // `if (from == X)` guards would silently skip the missing delta.
    //
    // No drift_schema_v1.json snapshot exists (v1 was the implicit empty
    // schema before story 1.2), so this test can't go through SchemaVerifier.
    // Simulate v1 by stamping `PRAGMA user_version = 1` on a fresh in-memory
    // database (via NativeDatabase's setup callback) before AppDatabase first
    // touches it -- Drift then reads user_version=1, sees schemaVersion=3, and
    // invokes onUpgrade(m, 1, 3).
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 1'),
      ),
    );
    // Touch the database so the migration runs.
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // Both deltas applied: bookmarks/sync_queue (v1->v2) AND folders (v2->v3).
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name IN ('bookmarks', 'sync_queue', 'folders') "
          'ORDER BY name',
          variables: <Variable<Object>>[],
        )
        .get();
    expect(
      tables.map((r) => r.read<String>('name')).toList(),
      ['bookmarks', 'folders', 'sync_queue'],
    );

    await db.close();
  });

  test('existing bookmarks survive v2 -> v3 migration (no data loss)',
      () async {
    final schema = await verifier.schemaAt(2);

    // Seed a bookmark via raw SQL against the v2 schema -- the generated
    // schema_v2.dart only exposes Table type-info, no Companion classes.
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-1', 'https://example.com', 'Example', NULL, NULL, NULL, "
      '1700000000000, 1700000000000)',
    );

    // Re-open against AppDatabase to trigger v2 -> v3 migration.
    final db = AppDatabase.forTesting(schema.newConnection());
    // Touch the database so the migration runs.
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final survivors = await db.select(db.bookmarks).get();
    expect(survivors.length, 1);
    expect(survivors.single.id, 'bm-1');
    expect(survivors.single.url, 'https://example.com');

    // The new folders table exists and is empty post-migration.
    final folders = await db.select(db.folders).get();
    expect(folders, isEmpty);

    await db.close();
  });
}
