import 'dart:async';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/search/data/search_repository.dart';
import 'package:bookmarks/features/tags/data/tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story 3.1: validates SearchRepository's FTS5 MATCH-driven search,
/// query sanitisation, BM25 ordering, and reactive re-emission on
/// underlying-data changes. Operates against a real in-memory v6
/// AppDatabase so the FTS triggers exercise the same code path as in
/// production.
void main() {
  late AppDatabase db;
  late SearchRepository searchRepo;
  late BookmarkRepository bookmarkRepo;
  late TagRepository tagRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    searchRepo = SearchRepository(db);
    bookmarkRepo = BookmarkRepository(db);
    tagRepo = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Bookmark mkBookmark({
    required String id,
    String url = 'https://example.com',
    String title = 'Title',
    String? notes,
    DateTime? createdAt,
  }) {
    final ts = createdAt ?? DateTime.now();
    return Bookmark(
      id: id,
      url: url,
      title: title,
      notes: notes,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  Future<List<Bookmark>> firstResults(String query) {
    return searchRepo.search(query).first;
  }

  test('empty query returns empty list', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Anything'));

    expect(await firstResults(''), isEmpty);
  });

  test('whitespace-only query returns empty list', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Anything'));

    expect(await firstResults('   '), isEmpty);
  });

  test('single-token query returns matching bookmark', () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'Flutter docs',
      url: 'https://flutter.dev',
    ));

    final results = await firstResults('flutter');
    expect(results.map((b) => b.id).toList(), ['bm-1']);
  });

  test('prefix matching: typing "fl" returns bookmarks with "Flutter" or '
      '"Flask"', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Flutter docs'));
    await bookmarkRepo.save(mkBookmark(id: 'bm-2', title: 'Flask routing'));
    await bookmarkRepo.save(mkBookmark(id: 'bm-3', title: 'Python lists'));

    final results = await firstResults('fl');
    final ids = results.map((b) => b.id).toSet();
    expect(ids, containsAll({'bm-1', 'bm-2'}));
    expect(ids, isNot(contains('bm-3')));
  });

  test('multi-token query is implicit AND across tokens', () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'both',
      title: 'Flutter docs',
      url: 'https://flutter.dev',
    ));
    await bookmarkRepo.save(mkBookmark(
      id: 'flutter-only',
      title: 'Flutter widgets',
      url: 'https://example.com',
    ));
    await bookmarkRepo.save(mkBookmark(
      id: 'docs-only',
      title: 'Generic docs',
      url: 'https://example.org',
    ));

    final results = await firstResults('flutter docs');
    expect(results.map((b) => b.id).toList(), ['both']);
  });

  test('tag-only match: bookmark with tag "graphql" but nothing else hits '
      'on a "graphql" search', () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'Random title',
      url: 'https://example.com',
    ));
    final tagResult = await tagRepo.upsertByName('graphql');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);

    final results = await firstResults('graphql');
    expect(results.map((b) => b.id).toList(), ['bm-1']);
  });

  test('notes-only match: bookmark whose only "dynamic" mention is in notes',
      () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'Algorithms paper',
      url: 'https://arxiv.org/abs/x',
      notes: 'Annotated for the dynamic-programming chapter',
    ));

    final results = await firstResults('dynamic');
    expect(results.map((b) => b.id).toList(), ['bm-1']);
  });

  test('URL host match: typing the dotted host returns the bookmark',
      () async {
    // unicode61 splits on `.` so the host "docs.flutter.dev" indexes the
    // tokens "docs", "flutter", "dev". The sanitiser must replace `.`
    // with a space at query time too (FTS5's query parser would otherwise
    // error on the literal dot) so a user typing the full host hits.
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'API reference',
      url: 'https://docs.flutter.dev/widgets',
    ));

    final results = await firstResults('docs.flutter.dev');
    expect(results.map((b) => b.id).toList(), ['bm-1']);
  });

  test('results ordered by BM25 then created_at DESC', () async {
    // Three bookmarks all match "flutter". The one with "flutter" appearing
    // multiple times across columns will rank highest by BM25; ties are
    // broken by created_at DESC.
    final old = DateTime.utc(2020);
    final mid = DateTime.utc(2021);
    final fresh = DateTime.utc(2022);

    await bookmarkRepo.save(mkBookmark(
      id: 'best',
      title: 'Flutter Flutter Flutter',
      notes: 'flutter flutter',
      createdAt: old,
    ));
    await bookmarkRepo.save(mkBookmark(
      id: 'mid-fresh',
      title: 'Flutter docs',
      createdAt: fresh,
    ));
    await bookmarkRepo.save(mkBookmark(
      id: 'mid-old',
      title: 'Flutter docs',
      createdAt: mid,
    ));

    final results = await firstResults('flutter');
    final ids = results.map((b) => b.id).toList();
    expect(ids.first, 'best',
        reason: 'best BM25 score wins regardless of created_at');
    // Among the BM25-tied middle bookmarks, the fresher one comes first.
    final midFreshIdx = ids.indexOf('mid-fresh');
    final midOldIdx = ids.indexOf('mid-old');
    expect(midFreshIdx, lessThan(midOldIdx));
  });

  test('FTS5 special characters are sanitised, not error: searching "c++" '
      'returns "c"-matching bookmarks', () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'C language'));

    // Should not throw a SQLite syntax error; should match the "c" token.
    final results = await firstResults('c++');
    expect(results.map((b) => b.id).toList(), contains('bm-1'));
  });

  test('all-special-characters query returns empty list (no usable tokens)',
      () async {
    await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Anything'));

    expect(await firstResults('"""'), isEmpty);
    expect(await firstResults('()'), isEmpty);
  });

  test(
      'natural-input punctuation never throws: dot / comma / slash / '
      'apostrophe / etc. all get sanitised', () async {
    // Real-world queries the user is likely to type. None of these may
    // surface as a SQLite syntax error -- the sanitiser must keep the
    // search bar a free-text input, not an FTS5 query-language input.
    await bookmarkRepo.save(mkBookmark(
      id: 'flutter',
      title: 'Flutter',
      url: 'https://flutter.dev',
      notes: 'Cross-platform UI toolkit',
    ));

    const queries = <String>[
      'dart.dev', // single dot (URL host)
      'docs.flutter.dev', // multiple dots
      'hello, world', // comma
      'a/b/c', // slashes
      "it's", // apostrophe
      'a?b', // question mark
      'a=b&c=d', // URL-style equals + ampersand
      'hash#anchor', // hash
      '20% off', // percent
      'a;b', // semicolon
      'flutter ', // trailing whitespace (no-op + strip)
      ' flutter', // leading whitespace
    ];

    for (final q in queries) {
      // Any throw here would surface as test failure -- the contract is
      // that no natural input crashes the query.
      final results = await firstResults(q);
      // We don't assert on result content (some are empty by design);
      // the load-bearing assertion is that no exception was thrown.
      expect(results, isA<List<Bookmark>>(),
          reason: 'query "$q" should not throw');
    }
  });

  test('real-time re-emission: stream emits when a new matching bookmark '
      'is inserted', () async {
    final stream = searchRepo.search('flutter');
    final emissions = <List<Bookmark>>[];
    final completer = Completer<void>();
    final sub = stream.listen((event) {
      emissions.add(event);
      if (emissions.length >= 2) completer.complete();
    });
    addTearDown(sub.cancel);

    // First emission is the initial (empty) result for the just-opened DB.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, isNotEmpty);

    await bookmarkRepo.save(mkBookmark(id: 'new-bm', title: 'Flutter docs'));

    await completer.future.timeout(const Duration(seconds: 2));
    final last = emissions.last;
    expect(last.map((b) => b.id).toList(), ['new-bm']);
  });

  test('real-time re-emission: stream emits when a tag is linked to a '
      'previously non-matching bookmark', () async {
    await bookmarkRepo.save(mkBookmark(
      id: 'bm-1',
      title: 'Random',
      url: 'https://example.com',
    ));

    final stream = searchRepo.search('graphql');
    final emissions = <List<Bookmark>>[];
    final completer = Completer<void>();
    final sub = stream.listen((event) {
      emissions.add(event);
      if (event.isNotEmpty) completer.complete();
    });
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final tagResult = await tagRepo.upsertByName('graphql');
    final tag = (tagResult as dynamic).value as Tag;
    await tagRepo.linkBookmarkTag('bm-1', tag.id);

    await completer.future.timeout(const Duration(seconds: 2));
    expect(emissions.last.map((b) => b.id).toList(), ['bm-1']);
  });

  // ===== Story 3.2: folder + tag scoping =====

  group('folder scoping (Story 3.2 AC5)', () {
    late FolderRepository folderRepo;

    setUp(() {
      folderRepo = FolderRepository(db);
    });

    Future<Folder> mkFolder(String id, {String? parentId}) async {
      final now = DateTime.now();
      final f = Folder(
        id: id,
        name: id,
        parentId: parentId,
        createdAt: now,
        updatedAt: now,
      );
      await folderRepo.save(f);
      return f;
    }

    Future<void> mkBookmarkInFolder(
      String id,
      String? folderId,
      String title,
    ) async {
      await bookmarkRepo.save(mkBookmark(
        id: id,
        title: title,
      ).copyWith(folderId: folderId));
    }

    test('single folder, no descendants: only that folder\'s matches return',
        () async {
      await mkFolder('A');
      await mkFolder('B');
      await mkBookmarkInFolder('bm-a', 'A', 'Flutter docs');
      await mkBookmarkInFolder('bm-b', 'B', 'Flutter widgets');

      final results = await searchRepo
          .search('flutter', folderIds: {'A'}).first;
      expect(results.map((b) => b.id).toSet(), {'bm-a'});
    });

    test('parent + descendants: scope set covers nested folders', () async {
      await mkFolder('A');
      await mkFolder('B', parentId: 'A');
      await mkFolder('C', parentId: 'B');
      await mkBookmarkInFolder('bm-a', 'A', 'Flutter at A');
      await mkBookmarkInFolder('bm-b', 'B', 'Flutter at B');
      await mkBookmarkInFolder('bm-c', 'C', 'Flutter at C');
      await mkBookmarkInFolder('bm-d', null, 'Flutter at root');

      final results = await searchRepo
          .search('flutter', folderIds: {'A', 'B', 'C'}).first;
      expect(results.map((b) => b.id).toSet(),
          {'bm-a', 'bm-b', 'bm-c'});
    });

    test('empty folderIds set behaves like the unscoped baseline', () async {
      await mkFolder('A');
      await mkFolder('B');
      await mkBookmarkInFolder('bm-a', 'A', 'Flutter docs');
      await mkBookmarkInFolder('bm-b', 'B', 'Flutter widgets');

      final results =
          await searchRepo.search('flutter', folderIds: <String>{}).first;
      final unscoped = await searchRepo.search('flutter').first;
      expect(results.map((b) => b.id).toSet(),
          unscoped.map((b) => b.id).toSet());
    });

    test('null folderIds is the same as unscoped', () async {
      await mkFolder('A');
      await mkBookmarkInFolder('bm-a', 'A', 'Flutter docs');

      final results = await searchRepo.search('flutter', folderIds: null).first;
      expect(results.map((b) => b.id).toSet(), {'bm-a'});
    });

    test('BM25 ordering preserved within scope', () async {
      await mkFolder('A');
      // Bookmark whose title is exactly the term — high BM25 relevance.
      await mkBookmarkInFolder('bm-exact', 'A', 'Flutter');
      // Bookmark whose only mention is via notes (lower relevance).
      final now = DateTime.now();
      await bookmarkRepo.save(Bookmark(
        id: 'bm-notes',
        url: 'https://example.com',
        title: 'Notes',
        folderId: 'A',
        notes: 'Some flutter content here',
        createdAt: now.subtract(const Duration(seconds: 1)),
        updatedAt: now.subtract(const Duration(seconds: 1)),
      ));

      final results = await searchRepo
          .search('flutter', folderIds: {'A'}).first;
      expect(results.first.id, 'bm-exact');
    });

    test('real-time re-emission under scope: inserting a matching bookmark '
        'in the scoped folder updates the stream; inserting outside it '
        'does not surface in the scoped result set', () async {
      await mkFolder('A');
      await mkFolder('B');

      final stream = searchRepo.search('flutter', folderIds: {'A'});
      final emissions = <List<Bookmark>>[];
      final sawMatch = Completer<void>();
      final sub = stream.listen((event) {
        emissions.add(event);
        if (event.any((b) => b.id == 'bm-in-scope')) {
          if (!sawMatch.isCompleted) sawMatch.complete();
        }
      });
      addTearDown(sub.cancel);

      // First emission: empty (no bookmarks yet).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions, isNotEmpty);

      // In-scope insert -> stream re-emits with the new bookmark.
      await mkBookmarkInFolder('bm-in-scope', 'A', 'Flutter docs');
      await sawMatch.future.timeout(const Duration(seconds: 2));
      expect(emissions.last.map((b) => b.id).toList(), ['bm-in-scope']);

      // Out-of-scope insert -> bookmark_tags/bookmarks readsFrom set still
      // fires invalidation (the stream re-runs), but the WHERE clause
      // filters the row out, so it must NOT appear in the scoped results.
      final beforeOutOfScope = emissions.length;
      await mkBookmarkInFolder('bm-out-of-scope', 'B', 'Flutter widgets');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Either no re-emission happened, or any that did still contains only
      // the in-scope bookmark. Both shapes satisfy the scoped contract.
      if (emissions.length > beforeOutOfScope) {
        expect(emissions.last.map((b) => b.id).toSet(), {'bm-in-scope'},
            reason: 'out-of-scope insert must not leak into the scoped set');
      }
    });
  });

  group('tag scoping (Story 3.2 AC6)', () {
    test('single tag: only bookmarks linked to that tag match', () async {
      await bookmarkRepo.save(mkBookmark(id: 'bm-x1', title: 'Flutter X1'));
      await bookmarkRepo.save(mkBookmark(id: 'bm-x2', title: 'Flutter X2'));
      await bookmarkRepo.save(mkBookmark(id: 'bm-y1', title: 'Flutter Y1'));

      final tagXResult = await tagRepo.upsertByName('x');
      final tagX = (tagXResult as dynamic).value as Tag;
      final tagYResult = await tagRepo.upsertByName('y');
      final tagY = (tagYResult as dynamic).value as Tag;
      await tagRepo.linkBookmarkTag('bm-x1', tagX.id);
      await tagRepo.linkBookmarkTag('bm-x2', tagX.id);
      await tagRepo.linkBookmarkTag('bm-y1', tagY.id);

      final results =
          await searchRepo.search('flutter', tagId: tagX.id).first;
      expect(results.map((b) => b.id).toSet(), {'bm-x1', 'bm-x2'});
    });

    test('bookmark with multiple tags is returned exactly once', () async {
      await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Flutter docs'));

      final tagAResult = await tagRepo.upsertByName('a');
      final tagA = (tagAResult as dynamic).value as Tag;
      final tagBResult = await tagRepo.upsertByName('b');
      final tagB = (tagBResult as dynamic).value as Tag;
      await tagRepo.linkBookmarkTag('bm-1', tagA.id);
      await tagRepo.linkBookmarkTag('bm-1', tagB.id);

      final results =
          await searchRepo.search('flutter', tagId: tagA.id).first;
      expect(results.map((b) => b.id).toList(), ['bm-1'],
          reason: 'EXISTS subquery (not JOIN) avoids duplicate rows');
    });

    test('null tagId is the same as unscoped', () async {
      await bookmarkRepo.save(mkBookmark(id: 'bm-1', title: 'Flutter docs'));
      final results = await searchRepo.search('flutter', tagId: null).first;
      expect(results.map((b) => b.id).toList(), ['bm-1']);
    });
  });

  group('combined scoping defensive behaviour', () {
    test('both folderIds and tagId are AND-combined (defensive)', () async {
      // searchScopeProvider never produces this state, but the SQL must be
      // sane if it ever happens.
      final folderRepo = FolderRepository(db);
      final now = DateTime.now();
      await folderRepo.save(Folder(
        id: 'A',
        name: 'A',
        createdAt: now,
        updatedAt: now,
      ));
      await bookmarkRepo.save(
          mkBookmark(id: 'bm-a-tagged', title: 'Flutter')
              .copyWith(folderId: 'A'));
      await bookmarkRepo.save(
          mkBookmark(id: 'bm-a-untagged', title: 'Flutter')
              .copyWith(folderId: 'A'));
      await bookmarkRepo.save(
          mkBookmark(id: 'bm-other-tagged', title: 'Flutter'));

      final tagResult = await tagRepo.upsertByName('hot');
      final tag = (tagResult as dynamic).value as Tag;
      await tagRepo.linkBookmarkTag('bm-a-tagged', tag.id);
      await tagRepo.linkBookmarkTag('bm-other-tagged', tag.id);

      final results = await searchRepo
          .search('flutter', folderIds: {'A'}, tagId: tag.id)
          .first;
      expect(results.map((b) => b.id).toSet(), {'bm-a-tagged'});
    });
  });
}
