// TODO(story-1.2): convert to @riverpod once riverpod_generator is unblocked.
// Re-checked 2026-04-30 (story 1.3): still blocked by analyzer version
// conflict between drift_dev ^2.32.0 (needs analyzer 10/11/12) and custom_lint
// (needs analyzer 7/8). Track via Story 1.1 deferred follow-up.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart';
import '../data/bookmark_repository.dart';
import '../data/metadata_fetch_service.dart';
import '../domain/bookmark.dart';
import '../domain/i_bookmark_repository.dart';

final bookmarkRepositoryProvider = Provider<IBookmarkRepository>((ref) {
  return BookmarkRepository(ref.watch(appDatabaseProvider));
});

final watchBookmarksProvider = StreamProvider<List<Bookmark>>((ref) {
  return ref.watch(bookmarkRepositoryProvider).watchAll();
});

/// Provides the singleton MetadataFetchService. The underlying http.Client is
/// closed when the provider is disposed to avoid leaking file descriptors.
final metadataFetchServiceProvider = Provider<MetadataFetchService>((ref) {
  final service = MetadataFetchService();
  ref.onDispose(service.close);
  return service;
});

/// Tracks bookmark IDs for which a metadata fetch is currently in flight.
/// Consumed by FaviconWidget to render the loading spinner. In-memory only --
/// closing the app cancels any pending fetch and drops the in-flight set;
/// no automatic resume on relaunch (matches Story 5.2's "no auto retry").
class MetadataFetchInFlightNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void start(String bookmarkId) => state = {...state, bookmarkId};

  void finish(String bookmarkId) =>
      state = state.where((id) => id != bookmarkId).toSet();
}

final metadataFetchInFlightProvider =
    NotifierProvider<MetadataFetchInFlightNotifier, Set<String>>(
        MetadataFetchInFlightNotifier.new);

/// Controls visibility of the inline add form. Flipped by the global
/// `Cmd+N` AddBookmarkIntent in AppShell, watched by BookmarkListScreen.
class AddFormVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
}

final addFormVisibleProvider =
    NotifierProvider<AddFormVisibleNotifier, bool>(AddFormVisibleNotifier.new);

/// Holds the id of the bookmark currently shown in the detail pane. Storing
/// only the id (rather than the whole [Bookmark]) keeps the detail pane in
/// sync with mutations from elsewhere -- e.g. Story 1.3's metadata fetch
/// updating favicon/title -- by deriving the live bookmark from
/// [watchBookmarksProvider] inside [selectedBookmarkProvider].
class SelectedBookmarkIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
  void clear() => state = null;
}

final selectedBookmarkIdProvider =
    NotifierProvider<SelectedBookmarkIdNotifier, String?>(
        SelectedBookmarkIdNotifier.new);

/// The id of the bookmark currently showing its inline delete confirmation
/// (Story 1.5). Only ONE bookmark can be in this state at a time -- pressing
/// Delete on a different bookmark moves the confirmation to that one.
/// `null` means no confirmation is open. Kept separate from
/// [selectedBookmarkIdProvider] because selection ("which detail pane shows")
/// and pendingDelete ("which inline confirm is open") have different
/// lifecycles -- conflating them would create a tri-state harder to reason
/// about than two orthogonal flags.
class PendingDeleteIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void prompt(String id) => state = id;
  void clear() => state = null;
}

final pendingDeleteIdProvider =
    NotifierProvider<PendingDeleteIdNotifier, String?>(
        PendingDeleteIdNotifier.new);

/// The bookmark referenced by [selectedBookmarkIdProvider], joined against
/// the live list from [watchBookmarksProvider]. Returns null when:
///   - no selection is set,
///   - the list hasn't emitted yet, or
///   - the selected id is no longer in the list (e.g. deleted in Story 1.5).
/// Callers can treat null as "render the empty placeholder" (AC7).
final selectedBookmarkProvider = Provider<Bookmark?>((ref) {
  final id = ref.watch(selectedBookmarkIdProvider);
  if (id == null) return null;
  final list = ref.watch(watchBookmarksProvider).value;
  if (list == null) return null;
  for (final b in list) {
    if (b.id == id) return b;
  }
  return null;
});
