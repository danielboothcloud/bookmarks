/// SQL DDL for the 11 outbox triggers added in Story 4.2.
///
/// These statements are used by `app_database.dart`'s `onCreate` (fresh
/// install at v7+) and `onUpgrade` `from < 7` block (v6 -> v7 migration),
/// and are imported by tests that need to reason about the sync trigger
/// schema directly. Sourced from `drift_files/sync_triggers.drift` (the
/// documented source-of-truth); the .drift file is kept in sync by hand
/// because the `@DriftDatabase` annotation does NOT include it (matches
/// the `bookmarks_fts.drift` precedent).
///
/// Each trigger fires AFTER its source mutation, inside the same SQL
/// transaction, and inserts exactly one row into `sync_queue`. The
/// transactional integration is the load-bearing property: either both
/// the mutation and the queue row commit, or neither does. The queue
/// can never miss a user write, and can never contain a row whose
/// mutation was rolled back.
///
/// `bookmark_tags` triggers fire with `entity_type = 'bookmark'` and
/// `entity_id = bookmark_id` because the user-observable change is "the
/// bookmark's tag list now differs", not "a junction row exists in
/// isolation". This also dedupes implicitly when a single user delete
/// cascades into multiple queue rows for the same bookmark -- the
/// whole-snapshot upload model serializes the bookmark once regardless
/// of how many queue rows reference it.
///
/// **Cross-trigger isolation invariant:** these triggers MUST NOT touch
/// `bookmarks_fts` (Story 3.1 owns that table) and the Story 3.1 FTS
/// triggers MUST NOT touch `sync_queue` (Story 4.2 owns that table).
/// `test/core/database/sync_queue_write_guard_test.dart` enforces both
/// directions.
library;

/// CREATE statements for the 11 outbox triggers, in source-table order.
/// All use `IF NOT EXISTS` for idempotence under migration replay.
///
/// Trigger count: bookmarks (3) + folders (3) + tags (3) + bookmark_tags (2)
/// = 11.
const List<String> kSyncTriggersCreateStatements = [
  // bookmarks: AI / AU / AD
  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_sync_ai AFTER INSERT ON bookmarks BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'bookmark', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_sync_au AFTER UPDATE ON bookmarks BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'bookmark', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_sync_ad AFTER DELETE ON bookmarks BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('delete', 'bookmark', OLD.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  // folders: AI / AU / AD
  '''
CREATE TRIGGER IF NOT EXISTS folders_sync_ai AFTER INSERT ON folders BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'folder', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS folders_sync_au AFTER UPDATE ON folders BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'folder', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS folders_sync_ad AFTER DELETE ON folders BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('delete', 'folder', OLD.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  // tags: AI / AU / AD
  '''
CREATE TRIGGER IF NOT EXISTS tags_sync_ai AFTER INSERT ON tags BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'tag', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS tags_sync_au AFTER UPDATE ON tags BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'tag', NEW.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS tags_sync_ad AFTER DELETE ON tags BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('delete', 'tag', OLD.id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  // bookmark_tags: AI / AD only -- composite PK forbids in-place update.
  '''
CREATE TRIGGER IF NOT EXISTS bookmark_tags_sync_ai AFTER INSERT ON bookmark_tags BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'bookmark', NEW.bookmark_id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',

  '''
CREATE TRIGGER IF NOT EXISTS bookmark_tags_sync_ad AFTER DELETE ON bookmark_tags BEGIN
  INSERT INTO sync_queue (operation, entity_type, entity_id, payload, created_at)
  VALUES ('upsert', 'bookmark', OLD.bookmark_id, NULL,
          CAST(strftime('%s','now') AS INTEGER) * 1000);
END
''',
];
