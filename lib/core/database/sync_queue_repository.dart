import 'package:drift/drift.dart';

import 'app_database.dart';

/// Reads the outbox: streams the pending row count, drains snapshots of
/// the queue for upload, and deletes the captured IDs after a successful
/// push.
///
/// The sync engine reads from this repository; the triggers in
/// `sync_triggers_schema.dart` are the only writers. The engine never
/// inserts into `sync_queue` itself.
class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  /// Live count of pending queue rows. The Drive sync engine listens to
  /// this stream and pushes (debounced ~250ms) whenever the count
  /// transitions above zero.
  ///
  /// **Why `readsFrom` spans the source tables, not just `sync_queue`.**
  /// The outbox rows are written by SQL triggers (Story 4.2), not by
  /// the Dart API. Drift's update-notifier observes the table its
  /// statements declare, but triggered side-effects on a *different*
  /// table are invisible to it. The pragmatic fix: declare every table
  /// whose mutation fires a sync trigger as a read-source. Any
  /// user-initiated write to bookmarks / folders / tags / bookmark_tags
  /// then refires the count query — which, by then, includes the row
  /// the trigger just inserted into `sync_queue`. Including
  /// `sync_queue` itself keeps explicit `deleteByIds(...)` drains
  /// triggering a re-emit (since `deleteByIds` IS a Drift-API write).
  Stream<int> watchPendingCount() {
    return _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sync_queue',
          readsFrom: {
            _db.syncQueue,
            _db.bookmarks,
            _db.folders,
            _db.tags,
            _db.bookmarkTags,
          },
        )
        .watchSingle()
        .map((row) => row.read<int>('c'));
  }

  /// One-time read of the queue's current rows, ordered by insertion
  /// (`created_at` ASC then `id` ASC -- second-resolution timestamps
  /// from the triggers tie on rapid bursts, so `id` is the tiebreaker).
  ///
  /// The caller retains the list of IDs and deletes them via
  /// [deleteByIds] only after the corresponding snapshot has been
  /// successfully uploaded. Rows inserted between drain start and
  /// upload completion survive the next drain unaffected -- this is
  /// the at-least-once-snapshot semantics the engine relies on.
  Future<List<SyncQueueRow>> drain() {
    final query = _db.select(_db.syncQueue)
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.get();
  }

  /// Deletes only the rows with the given IDs. Returns the count
  /// deleted (for test assertions; the engine ignores the return).
  ///
  /// Selective delete preserves any rows that arrived in the queue
  /// between [drain] and the corresponding upload's success.
  Future<int> deleteByIds(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (_db.delete(_db.syncQueue)..where((t) => t.id.isIn(ids))).go();
  }
}
