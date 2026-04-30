import 'package:drift/drift.dart';

@DataClassName('BookmarkRow')
@TableIndex(name: 'idx_bookmarks_folder_id', columns: {#folderId})
@TableIndex(name: 'idx_bookmarks_updated_at', columns: {#updatedAt})
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get folderId => text().nullable()();
  TextColumn get faviconBase64 => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
