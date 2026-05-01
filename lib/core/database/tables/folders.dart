import 'package:drift/drift.dart';

@DataClassName('FolderRow')
@TableIndex(name: 'idx_folders_parent_id', columns: {#parentId})
@TableIndex(name: 'idx_folders_updated_at', columns: {#updatedAt})
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
