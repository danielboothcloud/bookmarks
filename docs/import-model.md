# Import model — Story 5.1

This document is the contract for Epic 5 / Story 5.1 (Browser Bookmark
Import). Sibling to `docs/sync-model.md`, `docs/auth-model.md`, and
`docs/focus-model.md`. Schema impact is explicitly **none** — the
import path writes through the existing `bookmarks` / `folders`
repositories at schema v7.

## 1. The Netscape bookmark format

Browsers export their bookmarks as a single self-contained HTML file
loosely called the "Netscape bookmark file format" (the original spec
was Netscape Navigator's; Chrome / Firefox / Safari all emit
compatible-ish variants).

Structural cues:

| Element | Role |
| --- | --- |
| `<DL>` | Wraps a list of bookmark entries. The whole tree starts with one root `<DL>`. |
| `<DT>` | Wraps a single entry. May contain a bookmark `<A>` OR a folder header `<H3>` followed by a nested `<DL>`. |
| `<H3>` | Folder name. The text content is the folder label. |
| `<A HREF="…">` | A bookmark. The `HREF` is the URL; the inner text is the title. |
| `<P>` | Cosmetic separator some exporters insert; ignored. |
| `<DD>` | A folder description (Firefox uses it). The html5 parser folds the *content* `<DL>` inside the `<DD>` — the parser handles that quirk. |

Per-browser quirks observed during 5.1 development:

* **Chrome**: vanilla Netscape shape. Adds `PERSONAL_TOOLBAR_FOLDER=true` on the Bookmarks-bar `<H3>`; inserts inline `ICON="data:image/png;base64,…"` for some entries.
* **Firefox**: includes `TAGS="foo,bar"` on tagged bookmarks; adds `<DD>` description nodes which the html5 parser absorbs the subsequent `<DL>` into.
* **Safari**: closest to the original spec; uses `FOLDED` on collapsed folders; omits `ADD_DATE`.

**Attributes deliberately ignored in 5.1**: `ADD_DATE`, `LAST_VISIT`,
`LAST_MODIFIED`, `ICON`, `ICON_URI`, `TAGS`. Rationale:

* `ADD_DATE` / `LAST_VISIT` / `LAST_MODIFIED` — imported bookmarks all share `createdAt = updatedAt = import-moment` so they cluster together in the chronological list. Preserving original dates would scatter them silently to the bottom.
* `ICON` / `ICON_URI` — inline base64 favicons are often stale (cached by the browser years ago). Story 5.2's live fetch will always trump the inline value.
* `TAGS` — tags are first-class in Drift but conflating attribute extraction with structure parsing is out of scope; deferred to post-Epic 5 backlog.

## 2. Parser contract

`lib/features/import/data/browser_bookmarks_html_parser.dart`:

```dart
class BrowserBookmarksHtmlParser {
  ParsedBookmarksTree parse(String htmlContent);
}
```

* **Pure.** Input is `String` HTML; output is the in-memory tree
  (`lib/features/import/domain/parsed_bookmarks_tree.dart`). No Flutter
  imports, no Drift, no Riverpod, no I/O.
* **`noexcept`-by-design.** Pathological inputs (non-HTML bytes,
  missing `<DL>` root, garbage with no `<A>` or `<H3>`) return an
  empty `ParsedBookmarksTree` rather than throwing. The downstream
  `ImportNotifier` decides "invalid file" via the empty-counts
  heuristic (`rootBookmarks.isEmpty && every-folder-empty`).
* **URL-as-title fallback.** When `<A>`'s inner text is empty /
  whitespace, the parser substitutes the URL — consistent with the
  Story 1.2 add-bookmark rule.
* **`unparseableItems` counter.** Increments for each `<DT>` block
  that contained neither `<A>` nor `<H3>` (or contained an empty-href
  `<A>`). Surfaced to the user as the "X items skipped" sub-clause of
  the success summary.
