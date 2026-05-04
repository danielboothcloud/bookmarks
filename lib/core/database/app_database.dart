import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/bookmark_tags.dart';
import 'tables/bookmarks.dart';
import 'tables/folders.dart';
import 'tables/sync_queue.dart';
import 'tables/tags.dart';

part 'app_database.g.dart';

// Tables will be added as their stories are implemented.
// Story 1.2 added: Bookmarks, SyncQueue
// Story 2.1 added: Folders
// Story 2.5 added: Tags, BookmarkTags

@DriftDatabase(tables: [Bookmarks, Folders, SyncQueue, Tags, BookmarkTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Drift's @TableIndex generator (as of drift ^2.32) does not emit
          // functional `lower(...)` UNIQUE indexes, so the Tags table has no
          // @TableIndex for this name and m.createAll() does not create it.
          // Install the functional UNIQUE index manually so a fresh v4 create
          // enforces case-insensitive name dedup at the SQL layer (matching
          // the v3->v4 upgrade path in onUpgrade).
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_lower_name '
            'ON tags (lower(name))',
          );
        },
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
          if (from < 4) {
            await m.createTable(tags);
            await m.createTable(bookmarkTags);
            // Functional UNIQUE index for case-insensitive name dedup. Drift's
            // @TableIndex generator does not yet emit `lower(...)` expressions
            // (as of drift ^2.32), so we hand-roll the SQL. The index name
            // matches the @TableIndex annotation on Tags so any future
            // schema-dump diff stays clean.
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_lower_name '
              'ON tags (lower(name))',
            );
            await m.createIndex(
              Index(
                'idx_tags_updated_at',
                'CREATE INDEX IF NOT EXISTS idx_tags_updated_at '
                    'ON tags (updated_at);',
              ),
            );
            // bookmark_tags.tagId reverse index. PK already covers the forward
            // direction (bookmarkId, tagId).
            await m.createIndex(
              Index(
                'idx_bookmark_tags_tag_id',
                'CREATE INDEX IF NOT EXISTS idx_bookmark_tags_tag_id '
                    'ON bookmark_tags (tag_id);',
              ),
            );
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'bookmarks_db');
}
