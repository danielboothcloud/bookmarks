import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bookmarks/application/bookmark_providers.dart';
import '../../folders/application/folder_providers.dart';
import '../data/bookmark_import_service.dart';
import '../data/browser_bookmarks_html_parser.dart';
import '../data/file_picker_wrapper.dart';
import '../data/import_favicon_backfill_service.dart';
import '../domain/import_state.dart';
import 'import_notifier.dart';

/// Pure parser; no state. Held as a Provider so tests can swap in a
/// fake-throwing variant if they ever need to exercise the
/// parse-failure path (the production parser is `noexcept` by design).
final browserBookmarksHtmlParserProvider =
    Provider<BrowserBookmarksHtmlParser>((_) {
  return const BrowserBookmarksHtmlParser();
});

/// Side-effecting writer; depends on the bookmark + folder
/// repositories. Reads (rather than watches) the repos because the
/// import is a one-shot operation — re-binding on repo identity
/// changes would needlessly rebuild the service mid-import.
final bookmarkImportServiceProvider =
    Provider<BookmarkImportService>((ref) {
  return BookmarkImportService(
    folderRepo: ref.read(folderRepositoryProvider),
    bookmarkRepo: ref.read(bookmarkRepositoryProvider),
  );
});

/// The OS file picker seam. Tests override this with
/// `FilePickerWrapper.fake(...)` so the integration tests don't
/// require a real Cocoa file dialog. Mirrors the pattern of
/// `httpClientProvider` / `flutterSecureStorageProvider` in
/// `lib/core/drive/drive_auth_providers.dart`.
final filePickerProvider = Provider<FilePickerWrapper>((_) {
  return FilePickerWrapper.real();
});

/// Background favicon backfill service (Story 5.2). Wraps the
/// single-URL `MetadataFetchService` with a bounded worker pool +
/// cancellation. `ref.read` (not `ref.watch`) on the deps because the
/// service is one-shot and re-binding on repo identity changes would
/// invalidate its in-memory cancellation token mid-run.
///
/// `onDispose` cancels any in-flight backfill so AC10 ("no save attempt
/// against a disposed repository") holds when the container tears down
/// (hot reload, app shutdown, test teardown). Workers see the
/// cancellation token flip after their next await and return.
final importFaviconBackfillServiceProvider =
    Provider<ImportFaviconBackfillService>((ref) {
  final service = ImportFaviconBackfillService(
    bookmarkRepo: ref.read(bookmarkRepositoryProvider),
    metadataFetchService: ref.read(metadataFetchServiceProvider),
  );
  ref.onDispose(service.cancel);
  return service;
});

/// State machine driving the Settings → Import section. See
/// [ImportNotifier] for the transition rules.
final importNotifierProvider =
    AsyncNotifierProvider<ImportNotifier, ImportState>(
  ImportNotifier.new,
);
