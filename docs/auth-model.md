# Auth Model

The contract for how this app authenticates against Google Drive. Update this document when the auth surface, the scope set, the persisted-key catalogue, or the network destination list changes.

---

## Why this exists

The app is offline-first, single-user, no-backend, no-telemetry. The only network code in the app is the Google Drive sync subsystem (Epic 4). Auth sits at the front of that subsystem and is the highest-risk place to accidentally violate NFR9 ("no telemetry, no analytics, no third-party error reporting"). Centralising the auth contract here makes review easy: anything in the codebase that connects to the network must be expressible as a line in the "Network destinations" table below.

If you're adding or modifying anything in `lib/core/drive/`, read this whole document first.

---

## Hard rules

### 1. `drive.appdata` scope only

The app requests exactly one OAuth scope: `https://www.googleapis.com/auth/drive.appdata`. It never requests `drive`, `drive.file`, `drive.readonly`, `openid`, `email`, `profile`, or any other scope. The `appDataFolder` virtual folder is per-app and hidden from the user-facing Drive UI — exactly the right blast radius for a personal utility.

A consequence: the `id_token` returned at OAuth completion typically does not carry an `email` claim (which would require `openid email`). The Settings UI falls back to the literal string `"Google account"` when the email can't be extracted. That's by design — we don't ask for what we don't need.

### 2. PKCE end-to-end

OAuth flows for Desktop public clients use Authorization Code + PKCE (RFC 7636):

- `code_verifier` — 64 random chars from the unreserved set `[A-Z][a-z][0-9]-._~`, generated via `Random.secure()`. Held in memory only for the duration of the flow; never persisted.
- `code_challenge` — `base64url-no-pad(SHA-256(code_verifier))`. Sent in the authorization URL.
- `state` — 32 random bytes, base64url-no-pad. Sent in the authorization URL and validated on callback (CSRF defence).
- `client_secret` — included in the token-exchange POST (Google requires it for Desktop clients). It is NOT a real secret; Google's own docs and our architecture decision are explicit on this. PKCE is what protects the flow.

### 3. Loopback callback, ephemeral port

The OAuth `redirect_uri` is `http://127.0.0.1:<port>/`, where `<port>` is OS-assigned at `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` time. The server is one-shot: it accepts a single request (the OAuth callback), responds with an inline-CSS HTML success/error page, and shuts down. A 5-minute timeout bounds the wait; on timeout, the port is released and the flow yields `DriveAuthDisconnected` (same as user cancellation).

### 4. Tokens live in platform secure storage (with one macOS caveat)

All persisted auth state goes through `flutter_secure_storage`:

