# Sync Model

The contract for how this app pushes local changes to Google Drive. Update this document when the JSON envelope, the trigger set, the push-gate semantics, the retry policy, or the network destination list changes.

---

## Why this exists

The app is offline-first, single-user, no-backend, no-telemetry. The Drive sync subsystem (Epic 4) is the only network code in the app. Story 4.2 ships the push half; pull / merge / conflict resolution land in Story 4.3, the full status state-machine in Story 4.4, connectivity-driven reconnect in Story 4.5.

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

## Network destinations

The sync subsystem contacts EXACTLY these endpoints. Anything else is a bug.

| Endpoint | Purpose | Frequency |
|---|---|---|
| `https://oauth2.googleapis.com/token` | Refresh access token via `googleapis_auth.autoRefreshingClient` | On access-token expiry (~1×/hour for an active session) |
| `https://www.googleapis.com/drive/v3/files/{fileId}` | `files.update` upload (push) and `files.get?alt=media` (first-connect probe only) | 1× per push window; first-connect probe is 1×/device-lifetime |

The authentication endpoints proper (consent + initial token exchange) are covered in `docs/auth-model.md`. They are NOT re-listed here -- the sync engine never invokes them; OAuth flow is Story 4.1's territory.

---

## Audit grep

Run before each Epic 4 story merge:

```bash
# NFR9: no telemetry, no analytics, no error reporting SDK.
grep -ri "(firebase|sentry|crashlytics|mixpanel|amplitude|appcenter|datadog|posthog|segment)" pubspec.yaml lib/ test/

# Sync never polls -- the only triggers are event-based.
grep -ri "polling\|setInterval\|periodic" lib/core/drive/

# All HTTP endpoints in the sync surface should be Drive or token endpoints.
grep -rn "http\." lib/core/drive/ | grep -v "_test\.dart"
```

Expected output: zero matches for the first two; the third should only surface the Drive and OAuth token URLs from `oauth_config.dart` and the googleapis package.

---

## Cross-references

- `lib/core/drive/drive_sync_service.dart` -- the engine.
- `lib/core/drive/drive_snapshot_builder.dart` -- assembles the v1 envelope.
- `lib/core/drive/models/` -- the envelope types.
- `lib/core/database/sync_triggers_schema.dart` -- the 11 outbox trigger DDL.
- `lib/core/database/drift_files/sync_triggers.drift` -- the trigger documentation source-of-truth.
- `lib/core/drive/drive_credentials_store.dart` -- the auto-refreshing client wrapper.
- `lib/core/drive/drive_sync_providers.dart` -- Riverpod wiring + the 250ms-debounced auto-push orchestrator.
- `lib/core/widgets/sync_status_indicator.dart` -- the sidebar surface (text only at 4.2; dots at 4.4).
- `docs/auth-model.md` -- OAuth + credential storage (read first if you're new to this subsystem).
- `_bmad-output/planning-artifacts/architecture.md` -- the "Sync Architecture" section is the architecture-audience version of this document.
