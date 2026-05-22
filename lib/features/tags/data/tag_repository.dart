import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/app_error.dart';
import '../../../core/error/result.dart';
import '../domain/i_tag_repository.dart';
import '../domain/tag.dart';
import '../domain/tag_with_count.dart';

class TagRepository implements ITagRepository {
  TagRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  @override
  Stream<List<Tag>> watchAll() {
    // Alpha-by-name (case-insensitive) -- COLLATE NOCASE ensures "Flutter"
    // and "flutter" sort together regardless of which case was stored. Drift's
    // typed query builder doesn't expose COLLATE ergonomically, so a
    // customSelect with explicit SQL is clearer.
    return _db
        .customSelect(
          'SELECT * FROM tags ORDER BY name COLLATE NOCASE ASC',
          readsFrom: {_db.tags},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => Tag(
                  id: r.read<String>('id'),
                  name: r.read<String>('name'),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('created_at'),
                  ),
                  updatedAt: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('updated_at'),
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() {
    // LEFT JOIN keeps tags with zero junctions in the result (count = 0 --
    // FR16: tags survive their last bookmark). GROUP BY t.id collapses
    // junction multiplicity to one row per tag. ORDER BY name COLLATE NOCASE
    // matches `watchAll`'s ordering so consumers can switch between the two
    // streams without re-sorting client-side. The LEFT JOIN reuses the
    // `idx_bookmark_tags_tag_id` reverse-direction index installed in Story
    // 2.5 -- exactly the access pattern the index was added for. A single
    // SQL emission is atomically consistent: combining two streams (tags +
    // counts) in the application layer would surface "added with count 0"
    // frames before the count stream catches up.
    //
    // COUNT(bt.bookmark_id) (not COUNT(*)): with LEFT JOIN, a tag with no
    // junction rows produces one row whose `bt.*` columns are NULL.
    // COUNT(*) would count that NULL row as 1; COUNT(bt.bookmark_id) skips
    // NULLs and returns 0 -- the standard "count matched right-side rows"
    // SQL idiom.
    return _db
        .customSelect(
          'SELECT t.id, t.name, t.created_at, t.updated_at, '
          '       COUNT(bt.bookmark_id) AS bookmark_count '
          'FROM tags t '
          'LEFT JOIN bookmark_tags bt ON bt.tag_id = t.id '
          'GROUP BY t.id '
          'ORDER BY t.name COLLATE NOCASE ASC',
          readsFrom: {_db.tags, _db.bookmarkTags},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => TagWithCount(
                  tag: Tag(
                    id: r.read<String>('id'),
                    name: r.read<String>('name'),
                    createdAt: DateTime.fromMillisecondsSinceEpoch(
                      r.read<int>('created_at'),
                    ),
                    updatedAt: DateTime.fromMillisecondsSinceEpoch(
                      r.read<int>('updated_at'),
                    ),
                  ),
                  count: r.read<int>('bookmark_count'),
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) {
    // Inner join via custom SQL -- typed Drift joins are possible but verbose;
    // the SQL here is short and explicit about the order. ORDER BY
    // bt.created_at ASC = "tags appear in the order the user added them"
    // (AC2 chip ordering).
    return _db
        .customSelect(
          'SELECT t.* FROM tags t '
          'INNER JOIN bookmark_tags bt ON bt.tag_id = t.id '
          'WHERE bt.bookmark_id = ? '
          'ORDER BY bt.created_at ASC',
          variables: [Variable<String>(bookmarkId)],
          readsFrom: {_db.tags, _db.bookmarkTags},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => Tag(
                  id: r.read<String>('id'),
                  name: r.read<String>('name'),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('created_at'),
                  ),
                  updatedAt: DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('updated_at'),
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<Result<Tag, AppError>> getById(String id) async {
    try {
      final row = await (_db.select(_db.tags)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return const Err<Tag, AppError>(NotFoundError());
      return Ok<Tag, AppError>(Tag.fromDrift(row));
    } catch (e) {
      return Err<Tag, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<Tag, AppError>> findByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err<Tag, AppError>(NotFoundError());
    }
    try {
      // lower(name) = lower(?) leverages the functional UNIQUE index.
      final row = await _db
          .customSelect(
            'SELECT * FROM tags WHERE lower(name) = lower(?) LIMIT 1',
            variables: [Variable<String>(trimmed)],
            readsFrom: {_db.tags},
          )
          .getSingleOrNull();
      if (row == null) return const Err<Tag, AppError>(NotFoundError());
      return Ok<Tag, AppError>(
        Tag(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('updated_at'),
          ),
        ),
      );
    } catch (e) {
      return Err<Tag, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err<Tag, AppError>(
        StorageError('Tag name cannot be empty'),
      );
    }
    // Find first; if found, return as-is (createdAt preserved).
    final existing = await findByName(trimmed);
    if (existing case Ok(:final value)) return Ok<Tag, AppError>(value);

    try {
      final now = DateTime.now();
      final tag = Tag(
        id: _uuid.v4(),
        name: trimmed,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.tags).insert(_toCompanion(tag));
      return Ok<Tag, AppError>(tag);
    } catch (e) {
      // Race recovery: between findByName's miss and our insert, a concurrent
      // caller may have inserted the same lower(name). The UNIQUE index throws
      // -- re-resolve via findByName.
      final raceResolution = await findByName(trimmed);
      if (raceResolution case Ok(:final value)) {
        return Ok<Tag, AppError>(value);
      }
      return Err<Tag, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<void, AppError>> linkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    try {
      await _db.transaction(() async {
        // INSERT OR IGNORE on the composite PK: re-linking the same
        // (bookmarkId, tagId) is a no-op rather than an error. Matches
        // AC1's "submitting the same name twice is idempotent".
        await _db.into(_db.bookmarkTags).insert(
              BookmarkTagsCompanion(
                bookmarkId: Value(bookmarkId),
                tagId: Value(tagId),
                createdAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        // Bump the parent bookmark's updatedAt so the per-record LWW
        // merge (merge_engine.dart) sees local > remote on the next
        // pull. Without this bump, the local link is wiped on tie
        // because _decide() falls into upsertRemote → the
        // bookmarkTagLinksToReplace branch replaces local junctions
        // with the (stale) remote tagIds. The bookmark_tags trigger
        // already enqueues an outbox row with entity_id = bookmarkId;
        // the bookmark UPDATE adds a second one (both upserts; the
        // push coalesces them into a single snapshot).
        await _bumpBookmarkUpdatedAt(bookmarkId);
      });
      return const Ok<void, AppError>(null);
    } catch (e) {
      return Err<void, AppError>(StorageError(e.toString()));
    }
  }

  @override
  Future<Result<void, AppError>> unlinkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.bookmarkTags)
              ..where(
                (t) => t.bookmarkId.equals(bookmarkId) & t.tagId.equals(tagId),
              ))
            .go();
        // FR16 (revised v5): hard-delete the tag if no junctions reference it.
        // Avoids the "tag count = 0 row stays in the sidebar forever" UX. If
        // the user re-types the same name later, upsertByName creates a fresh
        // row (different uuid, same case via lower(name) UNIQUE). Targeted
        // delete -- only the just-unlinked tag is checked, not a full sweep.
        await _db.customUpdate(
          'DELETE FROM tags WHERE id = ? AND id NOT IN ('
          '  SELECT tag_id FROM bookmark_tags WHERE tag_id = ? LIMIT 1'
          ')',
          variables: [Variable<String>(tagId), Variable<String>(tagId)],
          updates: {_db.tags},
        );
        // Same rationale as linkBookmarkTag: bump the parent so LWW
        // keeps the removal on the next merge.
        await _bumpBookmarkUpdatedAt(bookmarkId);
      });
      // We DON'T return Err on affected==0 (unlike BookmarkRepository.delete
      // which does for NotFound semantics). An idempotent unlink is the right
      // behaviour: removing a chip that's already gone (e.g. via a sync merge)
      // shouldn't surface as an error to the user.
      return const Ok<void, AppError>(null);
    } catch (e) {
      return Err<void, AppError>(StorageError(e.toString()));
    }
  }

  /// Sets `bookmarks.updated_at = now` for [bookmarkId]. No-op if the
  /// bookmark row doesn't exist (UPDATE of zero rows). The UPDATE also
  /// fires the bookmarks AU outbox trigger; that's intentional — the
  /// resulting sync_queue row carries the bumped timestamp to remote
  /// via the next push.
  Future<void> _bumpBookmarkUpdatedAt(String bookmarkId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.customUpdate(
      'UPDATE bookmarks SET updated_at = ? WHERE id = ?',
      variables: [Variable<int>(now), Variable<String>(bookmarkId)],
      updates: {_db.bookmarks},
    );
  }

  @override
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  }) async {
    // Dedup case-insensitively, preserving first-occurrence case for display
    // fidelity. ["Flutter", "flutter", "DART"] -> ["Flutter", "DART"].
    final seen = <String>{};
    final ordered = <String>[];
    for (final raw in tagNames) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) ordered.add(trimmed);
    }
    if (ordered.isEmpty) {
      return const Ok<List<Tag>, AppError>(<Tag>[]);
    }
    try {
      final result = await _db.transaction(() async {
        final tags = <Tag>[];
        for (final name in ordered) {
          // Reuse upsertByName but inside the transaction. We don't call the
          // public method (its try/catch + race-recovery path is designed for
          // the no-transaction case); inline the lookup-then-insert flow to
          // keep transaction semantics tight.
          final existing = await _db
              .customSelect(
                'SELECT * FROM tags WHERE lower(name) = lower(?) LIMIT 1',
                variables: [Variable<String>(name)],
                readsFrom: {_db.tags},
              )
              .getSingleOrNull();
          Tag tag;
          if (existing != null) {
            tag = Tag(
              id: existing.read<String>('id'),
              name: existing.read<String>('name'),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                existing.read<int>('created_at'),
              ),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                existing.read<int>('updated_at'),
              ),
            );
          } else {
            final now = DateTime.now();
            tag = Tag(
              id: _uuid.v4(),
              name: name,
              createdAt: now,
              updatedAt: now,
            );
            await _db.into(_db.tags).insert(_toCompanion(tag));
          }
          tags.add(tag);
          await _db.into(_db.bookmarkTags).insert(
                BookmarkTagsCompanion(
                  bookmarkId: Value(bookmarkId),
                  tagId: Value(tag.id),
                  createdAt: Value(DateTime.now().millisecondsSinceEpoch),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
        return tags;
      });
      return Ok<List<Tag>, AppError>(result);
    } catch (e) {
      return Err<List<Tag>, AppError>(StorageError(e.toString()));
    }
  }

  TagsCompanion _toCompanion(Tag t) => TagsCompanion(
        id: Value(t.id),
        name: Value(t.name),
        createdAt: Value(t.createdAt.millisecondsSinceEpoch),
        updatedAt: Value(t.updatedAt.millisecondsSinceEpoch),
      );
}
