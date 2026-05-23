import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/parsed_bookmarks_tree.dart';

/// Pure-Dart parser for the Netscape bookmark file format produced by
/// Chrome / Firefox / Safari exports.
///
/// **Format.** A nested `<DL>` list whose direct children are `<DT>`
/// elements. Each `<DT>` contains either:
/// - an `<A HREF="...">title</A>` (bookmark), or
/// - an `<H3>folder name</H3>` followed by a nested `<DL>...</DL>`
///   (folder; the `<DL>` may itself be a sibling of the `<H3>` inside
///   the same `<DT>` parent depending on the exporter).
///
/// **Tolerance.** Real-world exports vary: Safari and Chrome put the
/// nested `<DL>` as a sibling of the `<H3>` inside the parent `<DT>`;
/// Firefox sometimes lifts the `<DL>` to be a direct child of the
/// outer `<DT>`'s parent. The walker handles both by treating every
/// `<DT>` independently and looking for an immediately-following `<DL>`
/// sibling regardless of nesting depth. Stray whitespace, comments,
/// and `<P>` separators (Firefox uses these) are ignored.
///
/// **Ignored attributes (deliberate, Story 5.1 scope).** `ADD_DATE`,
/// `LAST_VISIT`, `LAST_MODIFIED`, `ICON`, `ICON_URI`, `TAGS` — all
/// preserved by browsers but irrelevant to 5.1. `TAGS` and `ICON`
/// extraction is documented in `docs/import-model.md` as deferred work.
///
/// **Failure mode.** The parser never throws. Pathological input
/// returns `ParsedBookmarksTree(rootFolders: [], rootBookmarks: [],
/// unparseableItems: …)`; the caller decides whether that constitutes
/// "invalid file" based on the empty-counts heuristic.
class BrowserBookmarksHtmlParser {
  const BrowserBookmarksHtmlParser();

  ParsedBookmarksTree parse(String htmlContent) {
    final Document document;
    try {
      document = html_parser.parse(htmlContent);
    } catch (_) {
      // package:html's tolerant parser doesn't typically throw, but be
      // defensive — totally non-HTML bytes still produce an empty tree.
      return const ParsedBookmarksTree(
        rootFolders: <ParsedFolderNode>[],
        rootBookmarks: <ParsedBookmark>[],
        unparseableItems: 0,
      );
    }

    // Root: the FIRST <DL> in the document. Browsers wrap their entire
    // bookmark tree in a single top-level <DL>, often preceded by a
    // <H1> "Bookmarks" / Firefox's <META> header. Anything before the
    // first <DL> is ignored.
    final rootDl = document.querySelector('dl');
    if (rootDl == null) {
      return const ParsedBookmarksTree(
        rootFolders: <ParsedFolderNode>[],
        rootBookmarks: <ParsedBookmark>[],
        unparseableItems: 0,
      );
    }

    final unparseable = _UnparseableCounter();
    final (folders, bookmarks) = _parseDl(rootDl, unparseable);
    return ParsedBookmarksTree(
      rootFolders: folders,
      rootBookmarks: bookmarks,
      unparseableItems: unparseable.value,
    );
  }

  /// Parses a `<DL>` element into (folders, bookmarks). The walker
  /// scans direct `<DT>` children in document order; each `<DT>` is
  /// either a bookmark, a folder header, or unparseable.
  (List<ParsedFolderNode>, List<ParsedBookmark>) _parseDl(
    Element dl,
    _UnparseableCounter unparseable,
  ) {
    final folders = <ParsedFolderNode>[];
    final bookmarks = <ParsedBookmark>[];

    for (final dt in dl.children.where((c) => c.localName == 'dt')) {
      final anchor = _firstChild(dt, 'a');
      final header = _firstChild(dt, 'h3');

      if (header != null) {
        // Folder. The nested <DL> location varies by browser export
        // shape AND by html5 parser quirks:
        //   * Chrome / Safari: <DL> is a direct child of <DT>.
        //   * Firefox + html5: when a `<DD>` description follows the
        //     `<H3>`, the html5 parser folds the subsequent `<DL>`
        //     into the `<DD>` — so the content DL is at
        //     dt → next sibling DD → first child DL.
        //   * Some hand-rolled exports: `<DL>` is a plain sibling of
        //     the `<DT>`.
        final nested = _findFolderContentDl(dt);
        final List<ParsedFolderNode> subfolders;
        final List<ParsedBookmark> bms;
        if (nested != null) {
          final (subs, bs) = _parseDl(nested, unparseable);
          subfolders = subs;
          bms = bs;
        } else {
          subfolders = const <ParsedFolderNode>[];
          bms = const <ParsedBookmark>[];
        }
        folders.add(ParsedFolderNode(
          name: header.text.trim(),
          subfolders: subfolders,
          bookmarks: bms,
        ));
      } else if (anchor != null) {
        final href = anchor.attributes['href']?.trim() ?? '';
        if (href.isEmpty) {
          unparseable.value++;
          continue;
        }
        final innerText = anchor.text.trim();
        bookmarks.add(ParsedBookmark(
          url: href,
          title: innerText.isEmpty ? href : innerText,
        ));
      } else {
        // Empty <DT> with no <A> and no <H3>. Real exports occasionally
        // produce these when the user deleted a bookmark mid-edit; count
        // and continue.
        if (dt.text.trim().isNotEmpty) {
          unparseable.value++;
        }
      }
    }

    return (folders, bookmarks);
  }

  Element? _firstChild(Element parent, String localName) {
    for (final c in parent.children) {
      if (c.localName == localName) return c;
    }
    return null;
  }

  /// Locates the `<DL>` holding [folderDt]'s contents. Tries, in order:
  ///   1. A direct child of `<DT>` (Chrome / Safari).
  ///   2. A following sibling `<DL>` (rare hand-rolled exports).
  ///   3. A `<DL>` nested inside a following sibling `<DD>` (Firefox
  ///      shape after html5 parser normalisation).
  /// Stops scanning at the next `<DT>` — that DT owns its own contents
  /// and the current folder has finished its run.
  Element? _findFolderContentDl(Element folderDt) {
    final direct = _firstChild(folderDt, 'dl');
    if (direct != null) return direct;
    final parent = folderDt.parent;
    if (parent == null) return null;
    final siblings = parent.children;
    final ix = siblings.indexOf(folderDt);
    if (ix < 0) return null;
    for (var i = ix + 1; i < siblings.length; i++) {
      final s = siblings[i];
      if (s.localName == 'dt') return null;
      if (s.localName == 'dl') return s;
      if (s.localName == 'dd') {
        final inner = _firstChild(s, 'dl');
        if (inner != null) return inner;
      }
    }
    return null;
  }
}

/// Mutable counter passed through the recursive walk so deeply-nested
/// unparseable `<DT>` blocks contribute to the file-wide total without
/// the walker having to return-and-thread an int through every frame.
class _UnparseableCounter {
  int value = 0;
}
