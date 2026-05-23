# Test fixtures

Sample bookmark export files for Story 5.1 (Browser Bookmark Import).

| File | Provenance | Shape | Used by |
| --- | --- | --- | --- |
| `chrome_bookmarks.html` | Hand-crafted to match Chrome 120's export shape (verified against a real export, then anonymised). Includes `PERSONAL_TOOLBAR_FOLDER`, `ADD_DATE`, and an inline `ICON` data URL to confirm those attributes are ignored. Contains one empty-title `<A>` to exercise the URL-fallback rule. | 5 folders, 15 bookmarks (1 with no title). 3 levels of nesting. | `browser_bookmarks_html_parser_test.dart`, `import_flow_test.dart` |
| `firefox_bookmarks.html` | Hand-crafted to match Firefox 122's export shape. Includes `TAGS`, `LAST_MODIFIED`, and an `ICON_URI` attribute that the parser must ignore. Uses Firefox's `<DD>...</DD>` description elements between `<DT>` and the nested `<DL>`. | 3 folders, 6 bookmarks. | `browser_bookmarks_html_parser_test.dart` |
| `safari_bookmarks.html` | Hand-crafted to match Safari 17's export shape (closest to the original Netscape spec — no `ADD_DATE`, uses `FOLDED` attribute). Includes one root-level bookmark (DuckDuckGo) sitting outside any folder to exercise that branch. | 3 folders (nested 3 deep), 7 bookmarks total; 1 root-level. | `browser_bookmarks_html_parser_test.dart` |
| `malformed_bookmarks.html` | A regular HTML page with no `<DL>` and no `<A>` — represents the "user picked the wrong file" path. | 0 folders, 0 bookmarks, 0 unparseable items. | `browser_bookmarks_html_parser_test.dart`, `import_flow_test.dart` |
| `large_bookmarks.html` | Programmatically generated (5 top-level × 5 nested = 25 leaf folders, each holding 20 bookmarks). Generator lived at `/tmp/gen_large.dart` during dev; the committed file IS the test contract — re-generating would invalidate per-bookmark URL assertions. | 31 folders (1 wrapper + 5 top + 25 sub), 500 bookmarks. | `bookmark_import_service_test.dart`, `import_flow_test.dart` (NFR5 scenario D, coalesce scenario E) |

If a fixture needs to be regenerated, do it intentionally: the goal is a
stable file-as-test-contract, not a derived artefact. Real-browser
fixtures should be re-exported from the corresponding browser version,
anonymised (no personal URLs / cookies leaking through `ICON_URI`), and
diffed against the prior version so downstream test assertions stay
honest.
