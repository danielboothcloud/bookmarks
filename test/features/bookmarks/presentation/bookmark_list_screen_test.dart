import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/data/metadata_fetch_service.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/url_metadata.dart';
import 'package:bookmarks/features/bookmarks/presentation/bookmark_list_screen.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_list_item.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/inline_add_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeRepo implements IBookmarkRepository {
  _FakeRepo(this._controller);

  final StreamController<List<Bookmark>> _controller;
  final List<Bookmark> _items = [];
  Result<Bookmark, AppError> Function(Bookmark)? saveResult;
  Result<void, AppError> Function(String)? deleteResult;
  final List<String> deletedIds = <String>[];

  @override
  Stream<List<Bookmark>> watchAll() => _controller.stream;

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(NotFoundError());

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    final result = (saveResult ?? Ok<Bookmark, AppError>.new)(bookmark);
    if (result is Ok<Bookmark, AppError>) {
      _items.insert(0, bookmark);
      _controller.add(List.unmodifiable(_items));
    }
    return result;
  }

  @override
  Future<Result<void, AppError>> delete(String id) async {
    deletedIds.add(id);
    final result =
        deleteResult?.call(id) ?? const Ok<void, AppError>(null);
    if (result is Ok<void, AppError>) {
      _items.removeWhere((b) => b.id == id);
      _controller.add(List.unmodifiable(_items));
    }
    return result;
  }
}

Bookmark _bm(String id, {String? title, DateTime? createdAt}) {
  final now = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1000);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    title: title ?? 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
  );
}

/// Records every launchUrl call so the double-tap test can assert that the
/// list item routed through openExternal with the expected URL/mode.
class _RecordingLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];
  final List<LaunchOptions> launches = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launches.add(options);
    return true;
  }
}

/// No-op metadata fetch service: returns empty UrlMetadata for every URL.
/// Keeps the post-save fire-and-forget path off the real network in tests.
class _NoopMetadataFetchService implements MetadataFetchService {
  @override
  Future<UrlMetadata> fetch(String url) async => const UrlMetadata();

  @override
  void close() {}
}

Widget _wrap(IBookmarkRepository repo) {
  return ProviderScope(
    overrides: [
      bookmarkRepositoryProvider.overrideWithValue(repo),
      metadataFetchServiceProvider
          .overrideWithValue(_NoopMetadataFetchService()),
    ],
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(body: BookmarkListScreen()),
    ),
  );
}

