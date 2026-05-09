import 'package:bookmarks/core/database/app_database.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// `idx_tags_lower_name` is a *functional* unique index on `lower(name)`. Drift's
/// `@TableIndex` annotation cannot represent functional indexes, so the index
/// is installed via `customStatement` in `onCreate` (and re-installed in the
/// v3→v4 migration). This means the schema snapshot in `db_schemas/` does NOT
/// reflect the index — and the runtime is the only source of truth.
///
/// This test guards two things:
/// 1. The index physically exists in `sqlite_master` after a fresh DB open.
/// 2. The index actually enforces case-insensitive uniqueness (i.e. it's
///    functional, not a plain `ON tags (name)`). A regression to the
///    annotation-generated form would silently allow case-mismatched
///    duplicates.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('idx_tags_lower_name exists in sqlite_master after fresh DB open',
      () async {
    final rows = await db
        .customSelect(
          "SELECT sql FROM sqlite_master "
          "WHERE type = 'index' AND name = 'idx_tags_lower_name'",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(rows, hasLength(1),
        reason: 'idx_tags_lower_name must exist on a fresh v5 database');
    final sql = rows.single.read<String>('sql');
    expect(sql.toLowerCase(), contains('lower(name)'),
        reason: 'index must be functional on lower(name), not plain ON (name)');
    expect(sql.toLowerCase(), contains('unique'),
        reason: 'index must enforce uniqueness');
  });

  test('idx_tags_lower_name enforces case-insensitive uniqueness at runtime',
      () async {
    // Insert two rows whose names differ only in case. The functional unique
    // index on `lower(name)` should reject the second insert. A regression to
    // a plain `ON tags (name)` index would silently accept it.
    await db.customStatement(
      "INSERT INTO tags (id, name, created_at, updated_at) "
      "VALUES ('t1', 'Flutter', 1, 1)",
    );

    expect(
      () => db.customStatement(
        "INSERT INTO tags (id, name, created_at, updated_at) "
        "VALUES ('t2', 'flutter', 1, 1)",
      ),
      throwsA(anything),
      reason: 'second insert with case-mismatched name must violate UNIQUE',
    );
  });
}
