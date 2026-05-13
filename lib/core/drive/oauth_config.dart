/// OAuth2 configuration for Google Drive desktop client.
///
/// SETUP — required before this app builds successfully on a fresh
/// checkout:
///
/// 1. Open https://console.cloud.google.com/projectcreate and create
///    a project (e.g. "bookmarks-app").
/// 2. In APIs & Services -> Library, enable "Google Drive API".
/// 3. In APIs & Services -> OAuth consent screen, configure:
///      - User type: External (or Internal if you only ever sign in
///        with a Workspace account — External is the safe default).
///      - Scopes: add `https://www.googleapis.com/auth/drive.appdata`
///        ONLY. Do not add drive, drive.file, drive.readonly, or
///        userinfo scopes — the architecture is explicit that we
///        request the minimum.
///      - Test users: add your own Google account while the consent
///        screen is in "Testing" mode (avoids the 100-user external
///        review threshold for personal use).
/// 4. In APIs & Services -> Credentials, click "Create credentials"
///    -> "OAuth client ID" -> Application type: "Desktop app".
/// 5. Run the app with --dart-define=BOOKMARKS_OAUTH_CLIENT_ID=`<id>`
///    --dart-define=BOOKMARKS_OAUTH_CLIENT_SECRET=`<secret>`.
///
/// The Client Secret IS NOT a real secret for Desktop OAuth2 public
/// clients — Google's own docs and the architecture decision confirm
/// this. PKCE is what protects the flow. Google's token endpoint
/// requires `client_secret` as a parameter for desktop clients, but
/// its absence of secrecy is by design.
///
/// On a fresh checkout WITHOUT these defines set, the app builds and
/// tests pass (empty defaults are harmless — tests use a faked
/// `DriveAuthService` and never invoke the real `connect()`). At
/// runtime, hitting the "Connect Google Drive" button with an empty
/// client id will surface a clear failure via [DriveAuthState.failed].
library;

const String kOAuthClientId = String.fromEnvironment(
  'BOOKMARKS_OAUTH_CLIENT_ID',
  defaultValue: '',
);

const String kOAuthClientSecret = String.fromEnvironment(
  'BOOKMARKS_OAUTH_CLIENT_SECRET',
  defaultValue: '',
);

/// Drive.appdata scope — the ONLY scope we ever request.
const String kDriveAppDataScope =
    'https://www.googleapis.com/auth/drive.appdata';

/// The remote bookmarks file in the user's Drive app-data folder.
const String kBookmarksFileName = 'bookmarks.json';

/// The single canonical `spaces` filter value for app-data folder
/// queries. Drive's `appDataFolder` is a virtual folder ID; queries
/// must use `spaces: 'appDataFolder'`, not a parent-id filter.
const String kAppDataSpace = 'appDataFolder';

/// Google OAuth2 authorization endpoint.
const String kAuthEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';

/// Google OAuth2 token-exchange endpoint.
const String kTokenEndpoint = 'https://oauth2.googleapis.com/token';
