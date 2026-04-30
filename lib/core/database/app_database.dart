import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/bookmarks.dart';
import 'tables/sync_queue.dart';

part 'app_database.g.dart';

// Tables will be added as their stories are implemented.
// Story 1.2 adds: Bookmarks, SyncQueue
// Story 2.1 adds: Folders
// Story 2.5 adds: Tags, BookmarkTags

@DriftDatabase(tables: [Bookmarks, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from == 1) {
            await m.createTable(bookmarks);
            await m.createTable(syncQueue);
            await m.createIndex(
              Index(
                'idx_bookmarks_folder_id',
                'CREATE INDEX IF NOT EXISTS idx_bookmarks_folder_id '
                    'ON bookmarks (folder_id);',
              ),
            );
            await m.createIndex(
              Index(
                'idx_bookmarks_updated_at',
                'CREATE INDEX IF NOT EXISTS idx_bookmarks_updated_at '
                    'ON bookmarks (updated_at);',
              ),
            );
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'bookmarks_db');
}
