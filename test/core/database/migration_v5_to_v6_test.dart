import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/fts_schema.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/migrations/schema.dart';

/// Story 3.1: validates the v5 -> v6 schema migration that adds the FTS5
/// virtual table `bookmarks_fts`, its 5 sync triggers, and backfills the
/// index from existing data. drift_dev's `migrateAndValidate` covers
/// matching the snapshot but FTS5 virtual tables don't appear in the
/// snapshot, so these tests assert their existence + correct backfill via
/// runtime sqlite_master + MATCH queries.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('schema v5 -> v6 migration produces the expected v6 schema (snapshot)',
      () async {
    // The v6 snapshot is identical to v5 because FTS virtual tables are
    // not captured by drift_dev's schema dumper. migrateAndValidate still
    // exercises the migration path; the FTS-specific assertions live in
    // the runtime tests below.
    final connection = await verifier.startAt(5);
    final db = AppDatabase.forTesting(connection.executor);
    await verifier.migrateAndValidate(db, 6);
    await db.close();
  });

  test('v5 -> v6 with empty database: bookmarks_fts table + 5 triggers exist',
      () async {
    final schema = await verifier.schemaAt(5);
    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // FTS virtual table present.
    final ftsTable = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='table' AND name='bookmarks_fts'",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(ftsTable, hasLength(1));

    // Five sync triggers present.
    final triggerNames = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='trigger' AND name IN "
          "('bookmarks_ai','bookmarks_ad','bookmarks_au',"
          "'bookmark_tags_ai','bookmark_tags_ad') ORDER BY name",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(
      triggerNames.map((r) => r.read<String>('name')).toList(),
      [
        'bookmark_tags_ad',
        'bookmark_tags_ai',
        'bookmarks_ad',
        'bookmarks_ai',
        'bookmarks_au',
      ],
    );

    // FTS index empty.
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM bookmarks_fts',
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(count.read<int>('n'), 0);

    await db.close();
  });

  test(
      'v5 -> v6 with bookmarks (no tags): backfill populates title/url/notes; '
      'MATCH returns the right rows', () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-1', 'https://flutter.dev/widgets', 'Flutter widgets', "
      "'official api docs', NULL, NULL, 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-2', 'https://dart.dev', 'Dart language', "
      'NULL, NULL, NULL, 2, 2)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-3', 'https://example.org', 'Hello', "
      "'Notes mentioning dynamic-programming research', "
      'NULL, NULL, 3, 3)',
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // Three rows backfilled.
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM bookmarks_fts',
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(count.read<int>('n'), 3);

    // Title match.
    final title = await db
        .customSelect(
          'SELECT b.id AS id FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ?',
          variables: [const Variable<String>('flutter')],
        )
        .get();
    expect(title.map((r) => r.read<String>('id')).toList(), ['bm-1']);

    // URL host match. FTS5's unicode61 tokenizer splits on `.` so "dart"
    // alone hits the dart.dev URL.
    final url = await db
        .customSelect(
          'SELECT b.id AS id FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ?',
          variables: [const Variable<String>('dart')],
        )
        .get();
    expect(url.map((r) => r.read<String>('id')).toList(), ['bm-2']);

    // Notes-only match.
    final notes = await db
        .customSelect(
          'SELECT b.id AS id FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ?',
          variables: [const Variable<String>('dynamic')],
        )
        .get();
    expect(notes.map((r) => r.read<String>('id')).toList(), ['bm-3']);

    await db.close();
  });

  test(
      'v5 -> v6 with bookmarks + tags: backfill computes concatenated tag '
      'string per bookmark', () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-tagged', 'https://example.com', 'Generic title', "
      'NULL, NULL, NULL, 1, 1)',
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t-graphql', 'graphql', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      "VALUES ('t-api', 'api', 1, 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('bm-tagged', 't-graphql', 1)",
    );
    schema.rawDatabase.execute(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      "VALUES ('bm-tagged', 't-api', 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // Tags column populated. Order from GROUP_CONCAT is not strictly
    // deterministic without ORDER BY, but for two tags the set should
    // contain both names.
    final tagsRow = await db
        .customSelect(
          'SELECT tags FROM bookmarks_fts WHERE rowid = '
          "(SELECT rowid FROM bookmarks WHERE id = 'bm-tagged')",
          variables: <Variable<Object>>[],
        )
        .getSingle();
    final tagsString = tagsRow.read<String>('tags');
    expect(tagsString, contains('graphql'));
    expect(tagsString, contains('api'));

    // tag-only MATCH returns the bookmark.
    final hits = await db
        .customSelect(
          'SELECT b.id AS id FROM bookmarks b '
          'JOIN bookmarks_fts fts ON fts.rowid = b.rowid '
          'WHERE bookmarks_fts MATCH ?',
          variables: [const Variable<String>('graphql')],
        )
        .get();
    expect(hits.map((r) => r.read<String>('id')).toList(), ['bm-tagged']);

    await db.close();
  });

  test('clean-replay path: DELETE + create-IF-NOT-EXISTS + backfill restores '
      'the FTS table to its pre-replay state', () async {
    // This is the documented force-rebuild recipe (corruption recovery,
    // schema-tooling repair). It is NOT a claim that `kFtsBackfillStatement`
    // is idempotent on its own -- the live migration is gated by `from < 6`
    // so replay never happens in normal operation; the statement does not
    // protect itself against double-INSERT (see the test below).
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-x', 'https://e.com', 'Topic X', NULL, NULL, NULL, 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final beforeReplay = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM bookmarks_fts',
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(beforeReplay.read<int>('n'), 1);

    await db.customStatement('DELETE FROM bookmarks_fts');
    for (final stmt in kFtsCreateStatements) {
      await db.customStatement(stmt);
    }
    await db.customStatement(kFtsBackfillStatement);

    final afterReplay = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM bookmarks_fts',
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(afterReplay.read<int>('n'), 1);

    await db.close();
  });

  test('backfill statement is NOT self-idempotent: re-running without DELETE '
      'throws a constraint failure (locks in the contract)', () async {
    // Pinning behaviour so a future change can't silently make this
    // statement idempotent without also revisiting the migration gate
    // and the documented force-rebuild recipe in `fts_schema.dart`.
    // The fail-loud throw is preferable to silently duplicating rows --
    // any caller that wants idempotence has to opt in via DELETE first.
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) '
      "VALUES ('bm-x', 'https://e.com', 'Topic X', NULL, NULL, NULL, 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    expect(
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM bookmarks_fts',
                variables: <Variable<Object>>[],
              )
              .getSingle())
          .read<int>('n'),
      1,
    );

    // Re-running without first DELETE-ing the rows throws on the rowid
    // constraint -- proves the statement is not self-idempotent.
    expect(
      () async => db.customStatement(kFtsBackfillStatement),
      throwsA(isA<Object>()),
      reason: 'kFtsBackfillStatement is not self-idempotent; '
          'force-rebuild paths must DELETE FROM bookmarks_fts first',
    );

    await db.close();
  });

  test(
      'v1 -> v6 skip-version migration applies all deltas including FTS5 '
      'foundation', () async {
    // v1 was the empty pre-Story 1.2 schema; simulate by stamping
    // user_version=1 on a fresh in-memory db. AppDatabase will then run
    // onUpgrade(m, 1, 6).
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 1'),
      ),
    );
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    // All five tables created.
    final tables = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='table' "
          "AND name IN ('bookmarks','sync_queue','folders','tags',"
          "'bookmark_tags','bookmarks_fts') ORDER BY name",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(
      tables.map((r) => r.read<String>('name')).toList(),
      [
        'bookmark_tags',
        'bookmarks',
        'bookmarks_fts',
        'folders',
        'sync_queue',
        'tags',
      ],
    );

    // All five FTS triggers created.
    final triggers = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sqlite_master '
          "WHERE type='trigger' AND name IN "
          "('bookmarks_ai','bookmarks_ad','bookmarks_au',"
          "'bookmark_tags_ai','bookmark_tags_ad')",
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(triggers.read<int>('n'), 5);

    await db.close();
  });

  test('fresh v6 install (onCreate): FTS table + triggers exist', () async {
    // No prior schema; opening AppDatabase runs onCreate.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .customSelect('SELECT 1', variables: <Variable<Object>>[])
        .getSingle();

    final ftsRow = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type='table' AND name='bookmarks_fts'",
          variables: <Variable<Object>>[],
        )
        .get();
    expect(ftsRow, hasLength(1));

    final triggers = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sqlite_master '
          "WHERE type='trigger' AND name IN "
          "('bookmarks_ai','bookmarks_ad','bookmarks_au',"
          "'bookmark_tags_ai','bookmark_tags_ad')",
          variables: <Variable<Object>>[],
        )
        .getSingle();
    expect(triggers.read<int>('n'), 5);

    await db.close();
  });
}
