import 'dart:io';

import 'package:bookmarks/features/import/data/browser_bookmarks_html_parser.dart';
import 'package:bookmarks/features/import/domain/parsed_bookmarks_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = BrowserBookmarksHtmlParser();

  String loadFixture(String name) =>
      File('test/fixtures/$name').readAsStringSync();

  int bookmarkCount(ParsedBookmarksTree tree) {
    var count = tree.rootBookmarks.length;
    void walk(List<ParsedFolderNode> folders) {
      for (final f in folders) {
        count += f.bookmarks.length;
        walk(f.subfolders);
      }
    }
    walk(tree.rootFolders);
    return count;
  }

  int folderCount(ParsedBookmarksTree tree) {
    var count = 0;
    void walk(List<ParsedFolderNode> folders) {
      for (final f in folders) {
        count++;
        walk(f.subfolders);
      }
    }
    walk(tree.rootFolders);
    return count;
  }

  group('BrowserBookmarksHtmlParser', () {
    test('parses a Chrome export with nested folders and ICON/ADD_DATE '
        'attributes ignored', () {
      final tree = parser.parse(loadFixture('chrome_bookmarks.html'));
      expect(folderCount(tree), 5,
          reason: 'Bookmarks bar + Dev + Languages + News + Other bookmarks');
      expect(bookmarkCount(tree), 15,
          reason: 'all <A HREF> entries are captured');
      expect(tree.rootFolders.map((f) => f.name),
          containsAll(<String>['Bookmarks bar', 'Other bookmarks']));
      // Locate the GitHub bookmark to verify ICON= data URI did not leak
      // into the parsed title.
      final bar =
          tree.rootFolders.firstWhere((f) => f.name == 'Bookmarks bar');
      final dev = bar.subfolders.firstWhere((f) => f.name == 'Dev');
      final github =
          dev.bookmarks.firstWhere((b) => b.url == 'https://github.com');
      expect(github.title, 'GitHub');
    });

    test('parses a Firefox export and ignores TAGS / ICON_URI / DD '
        'description nodes', () {
      final tree = parser.parse(loadFixture('firefox_bookmarks.html'));
      expect(folderCount(tree), 3);
      expect(bookmarkCount(tree), 6);
      // The tagged Mozilla bookmark must come through with title only —
      // the TAGS="browser,foss" attribute is ignored, not folded into
      // the title or the URL.
      final mozilla = tree.rootFolders
          .expand((f) => f.bookmarks)
          .firstWhere((b) => b.url == 'https://mozilla.org');
      expect(mozilla.title, 'Mozilla',
          reason: 'TAGS attribute must not influence parsed title');
    });

    test('parses a Safari export with deep nesting and root-level '
        'bookmarks outside any folder', () {
      final tree = parser.parse(loadFixture('safari_bookmarks.html'));
      expect(folderCount(tree), 3, reason: 'Favorites + Daily + Sports');
      expect(bookmarkCount(tree), 7);
      expect(tree.rootBookmarks.length, 1,
          reason: 'DuckDuckGo sits outside any folder');
      expect(tree.rootBookmarks.single.url, 'https://duckduckgo.com/');

      // Verify 3-deep nesting survives intact.
      final favorites = tree.rootFolders.single;
      expect(favorites.name, 'Favorites');
      final daily = favorites.subfolders.single;
      expect(daily.name, 'Daily');
      final sports = daily.subfolders.single;
      expect(sports.name, 'Sports');
      expect(sports.bookmarks.length, 2);
    });

    test('returns empty tree for a non-bookmark HTML file (no <DL> root)', () {
      final tree = parser.parse(loadFixture('malformed_bookmarks.html'));
      expect(tree.rootFolders, isEmpty);
      expect(tree.rootBookmarks, isEmpty);
      expect(tree.unparseableItems, 0,
          reason: 'no <DT> blocks attempted → no unparseable items');
    });

    test('returns empty tree for completely empty input', () {
      final tree = parser.parse('');
      expect(tree.rootFolders, isEmpty);
      expect(tree.rootBookmarks, isEmpty);
      expect(tree.unparseableItems, 0);
    });

    test('substitutes URL when an <A> has empty inner text '
        '(URL-as-title fallback from Story 1.2)', () {
      final tree = parser.parse(loadFixture('chrome_bookmarks.html'));
      final allBookmarks = <ParsedBookmark>[];
      void walk(List<ParsedFolderNode> folders) {
        for (final f in folders) {
          allBookmarks.addAll(f.bookmarks);
          walk(f.subfolders);
        }
      }
      walk(tree.rootFolders);
      allBookmarks.addAll(tree.rootBookmarks);
      final fallback = allBookmarks
          .firstWhere((b) => b.url == 'https://example.org/no-title');
      expect(fallback.title, fallback.url,
          reason: 'empty inner text → URL used as title');
    });

    test('preserves folder hierarchy verbatim — no flattening, '
        'no smart-grouping', () {
      final tree = parser.parse(loadFixture('chrome_bookmarks.html'));
      final bar =
          tree.rootFolders.firstWhere((f) => f.name == 'Bookmarks bar');
      // Bookmarks bar holds two subfolders (Dev, News) and two direct
      // bookmarks (Example, Flutter) — Dev's content DL closes before
      // News in the fixture, so they're siblings of Dev rather than
      // children.
      expect(bar.subfolders.map((f) => f.name),
          containsAll(<String>['Dev', 'News']));
      expect(bar.bookmarks.map((b) => b.url),
          containsAll(<String>['https://example.com', 'https://flutter.dev']));
      // Dev itself contains exactly one subfolder (Languages) and three
      // direct bookmarks.
      final dev = bar.subfolders.firstWhere((f) => f.name == 'Dev');
      expect(dev.subfolders.single.name, 'Languages');
      expect(dev.bookmarks.length, 3);
      // Languages contains three language sites.
      expect(dev.subfolders.single.bookmarks.length, 3);
    });

    test('handles empty folders (folder-only nodes with no bookmarks inside)',
        () {
      const empty = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
  <DT><H3>Empty</H3>
  <DL><p></DL><p>
</DL>
''';
      final tree = parser.parse(empty);
      expect(tree.rootFolders.length, 1);
      expect(tree.rootFolders.single.name, 'Empty');
      expect(tree.rootFolders.single.subfolders, isEmpty);
      expect(tree.rootFolders.single.bookmarks, isEmpty);
    });

    test('increments unparseableItems for <DT> blocks that contain '
        'neither <A> nor <H3>', () {
      const garbage = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
  <DT>just some text we cannot parse
  <DT><span>also garbage</span>
  <DT><A HREF="https://valid.example">Valid</A>
</DL>
''';
      final tree = parser.parse(garbage);
      expect(tree.unparseableItems, 2);
      expect(bookmarkCount(tree), 1);
    });

    test('skips bookmarks with empty href and counts them as unparseable',
        () {
      const noHref = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
  <DT><A HREF="">Empty href</A>
  <DT><A HREF="https://ok.example">OK</A>
</DL>
''';
      final tree = parser.parse(noHref);
      expect(bookmarkCount(tree), 1);
      expect(tree.unparseableItems, 1);
    });

    test('parses the 500-bookmark large fixture without error', () {
      final tree = parser.parse(loadFixture('large_bookmarks.html'));
      expect(bookmarkCount(tree), 500);
      // 1 wrapper "Generated" + 5 top-level + 25 sub = 31 folders.
      expect(folderCount(tree), 31);
    });
  });
}
