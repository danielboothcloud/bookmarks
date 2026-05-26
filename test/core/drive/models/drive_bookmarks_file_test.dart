import 'dart:convert';

import 'package:bookmarks/core/drive/drive_file_service.dart';
import 'package:bookmarks/core/drive/models/drive_bookmark.dart';
import 'package:bookmarks/core/drive/models/drive_bookmarks_file.dart';
import 'package:bookmarks/core/drive/models/drive_folder.dart';
import 'package:bookmarks/core/drive/models/drive_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriveBookmarksFile JSON envelope (v1)', () {
    test('toJson/fromJson round-trips a populated envelope', () {
      const original = DriveBookmarksFile(
        version: 1,
        lastModified: '2026-05-20T14:23:45.123Z',
        bookmarks: [
          DriveBookmark(
            id: 'b1',
            url: 'https://example.com',
            title: 'Example',
            notes: 'Some notes',
            folderId: 'f1',
            faviconBase64: 'data:image/png;base64,xyz==',
            tagIds: ['t1', 't2'],
            createdAt: '2026-05-20T10:00:00.000Z',
            updatedAt: '2026-05-20T10:00:00.000Z',
          ),
        ],
        folders: [
          DriveFolder(
            id: 'f1',
            name: 'Reading',
            parentId: null,
            createdAt: '2026-05-20T09:00:00.000Z',
            updatedAt: '2026-05-20T09:00:00.000Z',
          ),
        ],
        tags: [
          DriveTag(
            id: 't1',
            name: 'flutter',
            createdAt: '2026-05-20T08:00:00.000Z',
            updatedAt: '2026-05-20T08:00:00.000Z',
          ),
        ],
      );

      final encoded = jsonEncode(original.toJson());
      final decoded =
          DriveBookmarksFile.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

      expect(decoded, original);
    });

    test('null optional fields are omitted from the emitted JSON', () {
      const bookmark = DriveBookmark(
        id: 'b1',
        url: 'https://example.com',
        title: 'Example',
        // notes / folderId / faviconBase64 left null
        createdAt: '2026-05-20T10:00:00.000Z',
        updatedAt: '2026-05-20T10:00:00.000Z',
      );
      final json = bookmark.toJson();
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('folderId'), isFalse);
      expect(json.containsKey('faviconBase64'), isFalse);
      expect(json['id'], 'b1');
      expect(json['title'], 'Example');
    });

    test('tagIds is always present in JSON even when empty', () {
      const bookmark = DriveBookmark(
        id: 'b1',
        url: 'https://example.com',
        title: 'Example',
        createdAt: '2026-05-20T10:00:00.000Z',
        updatedAt: '2026-05-20T10:00:00.000Z',
        // tagIds defaults to []
      );
      final json = bookmark.toJson();
      expect(json['tagIds'], <String>[]);
    });

    test('parentId is omitted from DriveFolder JSON when null', () {
      const folder = DriveFolder(
        id: 'f1',
        name: 'Reading',
        // parentId left null
        createdAt: '2026-05-20T09:00:00.000Z',
        updatedAt: '2026-05-20T09:00:00.000Z',
      );
      final json = folder.toJson();
      expect(json.containsKey('parentId'), isFalse);
    });

    test('field order follows declaration order', () {
      const file = DriveBookmarksFile(
        version: 1,
        lastModified: '2026-05-20T14:23:45.123Z',
        bookmarks: [],
        folders: [],
        tags: [],
      );
      final json = file.toJson();
      // Map.keys preserves insertion order, which json_serializable emits
      // in declaration order.
      expect(json.keys.toList(),
          ['version', 'lastModified', 'bookmarks', 'folders', 'tags']);
    });

    test('parsing the empty v1 envelope from DriveFileService round-trips '
        'to all-empty lists', () {
      // Forward-compat check: the exact JSON string DriveFileService writes
      // when it provisions a new bookmarks.json must parse cleanly into our
      // typed envelope.
      final emptyJson = DriveFileService.emptyBookmarksJson();
      final parsed = DriveBookmarksFile.fromJson(
        jsonDecode(emptyJson) as Map<String, dynamic>,
      );
      expect(parsed.version, 1);
      expect(parsed.lastModified, isNotEmpty);
      expect(parsed.bookmarks, isEmpty);
      expect(parsed.folders, isEmpty);
      expect(parsed.tags, isEmpty);
    });

    test('unknown extra fields are silently ignored on fromJson', () {
      // Forward-compat for a future v2 envelope that adds fields.
      final json = <String, dynamic>{
        'version': 1,
        'lastModified': '2026-05-20T14:23:45.123Z',
        'bookmarks': <Map<String, dynamic>>[],
        'folders': <Map<String, dynamic>>[],
        'tags': <Map<String, dynamic>>[],
        'unknownFutureField': 'ignored',
        'anotherFutureField': <int>[1, 2, 3],
      };
      final parsed = DriveBookmarksFile.fromJson(json);
      expect(parsed.version, 1);
    });

    test('compact JSON has no extra whitespace', () {
      const file = DriveBookmarksFile(
        version: 1,
        lastModified: '2026-05-20T14:23:45.123Z',
        bookmarks: [],
        folders: [],
        tags: [],
      );
      final compact = jsonEncode(file.toJson());
      // Compact encoding contains no spaces or newlines.
      expect(compact.contains('\n'), isFalse);
      expect(compact.contains(': '), isFalse);
    });
  });
}
