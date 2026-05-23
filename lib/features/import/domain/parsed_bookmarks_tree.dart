import 'package:freezed_annotation/freezed_annotation.dart';

part 'parsed_bookmarks_tree.freezed.dart';

/// A single bookmark extracted from a browser-exported HTML file. The
/// parser populates [title] from the `<A>` element's inner text; when
/// that text is empty / whitespace the parser substitutes [url] so the
/// downstream writer never persists an empty-title bookmark. Mirrors the
/// URL-fallback rule introduced by Story 1.2's add-bookmark flow.
@freezed
abstract class ParsedBookmark with _$ParsedBookmark {
  const factory ParsedBookmark({
    required String url,
    required String title,
  }) = _ParsedBookmark;
}

/// A folder node from the parsed Netscape `<DL>` hierarchy. Folders may
/// nest arbitrarily deep ([subfolders]) and may contain bookmarks
/// directly ([bookmarks]). Empty folders are preserved verbatim — the
/// import writer creates them so the user's hierarchy is mirrored 1:1.
@freezed
abstract class ParsedFolderNode with _$ParsedFolderNode {
  const factory ParsedFolderNode({
    required String name,
    required List<ParsedFolderNode> subfolders,
    required List<ParsedBookmark> bookmarks,
  }) = _ParsedFolderNode;
}

/// The parser's whole-file output. [rootFolders] holds the top-level
/// folders (typically a single "Bookmarks Bar" wrapper, but Firefox /
/// Safari shapes vary). [rootBookmarks] holds bookmarks that sit outside
/// any folder — rare but legal in the Netscape format. [unparseableItems]
/// counts `<DT>` blocks that contained neither an `<A>` nor an `<H3>`;
/// the writer surfaces this number to the user as "items skipped".
@freezed
abstract class ParsedBookmarksTree with _$ParsedBookmarksTree {
  const factory ParsedBookmarksTree({
    required List<ParsedFolderNode> rootFolders,
    required List<ParsedBookmark> rootBookmarks,
    required int unparseableItems,
  }) = _ParsedBookmarksTree;
}