* **Folder-DL discovery quirk.** A folder's content `<DL>` is found by
  checking, in order: a direct child of the `<DT>` (Chrome / Safari),
  a following sibling `<DL>` (rare hand-rolled exports), or a `<DL>`
  nested inside a following sibling `<DD>` (Firefox after html5
  normalisation).

## 3. Writer contract

`lib/features/import/data/bookmark_import_service.dart`:

```dart
class BookmarkImportService {
  Future<Result<ImportResult, AppError>> importTree(
    ParsedBookmarksTree tree, {
    void Function(ImportProgress)? onProgress,
  });
}
```

* **Repository-only writes.** Every mutation goes through
  `IBookmarkRepository.save` and `IFolderRepository.save`. **This is
  the load-bearing invariant for Epic 5.** Direct Drift inserts would
  bypass:
  * the 11 outbox triggers in
    `lib/core/database/drift_files/sync_triggers.drift` (would silently
    drop sync rows; imported bookmarks would never make it to Drive);
  * the 5 FTS triggers in
    `lib/core/database/drift_files/bookmarks_fts.drift` (imported
    bookmarks would be invisible to search until the next index
    rebuild).
  See `architecture.md` § "Application-Layer Integrity" (Epic 2 A1,
  reaffirmed Epic 4 retro §0; 5.1 is the third epic where the
  invariant is load-bearing).
* **Parent-before-child.** Each folder is `save`d before its bookmarks
  and subfolders so `parentId` and `folderId` references always
  resolve at write time. Depth-first walk.
* **UUID v4 + timestamps.** Every entity is assigned `id = Uuid().v4()`
  (architecture mandate) and `createdAt = updatedAt = DateTime.now()`
  at write time.
* **Chunked yields (every 50 writes).** `_batchSize = 50` — after
  every 50 `save` calls the writer `await Future<void>.delayed(Duration.zero)`s,
  which lets the frame scheduler paint the progress indicator and
  keeps the Settings `ListView` scrollable during a 500-bookmark
  import. Tune up if dev profiling shows yields dominate; tune down
  if 500-fixture imports produce visible jank. See § 5 NFR5 strategy.
* **Progress callback.** Fires per batch with `ImportProgress(itemsWritten, totalItems)`.
  `itemsWritten` is monotonically increasing; `totalItems` is fixed
  at the start of the import.
* **Partial-write semantics.** A storage failure mid-import returns
  `Err(StorageError(...))` immediately. Whatever folders + bookmarks
  made it through still persist. There is **no rollback**. Wrapping
  the entire 500-write run in a single Drift transaction would block
  Drive sync for the full import duration and triples peak memory in
  the engine; that's a poor tradeoff for a one-time onboarding ramp.
  The user-visible message is the calm "Couldn't save imported
  bookmarks. Try again?" and the next attempt picks up fresh.

## 4. Import-then-sync interaction

5.1 does NOT touch the sync stack. Each imported folder / bookmark
triggers its existing outbox-trigger insert
(`sync_triggers.drift`, lines 137 + similar — see `architecture.md`
§ "Sync Architecture"), which adds a row to `sync_queue`. The
`autoPushOrchestratorProvider`'s 250 ms queue-debounce coalesces all
500+ resulting queue rows into a single push cycle. The whole-snapshot
sync model means a 500-bookmark import is one HTTP POST to Drive, not
500.

Per Story 4.5 Surprise #5, the orchestrator may spawn a follow-up
cycle if a stray queue write lands during the first cycle's tail —
both terminate at `SyncSynced`. Integration test scenario E asserts
`uploads.length <= 2` to absorb that case.

## 5. NFR5 strategy — chunked main-thread writes

> "Browser HTML import of 500+ bookmarks completes without the app
> becoming unresponsive."

**Isolates rejected.** Per Epic 4 retro §8, Dart isolates can't access
Drift on macOS: `package:flutter_isolate` doesn't share the SQLite
handle across isolates, and bridging back to the main isolate for each
write defeats the parallelism. The chosen strategy is:

