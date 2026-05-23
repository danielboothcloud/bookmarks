# bookmarks

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## CI / Dagger Pipeline

CI runs as a custom Dagger module at `.dagger/main.go` (Go SDK). The
same `dagger call ...` functions invoked from GitHub Actions are
callable on a developer machine, so local runs and CI runs share one
source of truth. Dagger Cloud provides traces and a distributed cache
across both.

### One-time setup

1. **1Password** — in the `homelab` vault, create a single item named
   `bookmarks` with three fields:
   - `oauth_client_id` (from `client-creds.json`)
   - `oauth_client_secret` (from `client-creds.json`)
   - `dagger_cloud_token` (from <https://cloud.dagger.io>)
2. **1Password Service Account** — create one with read-only access to
   the `homelab` vault. Copy the service account token.
3. **GitHub** — add `OP_SERVICE_ACCOUNT_TOKEN` as the **only**
   repository secret. Everything else flows through 1Password.

### Local invocation (fish)

Sign in with `op signin`, then call any function:

```fish
# No secrets — fast feedback loop
dagger call analyze --source=.
dagger call test --source=.
dagger call codegen-check --source=.

# With OAuth secrets resolved from 1Password (matches CI exactly)
dagger call test --source=. \
  --oauth-client-id=op://homelab/bookmarks/oauth_client_id \
  --oauth-client-secret=op://homelab/bookmarks/oauth_client_secret

# Regenerate code and export it back to the host
dagger call codegen --source=. export --path=.

# Release builds (Linux host required for build-linux,
# Windows host with Dagger Desktop for build-windows)
dagger call build-linux --source=. \
  --oauth-client-id=op://homelab/bookmarks/oauth_client_id \
  --oauth-client-secret=op://homelab/bookmarks/oauth_client_secret \
  export --path=./out
```

If you can't use the `op://` provider, swap to env vars:

```fish
set -x BOOKMARKS_OAUTH_CLIENT_ID (jq -r .installed.client_id client-creds.json)
set -x BOOKMARKS_OAUTH_CLIENT_SECRET (jq -r .installed.client_secret client-creds.json)
dagger call test --source=. \
  --oauth-client-id=env://BOOKMARKS_OAUTH_CLIENT_ID \
  --oauth-client-secret=env://BOOKMARKS_OAUTH_CLIENT_SECRET
```

### Available functions

CLI names are the kebab-case form of the exported Go methods on
`Bookmarks` in `.dagger/main.go` (`BuildLinux` → `build-linux`, etc.).

| Function          | Host         | Purpose                                                                     |
| ----------------- | ------------ | --------------------------------------------------------------------------- |
| `analyze`         | any          | `flutter analyze --fatal-infos --fatal-warnings`                            |
| `test`            | any          | `flutter test` with optional OAuth `--dart-define`s                         |
| `codegen`         | any          | `dart run build_runner build --delete-conflicting-outputs`                  |
| `codegen-check`   | any          | Regenerate, then diff against a pre-codegen snapshot; fails CI on drift     |
| `build-linux`     | Linux/Dagger | Release Flutter Linux desktop bundle (`build/linux/x64/release/bundle`)     |
| `build-windows`   | Windows host | Release Flutter Windows desktop bundle (`build/windows/x64/runner/Release`) |

### Watch out for

- **Flutter version drift.** The module pins Flutter to `3.41.9` to
  match `mise.toml`. When you bump mise, bump the `flutterVersion`
  constant at the top of `.dagger/main.go` in the same change.
- **Windows is slow on the first run.** VS Build Tools install ~15
  minutes cold. Dagger caches the layer; subsequent runs are fast.
- **macOS desktop builds are not in this pipeline.** Apple licensing
  forbids containerized macOS builds. Use `mise run build-macos`
  locally.

### Dagger Cloud

Every CI run publishes a trace to <https://cloud.dagger.io>. The
trace URL is printed at the end of the workflow log by
`dagger/dagger-for-github`.
