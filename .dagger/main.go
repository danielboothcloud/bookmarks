// Dagger pipeline for the bookmarks Flutter project — codegen, analyze,
// test, build-linux, build-windows. Functions mirror the local mise tasks
// (`mise run dev` / `mise run build-linux` / `mise run build-macos`) so
// CI and local invocation share a single source of truth.
//
// Flutter is pinned to 3.41.9 to match mise.toml. OAuth secrets flow
// through Dagger's Secret API and are surfaced into the Flutter
// toolchain via `--dart-define`, the same contract as the mise tasks.
//
// Every function takes the same `+ignore=[...]` list on its `source`
// parameter. The list excludes local build outputs, gitignored
// secrets, planning artifacts, and tool caches — none of which the
// pipeline needs and all of which would balloon the host->container
// filesync. Keep the lists identical across functions.

package main

import (
	"context"
	"dagger/bookmarks/internal/dagger"
)

const (
	flutterVersion       = "3.41.9"
	linuxBaseImage       = "debian:bookworm-slim"
	windowsBaseImage     = "mcr.microsoft.com/windows/servercore:ltsc2022"
	flutterLinuxRepo     = "https://github.com/flutter/flutter.git"
	flutterWindowsZipURL = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_" + flutterVersion + "-stable.zip"
	flutterLinuxInstall  = "/opt/flutter"
	pubCacheVolume       = "flutter-pub-cache"
	pubCachePath         = "/root/.pub-cache"
)

type Bookmarks struct{}

// linuxBase returns a Debian Bookworm container with the Flutter Linux
// desktop build dependencies installed in a single layer.
func (m *Bookmarks) linuxBase() *dagger.Container {
	return dag.Container().
		From(linuxBaseImage).
		WithEnvVariable("HOME", "/root").
		WithEnvVariable("PUB_CACHE", pubCachePath).
		// Dagger runs the container in a user-namespaced sandbox
		// where chown to arbitrary uids is denied. Flutter's gradle
		// wrapper tarball has non-root ownership baked in, so tar
		// fails. TAR_OPTIONS is honoured by GNU tar globally — every
		// tar invocation in this layer will skip chown.
		WithEnvVariable("TAR_OPTIONS", "--no-same-owner").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{
			"apt-get", "install", "-y", "--no-install-recommends",
			"curl",
			"git",
			"unzip",
			"xz-utils",
			"zip",
			"libglu1-mesa",
			"clang",
			"cmake",
			"ninja-build",
			"pkg-config",
			"libgtk-3-dev",
			"liblzma-dev",
			"libstdc++-12-dev",
			"ca-certificates",
		})
}

// flutterLinuxBase extends linuxBase with the Flutter SDK pinned to
// the version declared in mise.toml. We clone the Flutter repo at the
// matching git tag rather than running `flutter upgrade`, which would
// silently drift from the pin.
func (m *Bookmarks) flutterLinuxBase() *dagger.Container {
	return m.linuxBase().
		WithExec([]string{
			"git", "clone",
			"--depth", "1",
			"--branch", flutterVersion,
			flutterLinuxRepo,
			flutterLinuxInstall,
		}).
		WithEnvVariable(
			"PATH",
			flutterLinuxInstall+"/bin:${PATH}",
			dagger.ContainerWithEnvVariableOpts{Expand: true},
		).
		// `flutter --version` doubles as a smoke test (the layer fails
		// fast if the install is broken) and pre-downloads the Dart
		// engine so later steps don't pay that cost.
		WithExec([]string{"flutter", "--version"}).
		// Disable every target except Linux desktop. Android in
		// particular triggers a gradle-wrapper download whose tarball
		// has non-root ownership baked in — tar then fails to chown
		// inside Dagger's user-namespaced container.
		WithExec([]string{
			"flutter", "config",
			"--no-enable-android",
			"--no-enable-ios",
			"--no-enable-web",
			"--no-enable-fuchsia",
			"--no-enable-macos-desktop",
			"--no-enable-windows-desktop",
			"--enable-linux-desktop",
		})
}

// withSource attaches the persistent pub cache, mounts pubspec files
// first to run `flutter pub get` (so changes elsewhere in the tree
// don't invalidate the dependency-resolution layer), then overlays
// the full source. Source is added via WithDirectory (copy, not bind
// mount) so build_runner's writes into /src are part of the directory
// snapshot returned by Codegen.
func (m *Bookmarks) withSource(c *dagger.Container, source *dagger.Directory) *dagger.Container {
	return c.
		WithMountedCache(
			pubCachePath,
			dag.CacheVolume(pubCacheVolume),
			dagger.ContainerWithMountedCacheOpts{Sharing: dagger.CacheSharingModeLocked},
		).
		WithWorkdir("/src").
		WithFile("/src/pubspec.yaml", source.File("pubspec.yaml")).
		WithFile("/src/pubspec.lock", source.File("pubspec.lock")).
		WithExec([]string{"flutter", "pub", "get"}).
		WithDirectory("/src", source)
}

