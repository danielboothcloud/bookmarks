import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// Tables will be added as their stories are implemented.
// Story 1.2 adds: Bookmarks, SyncQueue
// Story 2.1 adds: Folders
// Story 2.5 adds: Tags, BookmarkTags

@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'bookmarks_db');
}
