import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'fts_schema.dart';
import 'sync_triggers_schema.dart';
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
// Story 3.1 added: bookmarks_fts (FTS5 virtual table) + 5 sync triggers,
//   defined in `drift_files/bookmarks_fts.drift` (documentation) and
//   executed via customStatement from `fts_schema.dart` constants.
// Story 4.2 added: 11 outbox triggers populating sync_queue on user
//   mutations, defined in `drift_files/sync_triggers.drift` (documentation)
//   and executed via customStatement from `sync_triggers_schema.dart`
//   constants.

@DriftDatabase(tables: [Bookmarks, Folders, SyncQueue, Tags, BookmarkTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

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
          // Story 3.1: FTS5 virtual table + 5 sync triggers. Order matters:
          // `m.createAll()` must have created `bookmarks`, `bookmark_tags`,
          // and `tags` first because the triggers reference them. The
          // 'rebuild' step is skipped on a fresh install -- there are no
          // rows to backfill, and the triggers are no-op on an empty table.
          for (final stmt in kFtsCreateStatements) {
            await customStatement(stmt);
          }
          // Story 4.2: 11 outbox triggers populating sync_queue on user
          // mutations. Order: `m.createAll()` above created bookmarks /
          // folders / tags / bookmark_tags / sync_queue, all of which the
          // sync triggers reference. The sync triggers do not depend on
          // the FTS table, so the FTS / sync install order is arbitrary,
          // but stable order makes test assertions easier.
          for (final stmt in kSyncTriggersCreateStatements) {
            await customStatement(stmt);
          }
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
          if (from < 5) {
            // v5 is a DATA-only migration -- no schema change. It cleans up
            // two classes of stale rows that pre-v5 application paths could
            // leave behind:
            //
            //  1. Orphan junction rows in `bookmark_tags` where the referenced
            //     `bookmark_id` no longer exists (pre-fix `BookmarkRepository
            //     .delete` did NOT cascade-clean junctions; pre-fix
            //     `FolderRepository.deleteCascade` had the same gap). These
            //     orphans inflated the sidebar tag count without contributing
            //     to the user-visible bookmark list.
            //
            //  2. Orphan tag rows whose last junction was cleaned in step 1
            //     (or removed by pre-v5 `unlinkBookmarkTag`, which preserved
            //     the tag per the original FR16 reading). FR16 is updated in
            //     v5: a tag is hard-deleted when its last junction is gone.
            //
            // Both queries are idempotent and cheap (PK / indexed lookups).
            await customStatement(
              'DELETE FROM bookmark_tags '
              'WHERE bookmark_id NOT IN (SELECT id FROM bookmarks)',
            );
            await customStatement(
              'DELETE FROM tags '
              'WHERE id NOT IN (SELECT DISTINCT tag_id FROM bookmark_tags)',
            );
          }
          if (from < 6) {
            // Story 3.1: FTS5 virtual table + 5 sync triggers + backfill.
            // Runs AFTER the v5 cleanup so the backfill indexes a clean
            // junction/tag set (no orphan rows).
            //
            // Order:
            //   1. Create the FTS table and its triggers. The triggers
            //      reference bookmarks / bookmark_tags / tags, all created
            //      by earlier `from < N` blocks (or m.createAll on a fresh
            //      v6 install -- onCreate covers that path separately).
            //   2. Backfill: INSERT...SELECT walks every row of `bookmarks`
            //      and writes the FTS tuple in one statement. The
            //      derived `tags` column is computed in the SELECT subquery,
            //      so a single round-trip populates everything.
            //
            // Idempotence: the CREATE statements use `IF NOT EXISTS`. The
            // backfill is gated by the `from < 6` block so it runs once;
            // the migration test suite asserts re-execution is a no-op.
            for (final stmt in kFtsCreateStatements) {
              await customStatement(stmt);
            }
            await customStatement(kFtsBackfillStatement);
          }
          if (from < 7) {
            // Story 4.2: install 11 outbox triggers populating sync_queue
            // on user mutations of bookmarks / folders / tags /
            // bookmark_tags. No data backfill -- sync_queue is allowed to
            // start empty on the migrating device; whatever they have
            // locally either pushes on the next user mutation or stays
            // local until they touch something.
            //
            // Idempotence: each CREATE TRIGGER uses `IF NOT EXISTS` so
            // re-running this block (e.g. a recovered-from-corruption
            // device replaying the migration) is safe.
            for (final stmt in kSyncTriggersCreateStatements) {
              await customStatement(stmt);
            }
          }
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'bookmarks_db');
}