1. Parse the entire HTML on the main thread up front. 500 bookmarks
   ≈ a few hundred ms, acceptable as a single hiccup once the progress
   card is visible.
2. Write in chunks of 50; yield to the frame scheduler between chunks
   via `await Future<void>.delayed(Duration.zero)`.
3. Emit `ImportProgress(itemsWritten, totalItems)` after each yield so
   the `LinearProgressIndicator` repaints and the user sees the count
   climb.

Verified by integration test scenario D
(`test/integration/import_flow_test.dart`): the 500-bookmark fixture
imports in well under 5 s and fires ≥ 5 progress emits during the run.

## 6. Shipped in 5.2: background favicon backfill

Story 5.1 deliberately landed every imported bookmark with
`faviconBase64 = null`, deferring favicon discovery so the import
write phase stayed bounded. Story 5.2 closes that gap with a
background backfill that runs immediately after `ImportSucceeded`.

### Trigger

`ImportNotifier.pickAndImport` fires the backfill fire-and-forget
right after transitioning to `ImportSucceeded`:

```dart
case Ok(:final value):
  state = AsyncData(ImportSucceeded(value));
  unawaited(
    ref
        .read(importFaviconBackfillServiceProvider)
        .backfill(value.importedBookmarkIds),
  );
```

The `unawaited` is load-bearing — the Settings summary card renders
immediately; the user doesn't watch a spinner while 500 favicons
trickle in over the next ~30 seconds. The notifier also calls
`backfillService.cancel()` at the top of `pickAndImport` so a second
import cancels any in-flight prior backfill (AC7).

### Worker pool

`ImportFaviconBackfillService.backfill(List<String>)` spawns a fixed
pool of 6 worker futures sharing a single `Queue<String>` of bookmark
IDs. Each worker pulls the next ID, calls
`MetadataFetchService.fetch(url)` (the same single-URL discovery
primitive Story 1.3 uses, overhauled in commit `6788ed2`), and on a
non-null favicon writes `bookmark.copyWith(faviconBase64: …,
updatedAt: now)` through `BookmarkRepository.save`.

`_maxConcurrent = 6` sits at the midpoint of the 4–8 band the Epic 4
retro §3 prescribed — enough to keep the network busy without
saturating per-host rate limits across the long tail (Cloudflare /
WAF). No exponential backoff and no per-host throttling layer; the
single global cap is the only flow-control mechanism.

### Idempotency

Before fetching, the worker re-reads the current bookmark via
`bookmarkRepo.getById(id)`. If `faviconBase64 != null`, the worker
skips — no fetch, no save. This protects against:

* re-running the backfill against the same IDs;
* a future story populating favicons during parse (`<ICON>` attribute
  extraction);
* the user manually setting a favicon between import and backfill.

### Cancellation

Each `backfill(...)` call mints a fresh `_currentRun` cancellation
token. Workers check `identical(_currentRun, myToken)` before every
`await` and before every `save`. `cancel()` invalidates the token by
setting it to `null`; the next `backfill` call mints a new token.
In-flight HTTP requests are allowed to complete (we don't surgically
abort `http.Client.send`) but their results are discarded — workers
return as soon as they see the token mismatch after the await.

### Title upgrade — only when title equals URL

`MetadataFetchService.fetch` returns both a title and a favicon. The
imported title is usually the user's chosen browser title, which is
**more authoritative** than the live page `<title>` (which may have
changed since the user bookmarked it). The backfill therefore
preserves the imported title by default. The one exception is the
URL-fallback case from Story 5.1 AC6: when the imported title equals
the URL (because the HTML entry had empty inner text like
`<A HREF="…"></A>`), the fetched title is applied. Mirrors Story
1.3's `_fetchMetadata` heuristic verbatim.

### Failure semantics

`MetadataFetchService.fetch` is failure-as-data: every failure path
(404, timeout, parse error, malformed URI, non-image content,
oversized body) yields `UrlMetadata(title: null, faviconBase64:
null)`. On null favicon, the worker makes **no** `save` call —
placeholder remains. `BookmarkRepository.save` errors are
`kDebugMode`-logged and the worker continues to the next ID. No user
surface (no toast, no banner, no error message) — silent per AC4 and
the calm-utility feedback philosophy.

