import 'dart:async';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
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
}
