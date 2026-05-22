# Sync Model

The contract for how this app pushes local changes to Google Drive. Update this document when the JSON envelope, the trigger set, the push-gate semantics, the retry policy, or the network destination list changes.

---

## Why this exists

The app is offline-first, single-user, no-backend, no-telemetry. The Drive sync subsystem (Epic 4) is the only network code in the app. Story 4.2 shipped the push half; Story 4.3 added the pull + merge half (per-record LWW conflict resolution). The full status state-machine lands in Story 4.4; connectivity-driven reconnect in Story 4.5.

Sync is the second-highest-risk subsystem for NFR9 ("no telemetry, no analytics, no third-party error reporting") -- centralising the contract here makes review easy: anything that uploads bytes from the device must be expressible against the rules below.

If you're adding or modifying anything in `lib/core/drive/`, read `docs/auth-model.md` first (it owns OAuth + credential storage), then this document, then -- if you're starting a new sync story -- the "Sync Architecture" section in `_bmad-output/planning-artifacts/architecture.md`.

---

## Hard rules

### 1. Whole-snapshot push, never deltas

Every push uploads the entire local state as a single `bookmarks.json` payload via Drive v3 `files.update`. There is no per-record patch protocol, no chunked / resumable upload, no multi-file Drive layout. The architecture's data model (line 110-141, line 188-203) is explicit on this: snapshot-replace + Drive's atomic media-replacement is the right shape for a single-user, personal-utility scale (one human, tens-of-thousands of bookmarks tops, low-frequency mutation).

If usage ever drives this assumption to break (e.g. a 50 MB JSON file taking 30s to upload over a flaky tether), the migration is a v2 envelope with a delta side-channel -- and the `version: 1` field at the JSON root is the migration hook.

### 2. Outbox triggers, no per-row payloads

User mutations are mirrored into `sync_queue` by 11 SQL `AFTER` triggers (`sync_triggers_schema.dart`). The queue is a "something changed" signal, not a delta log: `payload` is always NULL. The snapshot model means full state is uploaded regardless of which entries are in the queue; the queue's role is to wake the engine and to track at-least-once semantics.

Each trigger fires inside the same SQL transaction as its source mutation. Either both the mutation AND the queue row commit, or neither does. The queue can never miss a user write, and it can never contain a row whose mutation rolled back. Repository code MUST NOT INSERT into `sync_queue` directly -- the triggers are the only writers.

### 3. The v1 JSON envelope

The format on the wire is documented as a Dart-style schema below. Once any user has data in Drive at v1, the format is permanent until a properly-versioned migration replaces it.

```
DriveBookmarksFile {
  version:       int           // always 1 at this revision
  lastModified:  String        // ISO 8601 UTC, e.g. "2026-05-20T14:23:45.123Z"
  bookmarks:     List<DriveBookmark>
  folders:       List<DriveFolder>
  tags:          List<DriveTag>
}

DriveBookmark {
  id:            String        // UUID v4
  url:           String
  title:         String
  notes:         String?       // omitted from JSON when null
  folderId:      String?       // UUID v4, omitted from JSON when null
  faviconBase64: String?       // "data:image/<mime>;base64,..." prefix included; omitted when null
  tagIds:        List<String>  // UUID v4 refs into the top-level `tags` array; ALWAYS present
  createdAt:     String        // ISO 8601 UTC
  updatedAt:     String        // ISO 8601 UTC
}

DriveFolder {
  id:        String            // UUID v4
  name:      String
  parentId:  String?           // UUID v4, omitted from JSON when null (top-level folder)
  createdAt: String            // ISO 8601 UTC
  updatedAt: String            // ISO 8601 UTC
}

DriveTag {
  id:        String            // UUID v4
  name:      String
  createdAt: String            // ISO 8601 UTC
  updatedAt: String            // ISO 8601 UTC -- carries identity for Story 4.3's per-tag LWW
}
```

Field order in the emitted JSON matches the declaration order above (json_serializable preserves it). Top-level arrays are sorted by `createdAt` ASC then `id` ASC by `DriveSnapshotBuilder` -- a stable database produces byte-identical JSON across snapshots. Compact encoding (no whitespace) is used.

Null-vs-empty discipline: optional fields that ARE null are omitted (per `@JsonSerializable(includeIfNull: false)`); `tagIds` is always present, possibly as `[]`. Cross-language consumers (a future Android port reading this same file) shouldn't have to disambiguate "no tags" from "field missing".