### No retry on relaunch

Backfill state is in-memory. If the app closes mid-backfill, pending
IDs are dropped and never re-queued (AC5 explicit). Users with
remaining placeholders can re-import the same file, manually edit a
bookmark to refresh its metadata (Story 1.4 + 1.3 path), or wait for
a future "Retry missing favicons" maintenance action (out of scope
for 5.2).

### Sync interaction

Every successful `BookmarkRepository.save` during the backfill enqueues
a row in `sync_queue` (the existing outbox triggers from §4 fire on
favicon writes too). The auto-push orchestrator's 250 ms
queue-debounce coalesces multiple favicon writes into one push cycle
when they cluster; over a 30-second backfill of 500 favicons, expect
**multiple push cycles** — not one. Each push uploads the latest
full snapshot (`bookmarks.json` POST). Total upload volume:
`500 × ≤ 64KB = ≤ 32MB` over the backfill lifetime, distributed
across N push cycles where N is timing-dependent. The integration
test asserts eventual convergence to `SyncSynced`, not a specific
cycle count (timing-dependent assertions are flaky — Story 4.5
Surprise #5 precedent).

### UX silence — the load-bearing decision

The backfill is deliberately invisible. The Settings card stays on
`ImportSucceeded` (the static summary text). No second progress
bar. The library views show placeholder globes until each favicon
lands; as the Drift stream emits, the `FaviconWidget` rebuilds and
the icon swaps in without animation — one at a time, quietly, like
a slow photo upload.

The `metadataFetchInFlightProvider` from Story 1.3 (which drives the
per-bookmark `CircularProgressIndicator` in `FaviconWidget`) is
**NOT** populated during backfill fetches. Lighting up 500 spinners
across the library would scream "the app is working hard" when the
calm-utility intent is the opposite. Backfilled favicons appear
without ceremony.

## 7. Deferred to post-5.2 (and beyond)

* **`<ICON>` attribute extraction.** Tempting "fast path" before live
  fetch, but the inline base64 favicons are often stale and the 5.2
  live fetch always trumps. The backfill's idempotency guard handles
  inline-favicon bookmarks gracefully if this lands later.
* **`TAGS` attribute extraction.** Post-Epic 5 backlog.
* **`ADD_DATE` / `LAST_VISIT` / `LAST_MODIFIED` preservation.** Out of
  scope; collapsing all imports to "now" is a better UX (the user
  knows they imported; clustering matches that mental model).
* **Duplicate detection.** Out of scope; URL-equality dedup is harder
  than it looks (`http`/`https`, `www.`, trailing slash, tracking
  query params).
* **Import undo.** Out of scope; whole-snapshot sync makes undo
  expensive infrastructure for a one-time onboarding ramp.
* **Non-Netscape formats.** JSON, Pocket, Pinboard, Raindrop — out of
  scope; users convert to `.html` first.
* **Persistent retry / "Retry missing favicons" maintenance action.**
  No schema change in 5.2; if a future story adds a `null`-favicon
  scan-and-retry surface, the existing `ImportFaviconBackfillService`
  API is reusable — it doesn't need to know its caller is the import
  path.
* **Per-host throttling.** The global `_maxConcurrent = 6` cap is the
  only flow control. If a future story bulk-imports single-host
  archives (e.g., a 500-page wiki dump), per-host throttling becomes
  worth re-examining.

## 8. Schema impact — none

**Schema remains at v7.** Neither 5.1 nor 5.2 add new tables, columns,
migrations, or Drift triggers. The existing `bookmarks` and `folders`
tables hold imported entities; the existing 11 outbox triggers and 5
FTS triggers fire on import + backfill writes through the repository
layer. Per Epic 3 retro P5 + Epic 4 retro §10 (
"schema-stable epics: name the non-change explicitly").
