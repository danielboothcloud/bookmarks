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

  test('schema v2 -> v3 migration produces the expected v3 schema', () async {
    // Boot the database at v2, then run AppDatabase's onUpgrade against it
    // and assert the resulting schema matches the v3 generated snapshot.
    final connection = await verifier.startAt(2);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 3);
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