// Codegen runs build_runner across the project (drift, freezed,
// json_serializable) and returns the resulting source tree so callers
// can extract regenerated files via `export`. Returns the full source
// tree so callers may inspect any generated file; this means
// `export --path=.` will overwrite the host source tree (intended for
// the regeneration workflow — see README).
func (m *Bookmarks) Codegen(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
) (*dagger.Directory, error) {
	c, err := m.withSource(m.flutterLinuxBase(), source).
		WithExec([]string{"dart", "run", "build_runner", "build", "--delete-conflicting-outputs"}).
		Sync(ctx)
	if err != nil {
		return nil, err
	}
	return c.Directory("/src"), nil
}

// CodegenCheck regenerates code and asserts the generated files
// haven't drifted from what's committed. CI uses this as a drift gate
// — if a contributor changes a `.drift` source without committing the
// regenerated output, the workflow fails with a diff.
//
// The mounted source has no `.git`, so we initialise a throwaway repo
// inside the container, snapshot HEAD, regenerate, then `git diff
// --exit-code` against the snapshot using pathspec globs that git
// (unlike POSIX `diff`) understands natively.
func (m *Bookmarks) CodegenCheck(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
) (string, error) {
	const checkScript = `set -e
cd /src
git init -q
git -c user.email=ci@local -c user.name=ci add -A
git -c user.email=ci@local -c user.name=ci commit -q -m baseline
dart run build_runner build --delete-conflicting-outputs
if ! git diff --exit-code -- '*.g.dart' '*.freezed.dart' 'test/generated/**'; then
  echo "ERROR: generated files drifted — run 'dagger call codegen --source=. export --path=.' and commit the result" >&2
  exit 1
fi
echo "codegen clean"
`
	return m.withSource(m.flutterLinuxBase(), source).
		WithExec([]string{"sh", "-c", checkScript}).
		Stdout(ctx)
}

// Analyze runs `flutter analyze` with infos and warnings promoted to
// fatal, matching the strictness expected of a production CI gate.
func (m *Bookmarks) Analyze(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
) (string, error) {
	return m.withSource(m.flutterLinuxBase(), source).
		WithExec([]string{"flutter", "analyze", "--fatal-infos", "--fatal-warnings"}).
		Stdout(ctx)
}

// Test runs the full `flutter test` suite. OAuth secrets are optional:
// callers may pass nil for PR runs that don't need live Drive access.
// `lib/core/drive/oauth_config.dart` documents empty defaults as
// harmless at build/test time — only runtime "Connect Google Drive"
// fails. The `${VAR:-}` expansion preserves that contract whether
// secrets are attached or not.
func (m *Bookmarks) Test(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
	// +optional
	oauthClientId *dagger.Secret,
	// +optional
	oauthClientSecret *dagger.Secret,
) (string, error) {
	c := m.withSource(m.flutterLinuxBase(), source)
	c = withOAuthSecrets(c, oauthClientId, oauthClientSecret)
	return c.
		WithExec([]string{
			"sh", "-c",
			"flutter test " +
				"--dart-define=BOOKMARKS_OAUTH_CLIENT_ID=${BOOKMARKS_OAUTH_CLIENT_ID:-} " +
				"--dart-define=BOOKMARKS_OAUTH_CLIENT_SECRET=${BOOKMARKS_OAUTH_CLIENT_SECRET:-}",
		}).
		Stdout(ctx)
}

// BuildLinux produces a release Flutter Linux desktop bundle. Returns
// the bundle directory so callers can `export --path=./out` it for
// artifact upload.
func (m *Bookmarks) BuildLinux(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
	// +optional
	oauthClientId *dagger.Secret,
	// +optional
	oauthClientSecret *dagger.Secret,
) (*dagger.Directory, error) {
	c := m.withSource(m.flutterLinuxBase(), source)
	c = withOAuthSecrets(c, oauthClientId, oauthClientSecret)
	c, err := c.WithExec([]string{
		"sh", "-c",
		"flutter build linux --release " +
			"--dart-define=BOOKMARKS_OAUTH_CLIENT_ID=${BOOKMARKS_OAUTH_CLIENT_ID:-} " +
			"--dart-define=BOOKMARKS_OAUTH_CLIENT_SECRET=${BOOKMARKS_OAUTH_CLIENT_SECRET:-}",
	}).Sync(ctx)
	if err != nil {
		return nil, err
	}
	return c.Directory("/src/build/linux/x64/release/bundle"), nil
}

// windowsBase returns a Windows Server Core container with Visual
// Studio Build Tools (C++ workload + Windows 10 SDK) and git
// installed via Chocolatey. The first run takes 15+ minutes; Dagger
// content-addresses the layer so subsequent runs hit cache. Future
// work bakes this image and pushes it to ghcr.io to avoid the cold
// cost entirely.
func (m *Bookmarks) windowsBase() *dagger.Container {
	const installChoco = `Set-ExecutionPolicy Bypass -Scope Process -Force; ` +
		`[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; ` +
		`iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))`

	const installBuildTools = `choco install -y visualstudio2022buildtools ` +
		`--package-parameters "--add Microsoft.VisualStudio.Workload.VCTools ` +
		`--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ` +
		`--add Microsoft.VisualStudio.Component.Windows10SDK.19041 ` +
		`--quiet --norestart"`

	return dag.Container().
		From(windowsBaseImage).
		WithExec([]string{"powershell", "-NoProfile", "-Command", installChoco}).
		WithExec([]string{"powershell", "-NoProfile", "-Command", installBuildTools}).
		WithExec([]string{"powershell", "-NoProfile", "-Command", "choco install -y git"})
}