### 4. The 11-trigger outbox set

| Trigger | Source table | Operation | entity_type | entity_id |
|---|---|---|---|---|
| `bookmarks_sync_ai` | bookmarks AI | `upsert` | `bookmark` | `NEW.id` |
| `bookmarks_sync_au` | bookmarks AU | `upsert` | `bookmark` | `NEW.id` |
| `bookmarks_sync_ad` | bookmarks AD | `delete` | `bookmark` | `OLD.id` |
| `folders_sync_ai` | folders AI | `upsert` | `folder` | `NEW.id` |
| `folders_sync_au` | folders AU | `upsert` | `folder` | `NEW.id` |
| `folders_sync_ad` | folders AD | `delete` | `folder` | `OLD.id` |
| `tags_sync_ai` | tags AI | `upsert` | `tag` | `NEW.id` |
| `tags_sync_au` | tags AU | `upsert` | `tag` | `NEW.id` |
| `tags_sync_ad` | tags AD | `delete` | `tag` | `OLD.id` |
| `bookmark_tags_sync_ai` | bookmark_tags AI | `upsert` | `bookmark` | `NEW.bookmark_id` |
| `bookmark_tags_sync_ad` | bookmark_tags AD | `upsert` | `bookmark` | `OLD.bookmark_id` |

Note: `bookmark_tags` triggers fire with `entity_type = 'bookmark'` because the user-observable change is "the bookmark's tag list now differs", not "a junction row exists in isolation". No `bookmark_tags_sync_au` -- the composite PK forbids in-place updates; a logical "rename" is a delete + insert.

### 5. The push gate (`drive.last_pulled_at`)

