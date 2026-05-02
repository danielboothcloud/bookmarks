import 'package:drift/drift.dart';

@DataClassName('TagRow')
@TableIndex(name: 'idx_tags_updated_at', columns: {#updatedAt})
class Tags extends Table {
  TextColumn get id => text()();
  // Name is stored verbatim (case-preserving). Uniqueness is enforced
  // case-insensitively by a functional UNIQUE index `idx_tags_lower_name`
  // built in AppDatabase.onCreate / onUpgrade via `customStatement` --
  // Drift's @TableIndex does not yet emit functional `lower(...)` indexes,
  // so the index is hand-rolled and lives outside the schema dump.
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