void main() {
  testWidgets('empty stream shows EmptyState.noBookmarks (AC4 negative)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(find.byType(BookmarkListItem), findsNothing);
  });

  testWidgets(
      'EmptyState.noBookmarks renders when the stream transitions from a '
      'single bookmark to empty (Story 1.5 AC4: deleting the last bookmark)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    // Start with one bookmark visible.
    controller.add([_bm('only')]);
    await tester.pumpAndSettle();
    expect(find.byType(BookmarkListItem), findsOneWidget);
    expect(find.text('No bookmarks yet'), findsNothing);

    // Drift's watchAll() re-emits when the deleted row is removed; simulate
    // the post-delete stream emission directly (per Story 1.5 task 9 spec).
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsNothing);
    expect(find.text('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('non-empty stream renders BookmarkListItem rows (AC4)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    final newer =
        _bm('newer', createdAt: DateTime.fromMillisecondsSinceEpoch(2000));
    final older =
        _bm('older', createdAt: DateTime.fromMillisecondsSinceEpoch(1000));

    await tester.pumpWidget(_wrap(repo));
    // Repository orders by createdAt desc — emit in that order.
    controller.add([newer, older]);
    await tester.pumpAndSettle();

    final items = tester
        .widgetList<BookmarkListItem>(find.byType(BookmarkListItem))
        .toList();
    expect(items.length, 2);
    expect(items.first.bookmark.id, 'newer');
    expect(items.last.bookmark.id, 'older');
  });

  testWidgets('addFormVisibleProvider true shows InlineAddForm above list (AC1)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('one')]);
    await tester.pumpAndSettle();
    expect(find.byType(InlineAddForm), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    expect(find.byType(InlineAddForm), findsOneWidget);
    final formY = tester.getTopLeft(find.byType(InlineAddForm)).dy;
    final listY = tester.getTopLeft(find.byType(BookmarkListItem).first).dy;
    expect(formY, lessThan(listY));
  });

  testWidgets('Esc while form visible flips provider false (AC3)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    // URL field auto-focuses; send Esc.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(container.read(addFormVisibleProvider), isFalse);
    expect(find.byType(InlineAddForm), findsNothing);
  });

  testWidgets(
      'Save with non-empty URL closes the form and the new bookmark appears (AC2)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    final urlField = find.widgetWithText(TextField, 'Paste a URL');
    await tester.enterText(urlField, 'https://example.com/new');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(InlineAddForm), findsNothing);
    expect(container.read(addFormVisibleProvider), isFalse);
    expect(find.byType(BookmarkListItem), findsOneWidget);
    final item = tester.widget<BookmarkListItem>(find.byType(BookmarkListItem));
    expect(item.bookmark.url, 'https://example.com/new');
  });

  testWidgets('save Err surfaces inline calm error banner (H1)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller)
      ..saveResult = (_) => const Err<Bookmark, AppError>(StorageError('boom'));
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Paste a URL'),
      'https://example.com/x',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save changes — try again."), findsOneWidget);
  });

  testWidgets(
      'BookmarkListItem renders FaviconWidget placeholder for bookmarks with '
      'no faviconBase64 (Story 1.3 regression)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('plain')]);
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkListItem), findsOneWidget);
    // Globe placeholder should render inside the FaviconWidget slot.
    expect(find.byIcon(Icons.public), findsOneWidget);
    // No spinner because nothing is in flight in this scenario.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('single-tap on a list item updates selectedBookmarkIdProvider '
      '(Story 1.4 AC1)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('one'), _bm('two')]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    expect(container.read(selectedBookmarkIdProvider), isNull);

    await tester.tap(find.byType(BookmarkListItem).first);
    // Single-tap fires after the double-tap recognizer's timeout when a
    // sibling onDoubleTap is registered. Pump past kDoubleTapTimeout.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(container.read(selectedBookmarkIdProvider), 'one');
  });

  testWidgets('double-tap on a list item launches the URL externally '
      '(Story 1.4 AC4)', (tester) async {
    final originalLauncher = UrlLauncherPlatform.instance;
    final recording = _RecordingLauncher();
    UrlLauncherPlatform.instance = recording;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('one')]);
    await tester.pumpAndSettle();

    final pos = tester.getCenter(find.byType(BookmarkListItem));
    await tester.tapAt(pos);
    // Stay well under kDoubleTapTimeout (300ms) so the gesture recogniser
    // forms a double-tap rather than two single-taps.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(pos);
    await tester.pumpAndSettle();

    expect(recording.launchedUrls, ['https://example.com/one']);
    expect(recording.launches.single.mode,
        PreferredLaunchMode.externalApplication);
  });

  testWidgets('selected list item gains a distinct surface tint (Story 1.4)',
      (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add([_bm('one')]);
    await tester.pumpAndSettle();

    // Capture the unselected Material colour first.
    final unselected = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BookmarkListItem),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(unselected.color, Colors.transparent);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(selectedBookmarkIdProvider.notifier).select('one');
    await tester.pumpAndSettle();

    final selected = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BookmarkListItem),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(selected.color, isNot(Colors.transparent),
        reason: 'selected item must be visually distinct from default');
  });

  testWidgets('URL field auto-focuses when form opens (AC1)', (tester) async {
    final controller = StreamController<List<Bookmark>>.broadcast();
    final repo = _FakeRepo(controller);
    addTearDown(controller.close);

    await tester.pumpWidget(_wrap(repo));
    controller.add(const <Bookmark>[]);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookmarkListScreen)),
    );
    container.read(addFormVisibleProvider.notifier).show();
    await tester.pumpAndSettle();

    final urlField = find.widgetWithText(TextField, 'Paste a URL');
    expect(urlField, findsOneWidget);
    final focusNode = (tester.widget<TextField>(urlField)).focusNode;
    expect(focusNode?.hasFocus, isTrue);
  });
}