// flutterWindowsBase extends windowsBase with the Flutter Windows SDK
// pinned to the same version as mise.toml. We download the official
// zip rather than cloning to match the mise install shape and to
// avoid pulling the full Flutter git history.
//
// PATH is set via Dagger's WithEnvVariable rather than a Machine
// registry write — registry-level changes aren't visible to
// subsequent WithExec processes (which inherit the engine-provided
// env, not a freshly-resolved Machine env).
func (m *Bookmarks) flutterWindowsBase() *dagger.Container {
	const installFlutter = `$ProgressPreference = 'SilentlyContinue'; ` +
		`Invoke-WebRequest -Uri '` + flutterWindowsZipURL + `' -OutFile C:\flutter.zip; ` +
		`Expand-Archive -Path C:\flutter.zip -DestinationPath C:\; ` +
		`Remove-Item C:\flutter.zip`

	return m.windowsBase().
		WithExec([]string{"powershell", "-NoProfile", "-Command", installFlutter}).
		WithEnvVariable(
			"PATH",
			`C:\flutter\bin;${PATH}`,
			dagger.ContainerWithEnvVariableOpts{Expand: true},
		).
		WithExec([]string{"powershell", "-NoProfile", "-Command", "flutter --version"}).
		// Same target-pruning as the Linux base — only enable the
		// platform we actually build for in this container.
		WithExec([]string{
			"powershell", "-NoProfile", "-Command",
			"flutter config " +
				"--no-enable-android " +
				"--no-enable-ios " +
				"--no-enable-web " +
				"--no-enable-fuchsia " +
				"--no-enable-linux-desktop " +
				"--no-enable-macos-desktop " +
				"--enable-windows-desktop",
		})
}

// BuildWindows produces a release Flutter Windows desktop bundle.
//
// Source is mounted at C:\src and copied to C:\work for the build.
// The copy is the documented workaround for the Windows-container
// alias-mount symlink failure (see tauu/flutter-windows-builder):
// plugin symlink creation under `windows\flutter\ephemeral\
// .plugin_symlinks` fails when the working directory is an alias
// mount. The non-mount path sidesteps the restriction.
func (m *Bookmarks) BuildWindows(
	ctx context.Context,
	// +ignore=[".git", ".dart_tool", "build", "coverage", "linux/flutter/ephemeral", "windows/flutter/ephemeral", "macos/Flutter/ephemeral", "macos/Pods", "ios/Pods", ".dagger", "dagger.json", "client-creds.json", "_bmad", "_bmad-output", ".idea", ".opencode", ".claude", "*.log"]
	source *dagger.Directory,
	// +optional
	oauthClientId *dagger.Secret,
	// +optional
	oauthClientSecret *dagger.Secret,
) (*dagger.Directory, error) {
	const buildScript = `$ProgressPreference = 'SilentlyContinue'; ` +
		`$VerbosePreference = 'SilentlyContinue'; ` +
		`New-Item -ItemType Directory -Force -Path C:\work | Out-Null; ` +
		`Copy-Item C:\src\* C:\work\ -Recurse -Force; ` +
		`Set-Location C:\work; ` +
		`flutter clean; ` +
		`flutter pub get; ` +
		`flutter build windows --release ` +
		`--dart-define=BOOKMARKS_OAUTH_CLIENT_ID=$env:BOOKMARKS_OAUTH_CLIENT_ID ` +
		`--dart-define=BOOKMARKS_OAUTH_CLIENT_SECRET=$env:BOOKMARKS_OAUTH_CLIENT_SECRET`

	c := m.flutterWindowsBase().WithMountedDirectory(`C:\src`, source)
	c = withOAuthSecrets(c, oauthClientId, oauthClientSecret)
	c, err := c.WithExec([]string{"powershell", "-NoProfile", "-Command", buildScript}).Sync(ctx)
	if err != nil {
		return nil, err
	}
	return c.Directory(`C:\work\build\windows\x64\runner\Release`), nil
}

// withOAuthSecrets attaches the OAuth credentials as env-var-bound
// secrets when provided. Dagger's secret scrubber redacts the values
// from trace output, so it's safe to surface them via `${VAR}`
// interpolation inside the shell exec.
func withOAuthSecrets(c *dagger.Container, id, secret *dagger.Secret) *dagger.Container {
	if id != nil {
		c = c.WithSecretVariable("BOOKMARKS_OAUTH_CLIENT_ID", id)
	}
	if secret != nil {
		c = c.WithSecretVariable("BOOKMARKS_OAUTH_CLIENT_SECRET", secret)
	}
	return c
}