A device that connects Drive for the first time cannot distinguish (without reading the remote file's body):

- The user is the first-ever device in this Drive account (remote file is the empty v1 envelope from Story 4.1's `ensureBookmarksFile`).
- Another device already populated the remote file (Story 4.1 detected the existing file ID but never read content).

Pushing in the second case before Story 4.3's merge would silently overwrite the other device's data. The push gate prevents this:

- `drive.last_pulled_at` (ISO 8601 UTC string in secure storage) is the gate-open marker.
- `DriveSyncService.push()` short-circuits when the gate is closed.
- The first-connect probe (`_firstConnectProbe`) is the only piece of 4.3-shaped read logic in 4.2: it downloads `bookmarks.json`, parses it through the typed envelope, and -- if all three arrays are empty -- writes `drive.last_pulled_at = now()` to open the gate.
- If the remote has data, the engine leaves the gate closed, emits `SyncStatus.awaitingInitialPull`, and refuses to push until Story 4.3 lands and sets `drive.last_pulled_at` after its first successful merge.

### 6. The retry policy

`DriveRetryPolicy` (shipped in Story 4.1's `drive_file_service.dart`) is the single retry primitive used everywhere in the sync subsystem.

- **3 attempts total** (1 initial + 2 retries).
- **Exponential backoff** starting at 500ms, doubling each retry, capped at 30s.
- **±10% jitter** so concurrent retries from future systems don't thunder.
- **Transient classes that trigger retry:** HTTP 429, HTTP 5xx, `SocketException`, `HttpException`, `TimeoutException`.
- **Non-transient classes that propagate immediately:** HTTP 4xx other than 429 (401 / 403 / 400 / 404). These require user re-auth or are bugs we want to see, not transient blips.

Retry attempts emit `debugPrint` in debug builds only; no logging package is added (NFR9).

### 7. Atomicity comes from Drive

`files.update` with a media replacement is atomic at Drive's end: the file is either the old bytes or the new bytes, never a partial concatenation. NFR15 ("the JSON file in Drive is a valid, parseable snapshot at all times") is satisfied by Drive's contract; we do not need a client-side tempfile-and-rename dance. A mid-upload connection drop is a transient failure that `DriveRetryPolicy` retries -- the remote file remains the pre-upload bytes until the retry succeeds.

---

## The pull half (Story 4.3)

Story 4.3 makes the round-trip real. The orchestrator's three triggers (auth-state transition, lifecycle resume, queue-non-empty debounce) now dispatch a unified `sync()` call: pull-then-push, with short-circuit on pull failure. The push half above is unchanged; the pull half adds four pieces.

### 1. Pull-then-push cycle

`DriveSyncService.sync(fileId)` is `pull() ∘ push()`. Pull runs first so any remote changes from another device land locally before our own pending writes get uploaded; push only runs if pull returns `Ok`. The reasoning: a failed pull might leave us unaware of remote changes, so pushing our snapshot atop it risks overwriting another device's data. Pull failures emit `SyncStatus.failed`; the next trigger event retries.

### 2. LWW merge algorithm

`MergeEngine.merge(local, remote)` is a pure function: takes a `LocalSnapshot` and a `DriveBookmarksFile`, returns a `MergePlan` of upserts and deletes. The truth table (per record id, per entity type):

| Local | Remote | Comparison | Decision |
|---|---|---|---|
| absent | present | remote `updatedAt` ≥ local `drive.last_pulled_at` (or first sync) | upsert remote (FR23, FR36 first-launch) |
| absent | present | remote `updatedAt` < local `drive.last_pulled_at` | keep local-absent (we already saw this record at our last pull AND deleted it locally — don't resurrect; see "Symmetric tombstone-less heuristic" below) |
| present | absent | local `updatedAt` < remote `lastModified` | delete local (the other device deleted it) |
| present | absent | local `updatedAt` ≥ remote `lastModified` | keep local (our edit post-dates their snapshot) |
| present | present | remote `updatedAt` > local | upsert remote (FR24 silent LWW) |
| present | present | local `updatedAt` > remote | keep local |
| present | present | equal | lexicographic `id` asc tiebreaker — vanishingly rare; defensive determinism |

`bookmark_tags` has no per-link `updatedAt`. The merge is computed at parent-bookmark granularity: when the remote bookmark wins, replace the local junction set with the remote's `tagIds` array; when local wins, preserve local junctions. As of Story 4.5, `TagRepository.linkBookmarkTag` / `unlinkBookmarkTag` also bump the parent bookmark's `updated_at` so a local tag-only edit registers as a local LWW win — see "Symmetric tombstone-less heuristic" below.

#### Symmetric tombstone-less heuristic (Story 4.5)

The "in remote, not in local" branch has a *defaultive* answer (upsert) and an exceptional one (keep local absent). The exception only applies when `hasEverSynced == true` AND `lastPulledAtMs != null` AND `remoteUpdatedAt < lastPulledAtMs`. In English: *"we already merged this remote record at our last pull AND we've since deleted it locally, so don't resurrect it on the next pull."*

This is the symmetric twin of the "in local, not in remote" decision: that branch uses `remoteLastModified` to disambiguate "they deleted it" from "we never pushed it"; this new branch uses `lastPulledAtMs` (the local moment we last successfully merged) to disambiguate "they added it" from "we deleted it after seeing it". Together they give us per-direction tombstone-less deletion semantics without a tombstones table.

The original FR16 orphan-tag scenario this fixes: Device A unlinks the last bookmark from tag T. `TagRepository.unlinkBookmarkTag` hard-deletes T (FR16 orphan cleanup), emits a `delete tag T` sync_queue row, and pushes — remote's `tags[]` no longer contains T. On the next pull, remote *does* still contain T from a stale snapshot in some failure modes (or the local delete races a concurrent remote upsert). Without the heuristic, T is upserted back into local — orphan resurrected. With the heuristic, T's remote `updatedAt` predates `drive.last_pulled_at`, so we recognise it as "already seen and locally deleted" and skip the upsert. The same logic protects any local hard-delete from remote-side stale-snapshot resurrection.

### 3. Trigger feedback cleanup (the load-bearing design decision)

Merge writes fire 11 outbox triggers — one `sync_queue` row per merged record. The FTS triggers also fire, which is what we want (the FTS index must reflect the merged state). The `sync_queue` rows are NOT what we want: they would cause the auto-push orchestrator to observe a non-zero count and push the just-merged state straight back to Drive, burning quota in a ping-pong loop.

The fix lives inside the merge transaction:

1. `cursorId = COALESCE(MAX(id), 0) FROM sync_queue` BEFORE any merge write.
2. Apply the merge plan.
3. `DELETE FROM sync_queue WHERE id > cursorId` AFTER.

Any user mutation that races the merge is serialized by SQLite's write lock: it commits after the merge transaction commits, with its trigger-inserted rows having ids above the deleted range. The user write's queue rows survive untouched.

The alternative — modify the 11 trigger WHEN clauses to check a `temp.merge_active` flag — would require a schema migration and 11 trigger rewrites. The cursor approach was chosen because it's contained to `MergeApplier` and requires zero schema / trigger churn. Documented escalation path if a future selective-merge use case surfaces.

### 4. Version rejection

A remote envelope with `version != 1` is rejected with `Err(SyncError('Unsupported Drive file version: ...'))`. The gate is NOT opened. The local DB is NOT touched. The user sees the calm "Couldn't sync — will retry" indicator label and is expected to update to a newer client. The `version` field is the migration hook; the migration code does not yet exist.

### 5. Gate opening on merge

`drive.last_pulled_at = now()` is written AFTER the merge transaction commits, AFTER all writes are durable. A pull failure or version rejection leaves the flag in its prior state. Once the flag is non-null it stays non-null (until the user disconnects in 4.5); subsequent pulls refresh the timestamp idempotently.

### 6. First-connect probe (demoted)

The 4.2-era first-connect probe still exists in `_pushInternal` as a fast-path for the empty-remote case. The merge path is now the authoritative gate-opening route — `sync()` pulls first, the merge opens the gate, push observes the gate is already open and proceeds. The probe is only reachable via a direct `push()` call (tests; a future debug-only "Push now" button); it's retained because removing it would force a rework of 4.2's test fixtures for zero behavioral gain.

### 7. Tag-only edits (resolved in Story 4.5)

Previously: the bookmark `updatedAt` was not advanced when a tag link changed, so a local tag-only edit could lose LWW against an unrelated remote bookmark edit. As of Story 4.5, `TagRepository.linkBookmarkTag` / `unlinkBookmarkTag` wrap their writes in a transaction that ALSO bumps the parent bookmark's `updated_at` via `_bumpBookmarkUpdatedAt`. The `bookmarks` AU trigger emits a second `sync_queue` row alongside the `bookmark_tags` AI/AD row (both `entity_id = bookmarkId`); the push coalesces them into a single snapshot upload.

Combined with the symmetric tombstone-less heuristic (see "LWW merge algorithm" above), this also defends against the FR16 orphan-tag resurrection: a local hard-delete of an orphan tag stays deleted across the next pull, because the remote tag row's `updatedAt` predates our `drive.last_pulled_at` and the merge engine recognises it as "already seen + locally deleted".

---

## The status surface (Story 4.4)

4.2 + 4.3 built the engine. 4.4 owns what the user sees of it: the sidebar-footer indicator (`lib/core/widgets/sync_status_indicator.dart`). The widget is a pure projection of three reactive inputs onto a `(dot colour, label, pulsing?)` triple; no state of its own.

### Composite state

The truth table is the contract:

| status                                 | pendingCount | hasEverSynced | dot                       | label                              |
|---------------------------------------|--------------|----------------|---------------------------|-------------------------------------|
| `SyncPulling`                         | n/a          | n/a            | amber pulse               | `Pulling from Drive…`              |
| `SyncMerging`                         | n/a          | n/a            | amber pulse               | `Merging changes…`                 |
| `SyncPushing`                         | n/a          | n/a            | amber pulse               | `Syncing…`                         |
| `SyncFailed(NetworkError \| AuthError)` | n/a          | n/a            | grey                      | `Drive unavailable`                |
| `SyncFailed(other)`                   | n/a          | n/a            | grey                      | `Couldn't sync — will retry`       |
| `SyncAwaitingInitialPull`             | n/a          | n/a            | amber                     | `Awaiting initial sync from Drive` |
| `SyncIdle` / `SyncSynced`             | `> 0`        | n/a            | amber                     | `Unsynced changes`                 |
| `SyncIdle` / `SyncSynced`             | `0`          | `true`         | green                     | `Synced with Drive`                |
| `SyncIdle` / `SyncSynced`             | `0`          | `false`        | amber                     | `Awaiting initial sync from Drive` |

Precedence: in-progress beats queue-count; `SyncFailed` beats both. The widget's `switch` expression encodes this by branching on `status` first; queue-count is a secondary discriminator only for idle/synced. The dot palette tokens live in `lib/core/theme/app_colors.dart` (`syncSynced #6A9E6A`, `syncUnsynced #C8873A`, `syncUnavailable #9A9A9A`); they were added in 4.2 in anticipation of this story.

Coverage: FR25 (status visibility), FR26 (in-progress signal), FR27 (offline / unsynced surface), NFR12 (sync failures never silent — every grey state carries a label that the `Semantics(liveRegion: true)` wrap announces).

### `hasEverSyncedProvider` derivation

A `StreamProvider<bool>` derived from `driveSyncServiceProvider.watchStatus()`. Yields `false` first; flips to `true` on the first `SyncSynced` emit of the session and `return`s — a subsequent `SyncFailed` does NOT reset the flag (the gate has been opened).

We do NOT read `kDriveLastPulledAtKey` from secure storage on every rebuild. Trade-off: on a cold start where the gate was opened in a prior session, the engine emits `SyncIdle` first and the indicator briefly reads amber "Awaiting initial sync from Drive" until the cold-start `sync()` cycle lands its first `SyncSynced` (~250 ms). Accepted vs. the heavier alternative (per-rebuild storage read).

### In-progress visual

Vanilla Flutter: `AnimationController(duration: 1200ms)..repeat(reverse: true)`; opacity tweens 1.0 ↔ 0.4 inside a `FadeTransition`. No `flutter_animate`, no `lottie`, no motion framework dep. Wrapped in `RepaintBoundary` so the per-frame repaint stays within the 7×7 px bounds.

Reduce-motion: gated on `MediaQuery.disableAnimations`. When true, the dot renders static (no `FadeTransition`); the controller is still created so a runtime flip of the accessibility flag doesn't require disposing/recreating it.

### Failure-class mapping

`SyncFailed(NetworkError)` and `SyncFailed(AuthError)` both render "Drive unavailable" rather than distinct labels. Rationale: the auth-error path needs a re-auth flow before it's actionable, and that flow lives in Story 4.5. Surfacing "auth error" distinctly in 4.4 would tease an action the user can't take. The triage-minded user reading the labels at all is the rare case; for them, the grey colour is the signal that the engine needs attention, and the actual error class is in the debug console.

`SyncFailed(SyncError)` and `SyncFailed(StorageError)` render "Couldn't sync — will retry" (the verbatim 4.2 label, preserved so existing users see no wording regression). New error subclasses fall through to the generic case automatically — the `switch` is exhaustive on the abstract `AppError`.

### Audit invariant

4.4 adds zero new network surface, zero new dependencies, zero new SyncStatus variants, zero new outbox triggers, and zero new schema. The audit greps at the bottom of this doc continue to return the same results post-4.4 — verified pre-merge.

---

## Connectivity & disconnect (Story 4.5)

4.5 closes Epic 4. It adds the fourth sync trigger (network-restored), the Settings Disconnect flow, and the engine reset that ties them together. No new schema; no new SyncStatus variants; no new network surface.

### The four triggers

The `autoPushOrchestratorProvider` (`lib/core/drive/drive_sync_providers.dart`) now wires four sync triggers. All four are gated on `DriveAuthConnected`:

1. **Queue non-empty** (250 ms debounce). Fires `sync(fileId)` when the pending count transitions above zero. Source: `syncQueuePendingCountProvider`. Debounced to collapse rapid bursts (5 inserts within 1 s collapse to a single push).
2. **Auth `_ → connected`**. Fires `sync(fileId)` on the cold-start / reconnect transition. Source: `driveAuthStateProvider`. Also handles re-emits of `connected` from a tab focus / token refresh.
3. **Lifecycle `AppLifecycleState.resumed`**. Fires `sync(fileId)` when the app foregrounds. Source: `_SyncLifecycleObserver` in `lib/core/widgets/app_shell.dart`. The observer is mounted by AppShell so the trigger is dormant on the /welcome route.
4. **Connectivity `offline → online`** (Story 4.5). Fires `sync(fileId)` on a `false → true` transition of `connectivityOnlineProvider`. Source: `connectivity_plus.onConnectivityChanged` via `lib/core/drive/connectivity_providers.dart`.

The first three fire on STATE (the orchestrator listens for "queue is non-empty NOW", "auth IS connected NOW"). The fourth fires on TRANSITION — a `true → true` re-emit (e.g. `[wifi] → [wifi, ethernet]` when the user plugs in an ethernet cable on top of an existing Wi-Fi connection) does NOT fire `sync()`. The transition guard lives in the orchestrator listener (`if (wasOnline || !isOnline) return;`), not in `connectivityOnlineProvider` — keeping the provider a pure observation lets multiple consumers compose against it without baking in trigger semantics.

The connectivity trigger does NOT debounce. `connectivity_plus.onConnectivityChanged` emits at most a few times per minute even on flaky networks; each emit represents a real OS state change, and the engine's `_coalesce` (Story 4.3) absorbs any overlap with the other three triggers. A 250 ms debounce would just delay sync without benefit.

### `connectivity_plus` integration boundary

The package is the **wake-up signal**, NOT the **health check**. `connectivity_plus` reports OS-level interface presence (SCNetworkReachability on macOS, NetworkChangeNotifier on Linux, INetworkListManager on Windows), but it does NOT verify actual internet reachability. A captive-portal Wi-Fi (airport, hotel) reports `[ConnectivityResult.wifi]` and 4.5 fires `sync()` — which then `SyncFailed(NetworkError)`s against Drive and the indicator goes grey "Drive unavailable". This is correct: the engine's per-attempt retry IS the health check.

The API shape pinned by v6.1.x: `Connectivity().onConnectivityChanged` is `Stream<List<ConnectivityResult>>` (v5 returned a single `ConnectivityResult`). The mapping to `bool` is `list.any((r) => r != ConnectivityResult.none)`. Doc-cited in `lib/core/drive/connectivity_providers.dart` so a future package upgrade has a test surface to break against.

The `connectivityProvider` wraps the singleton for test override; tests inject a `_FakeConnectivity` with a controllable `StreamController<List<ConnectivityResult>>`.

### The disconnect choreography

`DriveAccountController.disconnect()` (`lib/features/settings/application/drive_account_controller.dart`) is the cross-cutting orchestrator. It runs three steps in order:

1. **Clear the sync queue.** `ref.read(syncQueueRepositoryProvider).clear()` — a single DELETE on `sync_queue`. Local data is unaffected.
2. **Close the push gate.** `delete(key: kDriveLastPulledAtKey)` on secure storage. The gate stays closed until the next reconnect's pull merges remote data via `MergeApplier`.
3. **Wipe tokens.** `ref.read(driveAuthStateProvider.notifier).reset()` — clears OAuth keys and flips auth state to `disconnected`.

The `connected → disconnected` auth-state transition trips the orchestrator's auth-state listener (also extended in 4.5), which calls `DriveSyncService.reset()` to clear engine in-memory state (`_lastEmitted = SyncIdle`, `_lastSyncedAt = null`) and `ref.invalidate(hasEverSyncedProvider)` so the next reconnect starts from a clean amber-then-green baseline. The same auth transition also trips GoRouter's `_AuthRefreshNotifier`, which redirects `/settings` → `/welcome` via the existing 4.1 redirect logic (no router change in 4.5).

**Why a separate controller** rather than overloading `DriveAuthNotifier.reset()`: the auth notifier owns auth state (tokens, email, fileId). It does NOT own sync-side state (queue rows, gate timestamp, engine cache). Coupling them via the auth notifier would force the auth subsystem to know about the database; coupling them via the engine would force the engine to know about disconnect semantics. The controller is the right layer for cross-subsystem coordination.

**Why the queue is cleared, but local data isn't**: the queue is sync-side state — pre-disconnect rows are specifically "changes to upload to the (now-being-removed) account". Reconnecting to a *different* Google account would otherwise leak the prior account's queued changes into the new account's `bookmarks.json`. Local Drift data, by contrast, is the user's bookmarks — they exist independently of any Drive account. The next pull's LWW merge naturally re-discovers any unsynced local changes (their `updatedAt` is newer than the remote), so the queue clear is safe.

**Best-effort cleanup.** Each step is wrapped in try/catch with `debugPrint` on failure; subsequent steps run regardless. A macOS Keychain hiccup on the gate-delete must not block the token-wipe step — the user-visible outcome of disconnect must be "Drive is disconnected" even on partial state. Any zombie keys heal on the next reconnect via `DriveAuthService.resolveInitialState()`'s all-or-nothing check.

### Reset vs dispose

`DriveSyncService.reset()` (new in 4.5) is distinct from `dispose()`:

- `reset()` clears in-memory state (`_lastEmitted`, `_lastSyncedAt`); awaits any in-flight cycle's natural completion (we don't have cancellation primitives); emits `SyncStatus.idle()` on the broadcast stream so subscribers see the cleared state. Does NOT close the `_statusController` — subscribers stay live across disconnect/reconnect cycles.
- `dispose()` (existing) sets `_disposed = true` and closes the broadcast stream. Used only when the `ProviderContainer` is torn down (app shutdown).

A future reconnect re-uses the same `DriveSyncService` instance (the provider is long-lived for the lifetime of the container), which means the broadcast stream's existing subscribers (the indicator, integration tests) continue working without re-subscribing.

### Audit invariant

4.5 adds **one** new external dependency surface — `connectivity_plus` is imported by `lib/` for the first time (the package was a transitive dep since 4.1; `pubspec.yaml:41` line is unchanged). Zero new network destinations, zero new SyncStatus variants, zero new outbox triggers, zero new schema, zero new router routes, zero new polling primitives. The audit greps below continue to return the expected results post-4.5 — verified pre-merge.

---

## Network destinations

The sync subsystem contacts EXACTLY these endpoints. Anything else is a bug.

| Endpoint | Purpose | Frequency |
|---|---|---|
| `https://oauth2.googleapis.com/token` | Refresh access token via `googleapis_auth.autoRefreshingClient` | On access-token expiry (~1×/hour for an active session) |
| `https://www.googleapis.com/drive/v3/files/{fileId}` (`files.update`) | Whole-snapshot push | 1× per push window |
| `https://www.googleapis.com/drive/v3/files/{fileId}?alt=media` (`files.get`) | Pull (Story 4.3); first-connect probe (Story 4.2 fast-path) | 1× per sync cycle; probe is 1×/device-lifetime |

The authentication endpoints proper (consent + initial token exchange) are covered in `docs/auth-model.md`. They are NOT re-listed here -- the sync engine never invokes them; OAuth flow is Story 4.1's territory.

---

## Audit grep

Run before each Epic 4 story merge:

```bash
# NFR9: no telemetry, no analytics, no error reporting SDK.
grep -ri "(firebase|sentry|crashlytics|mixpanel|amplitude|appcenter|datadog|posthog|segment)" pubspec.yaml lib/ test/

# Sync never polls -- the only four triggers are event-based.
# Story 4.5 widens the scope to also cover the sync orchestrator wiring,
# the new connectivity providers, and the disconnect controller.
grep -ri "polling\|setInterval\|Timer\.periodic" lib/core/drive/ lib/core/widgets/ lib/features/settings/

# All HTTP endpoints in the sync surface should be Drive or token endpoints.
grep -rn "http\." lib/core/drive/ | grep -v "_test\.dart"

# Pull / push touch only files.get and files.update on www.googleapis.com.
grep -rn "files\.get\|files\.update" lib/core/drive/
```

Expected output: zero matches for the first two; the third should only surface the Drive and OAuth token URLs from `oauth_config.dart` and the googleapis package; the fourth surfaces only `api.files.get` and `api.files.update` in `drive_sync_service.dart` (no other Drive endpoints).

---

## Cross-references

- `lib/core/drive/drive_sync_service.dart` -- the engine (push + pull + unified `sync` cycle).
- `lib/core/drive/merge_engine.dart` -- pure per-record LWW; produces a `MergePlan` (Story 4.3).
- `lib/core/drive/merge_applier.dart` -- transactional applier with cursor-cleanup for trigger feedback (Story 4.3).
- `lib/core/drive/drive_snapshot_builder.dart` -- assembles the v1 envelope; exposes `readLocalSnapshot()` for the merge applier.
- `lib/core/drive/models/` -- the envelope types.
- `lib/core/database/sync_triggers_schema.dart` -- the 11 outbox trigger DDL.
- `lib/core/database/drift_files/sync_triggers.drift` -- the trigger documentation source-of-truth.
- `lib/core/drive/drive_credentials_store.dart` -- the auto-refreshing client wrapper.
- `lib/core/drive/drive_sync_providers.dart` -- Riverpod wiring + the 250ms-debounced auto-push orchestrator + connectivity / disconnect listeners (Story 4.5).
- `lib/core/drive/connectivity_providers.dart` -- `connectivity_plus` wrapper for the offline → online trigger (Story 4.5).
- `lib/features/settings/application/drive_account_controller.dart` -- the disconnect choreography (queue clear → gate clear → token wipe) (Story 4.5).
- `lib/core/widgets/sync_status_indicator.dart` -- the sidebar surface (text + dot at 4.4).
- `docs/auth-model.md` -- OAuth + credential storage (read first if you're new to this subsystem).
- `_bmad-output/planning-artifacts/architecture.md` -- the "Sync Architecture" section is the architecture-audience version of this document.
