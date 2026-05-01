import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/bookmarks.dart';
import 'tables/folders.dart';
import 'tables/sync_queue.dart';

part 'app_database.g.dart';

// Tables will be added as their stories are implemented.
// Story 1.2 added: Bookmarks, SyncQueue
// Story 2.1 added: Folders
// Story 2.5 adds: Tags, BookmarkTags

@DriftDatabase(tables: [Bookmarks, Folders, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Each branch guards on `from < targetVersion` so deltas compose for
          // skip-version upgrades (e.g. v1 -> v3 must apply BOTH v1->v2 and
          // v2->v3). Equality checks would silently skip the missing delta.
          if (from < 2) {
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
          if (from < 3) {
            await m.createTable(folders);
            await m.createIndex(
              Index(
                'idx_folders_parent_id',
                'CREATE INDEX IF NOT EXISTS idx_folders_parent_id '
                    'ON folders (parent_id);',
              ),
            );
            await m.createIndex(
              Index(
                'idx_folders_updated_at',
                'CREATE INDEX IF NOT EXISTS idx_folders_updated_at '
                    'ON folders (updated_at);',
              ),
            );
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'bookmarks_db');
}
