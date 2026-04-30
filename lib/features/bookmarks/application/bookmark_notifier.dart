// TODO(story-1.2): replace with @riverpod AsyncNotifier once codegen unblocked.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/result.dart';
import '../domain/bookmark.dart';
import 'bookmark_providers.dart';

class BookmarkNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> addBookmark({
    required String url,
    String? title,
    String? folderId,
  }) async {
    final trimmedUrl = url.trim();
    final trimmedTitle = (title ?? '').trim();
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: _uuid.v4(),
      url: trimmedUrl,
      title: trimmedTitle.isEmpty ? trimmedUrl : trimmedTitle,
      folderId: folderId,
      createdAt: now,
      updatedAt: now,
    );

    state = const AsyncValue<void>.loading();
    final result = await ref.read(bookmarkRepositoryProvider).save(bookmark);
    switch (result) {
      case Ok():
        state = const AsyncValue<void>.data(null);
        // Fire-and-forget metadata fetch (NFR4): runs after save resolves so
        // the UI is already updated via the StreamProvider emission. Failures
        // are swallowed inside _fetchMetadata -- they must NOT pollute this
        // notifier's AsyncValue<void>, which represents the SAVE mutation
        // (Story 1.2's _SaveErrorBanner reads bookmarkNotifierProvider.hasError).
        unawaited(_fetchMetadata(bookmark));
      case Err(:final error):
        state = AsyncValue<void>.error(error, StackTrace.current);
    }
  }

  Future<void> _fetchMetadata(Bookmark bookmark) async {
    // Mark in-flight synchronously (before any await) so the spinner appears
    // on the next frame.
    ref.read(metadataFetchInFlightProvider.notifier).start(bookmark.id);
    try {
      final meta = await ref
          .read(metadataFetchServiceProvider)
          .fetch(bookmark.url);

      // After the await, the notifier may have been disposed (app shutdown,
      // hot reload, container teardown). Guard every subsequent ref.read.
      if (!ref.mounted) return;

      // Only overwrite the title if the user did not provide a custom one.
      // `addBookmark` stores `title=url` when the user supplied no title;
      // anything else is the user's deliberate choice and we must preserve it.
      final fetchedTitle = meta.title;
      final fetchedFavicon = meta.faviconBase64;
      final nextTitle =
          (fetchedTitle != null && bookmark.title == bookmark.url)
              ? fetchedTitle
              : bookmark.title;
      final nextFavicon = fetchedFavicon ?? bookmark.faviconBase64;

      final titleChanged = nextTitle != bookmark.title;
      final faviconChanged = nextFavicon != bookmark.faviconBase64;
      if (!titleChanged && !faviconChanged) return;

      final updated = bookmark.copyWith(
        title: nextTitle,
        faviconBase64: nextFavicon,
        updatedAt: DateTime.now(),
      );
      // Reuse the existing upsert -- no new repository method needed.
      final saveResult =
          await ref.read(bookmarkRepositoryProvider).save(updated);
      switch (saveResult) {
        case Ok():
          break;
        case Err(:final error):
          _logDebug('post-fetch save failed: $error');
      }
    } catch (e) {
      // Swallow any unexpected fire-and-forget failure (incl. ref-after-dispose
      // edge cases that slip through ref.mounted). AC4 is silent fallback;
      // the in-flight cleanup below restores the placeholder.
      _logDebug('metadata fetch orchestration failed: $e');
    } finally {
      if (ref.mounted) {
        ref.read(metadataFetchInFlightProvider.notifier).finish(bookmark.id);
      }
    }
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('BookmarkNotifier: $message');
    }
  }
}

final bookmarkNotifierProvider =
    AsyncNotifierProvider<BookmarkNotifier, void>(BookmarkNotifier.new);
