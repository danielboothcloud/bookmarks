import 'package:bookmarks/core/database/app_database.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story 3.1 Task 8: smoke-verify that the SQLite library shipped with
/// `sqlite3_flutter_libs ^0.6.0` includes FTS5. Functional FTS tests would
/// already fail without it, but this test gives a precise diagnostic if
/// the package or platform ever drops the option.
void main() {
  test('sqlite3_flutter_libs ships SQLite with ENABLE_FTS5', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final row = await db
        .customSelect(
          "SELECT sqlite_compileoption_used('ENABLE_FTS5') AS used",
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(row.read<int>('used'), 1,
        reason: 'sqlite3_flutter_libs must ship SQLite with FTS5 enabled');
  });
}
