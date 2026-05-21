import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/drive/local_snapshot.dart';
import 'package:bookmarks/core/drive/merge_engine.dart';
import 'package:bookmarks/core/drive/models/drive_bookmark.dart';
import 'package:bookmarks/core/drive/models/drive_bookmarks_file.dart';
import 'package:bookmarks/core/drive/models/drive_folder.dart';
import 'package:bookmarks/core/drive/models/drive_tag.dart';
import 'package:flutter_test/flutter_test.dart';

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

BookmarkRow _bRow(
  String id, {
  int updatedAt = 1000,
  int createdAt = 500,
  String? folderId,
}) {
  return BookmarkRow(
    id: id,
    url: 'https://example.com/$id',
    title: 'Title $id',
    notes: null,
    folderId: folderId,
    faviconBase64: null,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

FolderRow _fRow(
  String id, {
  int updatedAt = 1000,
  String? parentId,
}) {
  return FolderRow(
    id: id,
    name: 'Folder $id',
    parentId: parentId,
    createdAt: 500,
    updatedAt: updatedAt,
  );
}

TagRow _tRow(String id, {int updatedAt = 1000}) {
  return TagRow(
    id: id,
    name: 'Tag $id',
    createdAt: 500,
    updatedAt: updatedAt,
  );
}

DriveBookmark _dB(
  String id, {
  int updatedAtMs = 1000,
  List<String> tagIds = const <String>[],
  String? folderId,
}) {
  return DriveBookmark(
    id: id,
    url: 'https://example.com/$id',
    title: 'Title $id',
    folderId: folderId,
    tagIds: tagIds,
    createdAt: _iso(500),
    updatedAt: _iso(updatedAtMs),
  );
}

DriveFolder _dF(String id, {int updatedAtMs = 1000, String? parentId}) {
  return DriveFolder(
    id: id,
    name: 'Folder $id',
    parentId: parentId,
    createdAt: _iso(500),
    updatedAt: _iso(updatedAtMs),
  );
}

DriveTag _dT(String id, {int updatedAtMs = 1000}) {
  return DriveTag(
    id: id,
    name: 'Tag $id',
    createdAt: _iso(500),
    updatedAt: _iso(updatedAtMs),
  );
}

LocalSnapshot _localOf({
  List<BookmarkRow> bookmarks = const <BookmarkRow>[],
  List<FolderRow> folders = const <FolderRow>[],
  List<TagRow> tags = const <TagRow>[],
  Map<String, List<String>> tagIdsByBookmark = const <String, List<String>>{},
}) {
  return LocalSnapshot(
    bookmarks: bookmarks,
    folders: folders,
    tags: tags,
    tagIdsByBookmark: tagIdsByBookmark,
  );
}

DriveBookmarksFile _remoteOf({
  required int lastModifiedMs,
  List<DriveBookmark> bookmarks = const <DriveBookmark>[],
  List<DriveFolder> folders = const <DriveFolder>[],
  List<DriveTag> tags = const <DriveTag>[],
}) {
  return DriveBookmarksFile(
    version: 1,
    lastModified: _iso(lastModifiedMs),
    bookmarks: bookmarks,
    folders: folders,
    tags: tags,
  );
}

void main() {
  group('MergeEngine — bookmarks LWW truth table', () {
    test('in remote, not in local → upsert', () {
      final plan = MergeEngine.merge(
        local: _localOf(),
        remote: _remoteOf(
          lastModifiedMs: 2000,
          bookmarks: [_dB('b1', updatedAtMs: 1500)],
        ),
      );
      expect(plan.bookmarksToUpsert.map((b) => b.id), ['b1']);
      expect(plan.bookmarksToDelete, isEmpty);
      expect(plan.bookmarkTagLinksToReplace, containsPair('b1', isEmpty));
    });

    test('in local, not in remote, local updatedAt < remote lastModified → '
        'delete local', () {
      final plan = MergeEngine.merge(
        local: _localOf(bookmarks: [_bRow('b1', updatedAt: 500)]),
        remote: _remoteOf(lastModifiedMs: 1000),
      );
      expect(plan.bookmarksToDelete, ['b1']);
      expect(plan.bookmarksToUpsert, isEmpty);
    });

    test('in local, not in remote, local updatedAt >= remote lastModified → '
        'keep local', () {
      final plan = MergeEngine.merge(
        local: _localOf(bookmarks: [_bRow('b1', updatedAt: 1500)]),
        remote: _remoteOf(lastModifiedMs: 1000),
      );
      expect(plan.bookmarksToDelete, isEmpty);
      expect(plan.bookmarksToUpsert, isEmpty);
    });

    test('in both, remote updatedAt newer → upsert remote and replace '
        'junctions', () {
      final plan = MergeEngine.merge(
        local: _localOf(
          bookmarks: [_bRow('b1', updatedAt: 1000)],
          tagIdsByBookmark: {'b1': const ['t-local']},
        ),
        remote: _remoteOf(
          lastModifiedMs: 3000,
          bookmarks: [_dB('b1', updatedAtMs: 2000, tagIds: const ['t-remote'])],
        ),
      );
      expect(plan.bookmarksToUpsert.map((b) => b.id), ['b1']);
      expect(plan.bookmarkTagLinksToReplace, containsPair('b1', ['t-remote']));
    });

    test('in both, local updatedAt newer → keep local; no junction '
        'replacement', () {
      final plan = MergeEngine.merge(
        local: _localOf(bookmarks: [_bRow('b1', updatedAt: 3000)]),
        remote: _remoteOf(
          lastModifiedMs: 3500,
          bookmarks: [_dB('b1', updatedAtMs: 1000, tagIds: const ['t-remote'])],
        ),
      );
      expect(plan.bookmarksToUpsert, isEmpty);
      expect(plan.bookmarksToDelete, isEmpty);
      expect(plan.bookmarkTagLinksToReplace, isEmpty);
    });

    test('in both, updatedAt exactly equal → upsert remote (tiebreaker)', () {
      // Deterministic tiebreaker: same id, remote wins. The actual id-asc
      // comparison is moot because there's only one record id; the
      // tiebreaker exists for defensive determinism.
      final plan = MergeEngine.merge(
        local: _localOf(bookmarks: [_bRow('b1', updatedAt: 2000)]),
        remote: _remoteOf(
          lastModifiedMs: 2500,
          bookmarks: [_dB('b1', updatedAtMs: 2000, tagIds: const ['t-remote'])],
        ),
      );
      expect(plan.bookmarksToUpsert.map((b) => b.id), ['b1']);
      expect(plan.bookmarkTagLinksToReplace, containsPair('b1', ['t-remote']));
    });
  });

  group('MergeEngine — folders LWW truth table', () {
    test('in remote, not in local → upsert', () {
      final plan = MergeEngine.merge(
        local: _localOf(),
        remote: _remoteOf(
          lastModifiedMs: 2000,
          folders: [_dF('f1', updatedAtMs: 1500)],
        ),
      );
      expect(plan.foldersToUpsert.map((f) => f.id), ['f1']);
    });

    test('in local, not in remote, local updatedAt < remote lastModified → '
        'delete', () {
      final plan = MergeEngine.merge(
        local: _localOf(folders: [_fRow('f1', updatedAt: 500)]),
        remote: _remoteOf(lastModifiedMs: 2000),
      );
      expect(plan.foldersToDelete, ['f1']);
    });

    test('in local, not in remote, local updatedAt >= remote lastModified → '
        'keep', () {
      final plan = MergeEngine.merge(
        local: _localOf(folders: [_fRow('f1', updatedAt: 3000)]),
        remote: _remoteOf(lastModifiedMs: 2000),
      );
      expect(plan.foldersToDelete, isEmpty);
      expect(plan.foldersToUpsert, isEmpty);
    });

    test('in both, remote newer → upsert remote', () {
      final plan = MergeEngine.merge(
        local: _localOf(folders: [_fRow('f1', updatedAt: 1000)]),
        remote: _remoteOf(
          lastModifiedMs: 2500,
          folders: [_dF('f1', updatedAtMs: 2000)],
        ),
      );
      expect(plan.foldersToUpsert.map((f) => f.id), ['f1']);
    });

    test('topological sort: parent emitted before child', () {
      final plan = MergeEngine.merge(
        local: _localOf(),
        remote: _remoteOf(
          lastModifiedMs: 5000,
          folders: [
            _dF('child', updatedAtMs: 1000, parentId: 'parent'),
            _dF('parent', updatedAtMs: 1000),
            _dF('grandchild', updatedAtMs: 1000, parentId: 'child'),
          ],
        ),
      );
      final ids = plan.foldersToUpsert.map((f) => f.id).toList();
      expect(ids.indexOf('parent'), lessThan(ids.indexOf('child')));
      expect(ids.indexOf('child'), lessThan(ids.indexOf('grandchild')));
    });
  });

  group('MergeEngine — tags LWW truth table', () {
    test('in remote, not in local → upsert', () {
      final plan = MergeEngine.merge(
        local: _localOf(),
        remote: _remoteOf(
          lastModifiedMs: 2000,
          tags: [_dT('t1', updatedAtMs: 1500)],
        ),
      );
      expect(plan.tagsToUpsert.map((t) => t.id), ['t1']);
    });

    test('in local, not in remote, local older than remote lastModified → '
        'delete', () {
      final plan = MergeEngine.merge(
        local: _localOf(tags: [_tRow('t1', updatedAt: 500)]),
        remote: _remoteOf(lastModifiedMs: 1000),
      );
      expect(plan.tagsToDelete, ['t1']);
    });

    test('in both, remote newer → upsert remote', () {
      final plan = MergeEngine.merge(
        local: _localOf(tags: [_tRow('t1', updatedAt: 1000)]),
        remote: _remoteOf(
          lastModifiedMs: 3000,
          tags: [_dT('t1', updatedAtMs: 2000)],
        ),
      );
      expect(plan.tagsToUpsert.map((t) => t.id), ['t1']);
    });
  });

  group('MergeEngine — junction replacement semantics', () {
    test('bookmark wins remotely → junctions replaced with remote tagIds', () {
      final plan = MergeEngine.merge(
        local: _localOf(
          bookmarks: [_bRow('b1', updatedAt: 1000)],
          tagIdsByBookmark: {'b1': const ['t1', 't3']},
        ),
        remote: _remoteOf(
          lastModifiedMs: 3000,
          bookmarks: [_dB('b1', updatedAtMs: 2000, tagIds: const ['t1', 't2'])],
        ),
      );
      expect(plan.bookmarkTagLinksToReplace,
          containsPair('b1', orderedEquals(['t1', 't2'])));
    });

    test('bookmark wins locally → junctions preserved (no replacement '
        'instruction)', () {
      final plan = MergeEngine.merge(
        local: _localOf(
          bookmarks: [_bRow('b1', updatedAt: 3000)],
          tagIdsByBookmark: {'b1': const ['t1', 't3']},
        ),
        remote: _remoteOf(
          lastModifiedMs: 3500,
          bookmarks: [_dB('b1', updatedAtMs: 1000, tagIds: const ['t1', 't2'])],
        ),
      );
      expect(plan.bookmarkTagLinksToReplace, isEmpty);
    });
  });

  group('MergeEngine — FR36 first-launch', () {
    test('empty local + non-empty remote → every record is an upsert', () {
      final plan = MergeEngine.merge(
        local: _localOf(),
        remote: _remoteOf(
          lastModifiedMs: 5000,
          bookmarks: [
            _dB('b1', updatedAtMs: 1000),
            _dB('b2', updatedAtMs: 2000),
          ],
          folders: [_dF('f1', updatedAtMs: 1000)],
          tags: [_dT('t1', updatedAtMs: 1000)],
        ),
      );
      expect(plan.bookmarksToUpsert.map((b) => b.id), unorderedEquals(['b1', 'b2']));
      expect(plan.foldersToUpsert.map((f) => f.id), ['f1']);
      expect(plan.tagsToUpsert.map((t) => t.id), ['t1']);
      expect(plan.bookmarksToDelete, isEmpty);
      expect(plan.foldersToDelete, isEmpty);
      expect(plan.tagsToDelete, isEmpty);
    });
  });

  group('MergeEngine — empty remote + populated local', () {
    test('lastModified post-dates all local rows → all deleted', () {
      final plan = MergeEngine.merge(
        local: _localOf(
          bookmarks: [_bRow('b1', updatedAt: 500)],
          folders: [_fRow('f1', updatedAt: 500)],
          tags: [_tRow('t1', updatedAt: 500)],
        ),
        remote: _remoteOf(lastModifiedMs: 5000),
      );
      expect(plan.bookmarksToDelete, ['b1']);
      expect(plan.foldersToDelete, ['f1']);
      expect(plan.tagsToDelete, ['t1']);
    });

    test('lastModified predates local rows → keep everything', () {
      final plan = MergeEngine.merge(
        local: _localOf(
          bookmarks: [_bRow('b1', updatedAt: 9000)],
          folders: [_fRow('f1', updatedAt: 9000)],
          tags: [_tRow('t1', updatedAt: 9000)],
        ),
        remote: _remoteOf(lastModifiedMs: 1000),
      );
      expect(plan.bookmarksToDelete, isEmpty);
      expect(plan.foldersToDelete, isEmpty);
      expect(plan.tagsToDelete, isEmpty);
      expect(plan.bookmarksToUpsert, isEmpty);
    });
  });

  test('empty remote on empty local → empty plan', () {
    final plan = MergeEngine.merge(
      local: _localOf(),
      remote: _remoteOf(lastModifiedMs: 1000),
    );
    expect(plan.bookmarksToUpsert, isEmpty);
    expect(plan.bookmarksToDelete, isEmpty);
    expect(plan.foldersToUpsert, isEmpty);
    expect(plan.foldersToDelete, isEmpty);
    expect(plan.tagsToUpsert, isEmpty);
    expect(plan.tagsToDelete, isEmpty);
    expect(plan.bookmarkTagLinksToReplace, isEmpty);
  });
}
