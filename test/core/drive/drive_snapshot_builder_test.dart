import 'dart:convert';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/drive_snapshot_builder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriveSnapshotBuilder builder;

  final fixedClock = DateTime.utc(2026, 5, 20, 14, 23, 45, 123);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = DriveSnapshotBuilder(db, clock: () => fixedClock);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedBookmark({
    required String id,
    String? folderId,
    String? notes,
    String? favicon,
    int createdAt = 1000,
    int updatedAt = 1000,
  }) async {
    await db.customStatement(
      'INSERT INTO bookmarks (id, url, title, notes, folder_id, '
      'favicon_base64, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        'https://example.com/$id',
        'Title $id',
        notes,
        folderId,
        favicon,
        createdAt,
        updatedAt,
      ],
    );
  }

  Future<void> seedFolder({
    required String id,
    String? parentId,
    int createdAt = 1000,
  }) async {
    await db.customStatement(
      'INSERT INTO folders (id, name, parent_id, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, 'Folder $id', parentId, createdAt, createdAt],
    );
  }

  Future<void> seedTag({
    required String id,
    int createdAt = 1000,
  }) async {
    await db.customStatement(
      'INSERT INTO tags (id, name, created_at, updated_at) '
      'VALUES (?, ?, ?, ?)',
      [id, 'Tag $id', createdAt, createdAt],
    );
  }

  Future<void> seedLink(String bookmarkId, String tagId) async {
    await db.customStatement(
      'INSERT INTO bookmark_tags (bookmark_id, tag_id, created_at) '
      'VALUES (?, ?, ?)',
      [bookmarkId, tagId, 1],
    );
  }

  test('empty database produces an empty v1 envelope', () async {
    final snapshot = await builder.build();
    expect(snapshot.version, 1);
    expect(snapshot.lastModified, fixedClock.toIso8601String());
    expect(snapshot.bookmarks, isEmpty);
    expect(snapshot.folders, isEmpty);
    expect(snapshot.tags, isEmpty);
  });

  test('single bookmark with no tags has tagIds = []', () async {
    await seedBookmark(id: 'b1');
    final snapshot = await builder.build();
    expect(snapshot.bookmarks, hasLength(1));
    expect(snapshot.bookmarks.first.id, 'b1');
    expect(snapshot.bookmarks.first.tagIds, isEmpty);
  });

  test('single bookmark with two tags has tagIds in tagId order', () async {
    await seedBookmark(id: 'b1');
    await seedTag(id: 't-alpha');
    await seedTag(id: 't-beta');
    await seedLink('b1', 't-beta');
    await seedLink('b1', 't-alpha');

    final snapshot = await builder.build();
    expect(snapshot.bookmarks.first.tagIds, ['t-alpha', 't-beta']);
  });

  test('nested folders appear with correct parentId references', () async {
    await seedFolder(id: 'f-root', createdAt: 100);
    await seedFolder(id: 'f-child', parentId: 'f-root', createdAt: 200);
    await seedFolder(id: 'f-grand', parentId: 'f-child', createdAt: 300);

    final snapshot = await builder.build();
    expect(snapshot.folders, hasLength(3));
    expect(snapshot.folders.map((f) => f.id).toList(),
        ['f-root', 'f-child', 'f-grand']);
    expect(snapshot.folders.firstWhere((f) => f.id == 'f-root').parentId,
        isNull);
    expect(snapshot.folders.firstWhere((f) => f.id == 'f-child').parentId,
        'f-root');
    expect(snapshot.folders.firstWhere((f) => f.id == 'f-grand').parentId,
        'f-child');
  });

  test('two snapshots of a stable DB produce byte-identical JSON', () async {
    await seedFolder(id: 'f1', createdAt: 100);
    await seedBookmark(id: 'b1', folderId: 'f1', createdAt: 200);
    await seedTag(id: 't1');
    await seedLink('b1', 't1');

    final json1 = jsonEncode((await builder.build()).toJson());
    final json2 = jsonEncode((await builder.build()).toJson());
    expect(json1, json2);
  });

  test('bookmark createdAt/updatedAt are emitted as ISO 8601 UTC strings',
      () async {
    // 1716210000000 ms since epoch -> 2024-05-20T13:00:00.000Z
    await seedBookmark(id: 'b1', createdAt: 1716210000000, updatedAt: 1716220000000);

    final snapshot = await builder.build();
    final bm = snapshot.bookmarks.single;
    expect(bm.createdAt, endsWith('Z'));
    expect(bm.updatedAt, endsWith('Z'));
    expect(DateTime.parse(bm.createdAt).isAtSameMomentAs(
      DateTime.fromMillisecondsSinceEpoch(1716210000000, isUtc: true),
    ), isTrue);
  });

  test('null bookmark fields (notes, folderId, faviconBase64) are preserved',
      () async {
    await seedBookmark(id: 'b1');
    final snapshot = await builder.build();
    final bm = snapshot.bookmarks.single;
    expect(bm.notes, isNull);
    expect(bm.folderId, isNull);
    expect(bm.faviconBase64, isNull);
  });

  test('bookmarks are sorted by createdAt ASC then id ASC', () async {
    await seedBookmark(id: 'b-z', createdAt: 100);
    await seedBookmark(id: 'b-a', createdAt: 100); // tied
    await seedBookmark(id: 'b-m', createdAt: 50);

    final snapshot = await builder.build();
    expect(snapshot.bookmarks.map((b) => b.id).toList(),
        ['b-m', 'b-a', 'b-z']);
  });
}