- **Linux** → libsecret
- **Windows** → Credential Manager
- **iOS / Android** → Keychain / Keystore
- **macOS, signed builds** → Keychain Services
- **macOS, unsigned builds (this project's default)** → `FileTokenStorage`, a JSON file at `~/Library/Application Support/dev.bookmarks.bookmarks/secrets.json` with mode `0600`.

The macOS fallback exists because macOS 26 (Tahoe) requires an `application-identifier` entitlement on the binary to access Keychain — which only lands when the bundle is code-signed with a real Apple Team (Personal Team via Xcode is sufficient). This project ships unsigned to keep the build prerequisites short (no Xcode, no Apple ID); the `FileTokenStorage` fallback documented in `lib/core/drive/file_token_storage.dart` is the trade-off.

Nothing auth-related is in the local Drift DB, in shared preferences, or in an env variable. Either path keeps tokens out of the codebase and out of git.

### 5. Zero telemetry, zero analytics, zero error reporting

The audit:

```sh
grep -ri "(firebase|sentry|crashlytics|mixpanel|amplitude|appcenter|datadog|posthog|segment)" pubspec.yaml lib/ test/
```

must return zero results, forever. There is no allowed exception. If a future story needs error reporting, it must be local-only (debug log, in-app diagnostics view) — never a third-party service.

---

## The PKCE + loopback flow

```
┌─────────────┐                                                     ┌──────────────┐
│ Bookmarks   │                                                     │ accounts     │
│ (Flutter)   │                                                     │ .google.com  │
└──────┬──────┘                                                     └──────┬───────┘
       │                                                                   │
       │ 1. Generate code_verifier (64 chars), state (32 bytes)            │
       │ 2. code_challenge = base64url-no-pad(SHA-256(code_verifier))      │
       │ 3. Bind HttpServer on 127.0.0.1:<random port>                     │
       │                                                                   │
       │ 4. Launch system browser → ───────────────────────────────────────┤
       │    GET /o/oauth2/v2/auth?                                         │
       │        client_id=<id>&                                            │
       │        response_type=code&                                        │
       │        scope=drive.appdata&                                       │
       │        redirect_uri=http://127.0.0.1:<port>/&                     │
       │        code_challenge=<challenge>&                                │
       │        code_challenge_method=S256&                                │
       │        state=<state>&                                             │
       │        access_type=offline&                                       │
       │        prompt=consent                                             │
       │                                                                   │
       │                                  User signs in + grants consent   │
       │                                                                   │
       │ 5. Browser redirected to ←────────────────────────────────────────┤
       │    http://127.0.0.1:<port>/?code=<code>&state=<state>             │
       │                                                                   │
       │ 6. Loopback server validates state (must match)                   │
       │ 7. Respond 200 + HTML "Connected. You can close this tab"         │
       │ 8. Shut down loopback server                                      │
       │                                                                   │
       │ 9. POST oauth2.googleapis.com/token ─────► oauth2.googleapis.com  │
       │    grant_type=authorization_code&                                 │
       │    code=<code>&                                                   │
       │    redirect_uri=http://127.0.0.1:<port>/&                         │
       │    client_id=<id>&                                                │
       │    client_secret=<not-actually-secret>&                           │
       │    code_verifier=<verifier>                                       │
       │                                                                   │
       │ 10. ←─────── { access_token, refresh_token, expires_in, id_token }│
       │                                                                   │
       │ 11. Persist tokens + email to flutter_secure_storage              │
       │ 12. GET www.googleapis.com/drive/v3/files?spaces=appDataFolder    │
       │     &q=name='bookmarks.json'   (auth via Bearer access_token)     │
       │ 13. If empty → POST .../drive/v3/files (create empty JSON)        │
       │     else      → use existing file id                              │
       │ 14. Persist file id; transition DriveAuthState → connected        │
       │                                                                   │
```

---

## Network destinations (entire app)

| Host                        | Purpose                                  | Scope required        | Called from                            |
|-----------------------------|------------------------------------------|-----------------------|----------------------------------------|
| `accounts.google.com`       | OAuth2 authorization endpoint            | n/a (user's browser)  | `url_launcher.launchUrl` only          |
| `oauth2.googleapis.com`     | Token exchange POST                      | n/a (PKCE-protected)  | `DriveAuthService.connect`             |
| `www.googleapis.com`        | Drive v3 `files.list` / `files.create`   | `drive.appdata`       | `DriveFileService.ensureBookmarksFile` |
| `<favicon hosts>`           | Per-bookmark favicon fetch               | n/a (public HTTP GET) | `MetadataFetchService` (Story 1.3)     |
| `<bookmarked URLs>`         | URL metadata fetch (title/OG)            | n/a (public HTTP GET) | `MetadataFetchService` (Story 1.3)     |

Anything outside this list is a bug. The app must NEVER contact Firebase, Sentry, Crashlytics, Mixpanel, Amplitude, AppCenter, Datadog, PostHog, Segment, or any other third-party service.

---

## Secure-storage keys

All under namespace `drive.*`. Values are platform-native secure storage (Keychain / Credential Manager / libsecret), or — on unsigned macOS builds — `FileTokenStorage`'s JSON file (see Hard rule 4).

| Key                            | Format                                  | Written by                                     | Lifecycle                                          |
|--------------------------------|------------------------------------------|------------------------------------------------|-----------------------------------------------------|
| `drive.access_token`           | Opaque string (Google OAuth2)            | `DriveAuthService.connect` step 11             | Lifetime ~1 hour; refreshed lazily in Story 4.2     |
| `drive.refresh_token`          | Opaque string (Google OAuth2)            | `DriveAuthService.connect` step 11             | Long-lived; wiped on disconnect (4.5) or auth failure |
| `drive.expires_at`             | ISO 8601 UTC timestamp                   | `DriveAuthService.connect` step 11             | Updated on each refresh                             |
| `drive.user_email`             | Email string or literal `"Google account"`| `DriveAuthService.connect` step 11             | Display only (Settings)                             |
| `drive.bookmarks_file_id`      | Drive file id (opaque)                   | `DriveAuthService.connect` step 13             | Stable per Drive account                            |

Defensive cleanup: on any `DriveAuthFailed` transition or test-driven `reset()`, `DriveAuthService.clearTokens` deletes all five keys. There is no half-written state.

---

## Non-events

Things this app explicitly does NOT do at the auth layer:

- **No `openid email profile` scope.** Don't ask for what you don't need.
- **No eager token refresh.** Story 4.2 leans on `googleapis_auth`'s 401-then-refresh; no proactive timer.
- **No multi-account support.** Single connection at a time; reconnect requires Disconnect first.
- **No revocation on disconnect.** Local clear only (deferred per Story 4.5 plan).
- **No analytics / crash reporting / usage telemetry.** See "Hard rule 5" above.
- **No third-party auth provider SDK.** No Firebase Auth, no Auth0, no Okta — we own the flow.
- **No `googleapis_auth` consent-flow helpers in Story 4.1.** We hand-roll the loopback + token exchange so the lifecycle is visible (and testable). `googleapis_auth.AuthClient` will appear in Story 4.2 for sync-engine token refresh.
- **No HTTPS for the loopback server.** It's `http://127.0.0.1:<port>/` per Google's Desktop OAuth2 documentation; no certificate handling.
- **No persistent state for the OAuth flow.** `code_verifier`, `state`, and the bound server live only in the lifetime of one `DriveAuthService.connect()` call.

---

## When to extend this document

- A new Drive API endpoint is added → add it to "Network destinations".
- A new secure-storage key is introduced → add it to the key catalogue.
- A scope change becomes necessary (e.g. moving to `drive.file` to support user-selectable folders) → revise "Hard rules" §1 and the corresponding ADR.
- A new "non-event" decision is made → add it to the "Non-events" list with a one-line rationale.

This document is owned by the auth subsystem; treat divergence between the code and the document as a bug.
