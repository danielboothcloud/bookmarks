/// SQL DDL for the FTS5 virtual table and 5 sync triggers added in Story 3.1.
///
/// The same statements are used by `app_database.dart`'s `onCreate` (fresh
/// install) and `onUpgrade` `from < 6` block (v5 -> v6 migration), and are
/// imported by tests that need to reason about the FTS schema directly.
/// Sourced from `drift_files/bookmarks_fts.drift` (the documented
/// source-of-truth); the .drift file is kept in sync by hand because the
/// `@DriftDatabase` annotation does NOT include it (matches the
/// `idx_tags_lower_name` precedent).
///
/// **Why regular (not external-content / contentless) FTS5:**
/// The story's plan favoured external-content (`content='bookmarks'`) for the
/// FTS5 `'rebuild'` backfill convenience. In practice external-content is
/// incompatible with our schema -- it requires the source table to have ALL
/// columns named in the FTS5 schema, but `bookmarks` has no `tags` column
/// (tags are computed via JOIN through `bookmark_tags`). Contentless
/// (`content=''`) forbids UPDATE statements on the FTS table, which would
/// force a delete+insert dance inside every trigger. Regular FTS5 stores
/// the column values inside its own shadow tables; cost is ~1KB per
/// indexed bookmark (same magnitude as external-content), in exchange for
/// straightforward UPDATE-driven triggers and a one-line backfill via
/// INSERT INTO ... SELECT. The trade-off is documented in story 3.1
/// Completion Notes.
library;

/// CREATE statements for the FTS table + 5 triggers, in dependency order.
/// All use `IF NOT EXISTS` for idempotence under migration replay.
const List<String> kFtsCreateStatements = [
  // The virtual table itself. Regular (non-external) FTS5 with the
  // unicode61 tokenizer and diacritic-stripping ON so "café" matches "cafe".
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS bookmarks_fts USING fts5(
  title, url, notes, tags,
  tokenize='unicode61 remove_diacritics 1'
)
''',

  // Insert: title/url/notes from the new row; tags starts empty because
  // junction rows are written after the bookmark.
  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_ai AFTER INSERT ON bookmarks BEGIN
  INSERT INTO bookmarks_fts(rowid, title, url, notes, tags)
  VALUES (new.rowid, new.title, new.url, COALESCE(new.notes, ''), '');
END
''',

  // Delete: drop the matching FTS row. Regular FTS5 handles index cleanup
  // automatically when rows are deleted.
  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_ad AFTER DELETE ON bookmarks BEGIN
  DELETE FROM bookmarks_fts WHERE rowid = old.rowid;
END
''',

  // Update: only fires on changes to the indexed user-mutable columns to
  // avoid spurious rewrites on metadata-only updates (e.g. updatedAt-only
  // writes from sync). The `tags` column is left alone -- it is owned by
  // the bookmark_tags triggers below.
  '''
CREATE TRIGGER IF NOT EXISTS bookmarks_au AFTER UPDATE OF title, url, notes
ON bookmarks BEGIN
  UPDATE bookmarks_fts
  SET title = new.title,
      url = new.url,
      notes = COALESCE(new.notes, '')
  WHERE rowid = new.rowid;
END
''',

  // bookmark_tags insert: refresh the affected bookmark's tags column with
  // the current concatenated tag-name set.
  '''
CREATE TRIGGER IF NOT EXISTS bookmark_tags_ai AFTER INSERT ON bookmark_tags
BEGIN
  UPDATE bookmarks_fts
  SET tags = COALESCE(
    (SELECT GROUP_CONCAT(t.name, ' ')
     FROM bookmark_tags bt JOIN tags t ON t.id = bt.tag_id
     WHERE bt.bookmark_id = new.bookmark_id),
    '')
  WHERE rowid = (SELECT rowid FROM bookmarks WHERE id = new.bookmark_id);
END
''',

  // bookmark_tags delete: same shape as ai. Post-delete the JOIN naturally
  // returns the now-shorter set; GROUP_CONCAT on empty input is NULL, which
  // COALESCE turns into ''.
  '''
CREATE TRIGGER IF NOT EXISTS bookmark_tags_ad AFTER DELETE ON bookmark_tags
BEGIN
  UPDATE bookmarks_fts
  SET tags = COALESCE(
    (SELECT GROUP_CONCAT(t.name, ' ')
     FROM bookmark_tags bt JOIN tags t ON t.id = bt.tag_id
     WHERE bt.bookmark_id = old.bookmark_id),
    '')
  WHERE rowid = (SELECT rowid FROM bookmarks WHERE id = old.bookmark_id);
END
''',
];

/// Backfill statement run during the v5 -> v6 upgrade. Walks `bookmarks`
/// and computes the (title, url, notes, tags) tuple for every existing
/// row in a single INSERT...SELECT.
///
/// **Not self-idempotent.** Running this statement twice against a
/// populated FTS5 table throws on the rowid uniqueness constraint
/// (verified by the migration test suite). The statement is safe under
/// normal operation only because it lives inside the `from < 6`
/// migration gate -- the gate is what prevents replay, not any quality
/// of the SQL itself. Force-rebuild paths (corruption recovery, schema
/// repair tooling) must `DELETE FROM bookmarks_fts` first; the
/// `clean-replay path` migration test exercises that recipe.
const String kFtsBackfillStatement = '''
INSERT INTO bookmarks_fts(rowid, title, url, notes, tags)
SELECT b.rowid,
       b.title,
       b.url,
       COALESCE(b.notes, ''),
       COALESCE(
         (SELECT GROUP_CONCAT(t.name, ' ')
          FROM bookmark_tags bt JOIN tags t ON t.id = bt.tag_id
          WHERE bt.bookmark_id = b.id),
         '')
FROM bookmarks b
''';
