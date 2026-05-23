import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bookmarks/application/bookmark_providers.dart';
import '../../folders/application/folder_providers.dart';
import '../data/bookmark_import_service.dart';
import '../data/browser_bookmarks_html_parser.dart';
import '../data/file_picker_wrapper.dart';
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

/// State machine driving the Settings → Import section. See
/// [ImportNotifier] for the transition rules.
final importNotifierProvider =
    AsyncNotifierProvider<ImportNotifier, ImportState>(
  ImportNotifier.new,
);
