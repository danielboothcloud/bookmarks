import 'package:drift/drift.dart';

@DataClassName('BookmarkTagRow')
@TableIndex(name: 'idx_bookmark_tags_tag_id', columns: {#tagId})
class BookmarkTags extends Table {
  TextColumn get bookmarkId => text()();
  TextColumn get tagId => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookmarkId, tagId};
}
