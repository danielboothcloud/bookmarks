import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/database/sync_queue_repository.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueueRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SyncQueueRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> _seed(
    String operation,
    String entityType,
    String entityId, {
    int? createdAt,
  }) async {
    await db.customStatement(
      'INSERT INTO sync_queue (operation, entity_type, entity_id, payload, '
      'created_at) VALUES (?, ?, ?, NULL, ?)',
      [
        operation,
        entityType,
        entityId,
        createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ],
    );
    // customStatement bypasses Drift's update notification system; manually
    // mark the table updated so watch streams refire (mirrors what the
    // production-path SQL triggers fire automatically via the sqlite3
    // update_hook on Drift-API writes).
    db.markTablesUpdated({db.syncQueue});
  }

  test('watchPendingCount emits 0 then 1 then 2 as rows are inserted',
      () async {
    final emissions = <int>[];
    final sub = repo.watchPendingCount().listen(emissions.add);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 0);

    await _seed('upsert', 'bookmark', 'b1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 1);

    await _seed('delete', 'folder', 'f1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 2);

    await sub.cancel();
  });

  test('drain returns rows in created_at ASC then id ASC order', () async {
    await _seed('upsert', 'bookmark', 'b1', createdAt: 1000);
    await _seed('upsert', 'folder', 'f1', createdAt: 2000);
    await _seed('upsert', 'tag', 't1', createdAt: 1000); // tied timestamp
    // id ordering is 1, 2, 3 so for the tied timestamps the earlier insert
    // (b1) comes before t1.

    final rows = await repo.drain();
    expect(rows.map((r) => r.entityId).toList(), ['b1', 't1', 'f1']);
  });

  test('deleteByIds removes only the specified rows', () async {
    await _seed('upsert', 'bookmark', 'b1');
    await _seed('upsert', 'bookmark', 'b2');
    await _seed('upsert', 'bookmark', 'b3');

    final all = await repo.drain();
    expect(all, hasLength(3));

    final twoIds = [all[0].id, all[2].id];
    final deletedCount = await repo.deleteByIds(twoIds);
    expect(deletedCount, 2);

    final remaining = await repo.drain();
    expect(remaining.map((r) => r.entityId).toList(), ['b2']);
  });

  test('deleteByIds with empty list is a no-op', () async {
    await _seed('upsert', 'bookmark', 'b1');
    final count = await repo.deleteByIds(const <int>[]);
    expect(count, 0);
    expect(await repo.drain(), hasLength(1));
  });

  test(
      'rows inserted between drain() and deleteByIds() survive the selective '
      'delete', () async {
    await _seed('upsert', 'bookmark', 'b1');
    final drained = await repo.drain();
    expect(drained, hasLength(1));

    // Simulate a fresh user mutation arriving after the drain snapshot.
    await _seed('upsert', 'bookmark', 'b2');

    await repo.deleteByIds(drained.map((r) => r.id).toList());

    final remaining = await repo.drain();
    expect(remaining.map((r) => r.entityId).toList(), ['b2']);
  });

  test('watchPendingCount re-emits after deleteByIds drains the queue',
      () async {
    final emissions = <int>[];
    final sub = repo.watchPendingCount().listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 0);

    await _seed('upsert', 'bookmark', 'b1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 1);

    final rows = await repo.drain();
    await repo.deleteByIds(rows.map((r) => r.id).toList());
    db.markTablesUpdated({db.syncQueue});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.last, 0);

    await sub.cancel();
  });
}
