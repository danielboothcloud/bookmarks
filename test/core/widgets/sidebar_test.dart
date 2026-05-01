import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/core/router/app_router.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/sidebar.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/folders/application/folder_notifier.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart' show Folder;
import 'package:bookmarks/features/folders/presentation/widgets/folder_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBookmarkRepository implements IBookmarkRepository {
  @override
  Stream<List<Bookmark>> watchAll() => Stream.value(const <Bookmark>[]);

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(StorageError('not found'));

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      Ok<Bookmark, AppError>(bookmark);

  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Ok<void, AppError>(null);
}

class _RecordingFolderNotifier extends FolderNotifier {
  int addCalls = 0;
  String? lastAddParentId;
  String? returnId = 'fake-new-id';
  final List<List<String?>> moveCalls = <List<String?>>[];

  @override
  Future<void> build() async {}

  @override
  Future<String?> addFolder({String? parentId}) async {
    addCalls += 1;
    lastAddParentId = parentId;
    return returnId;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {}

  @override
  Future<void> moveFolder(String folderId, String? newParentId) async {
    moveCalls.add([folderId, newParentId]);
  }
}

Widget _buildApp({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.build(),
      routerConfig: buildRouter(),
    ),
  );
}

ProviderContainer _container({
  Stream<List<Folder>>? folderStream,
  FolderNotifier Function()? notifierFactory,
}) {
  return ProviderContainer(overrides: [
    bookmarkRepositoryProvider.overrideWithValue(_FakeBookmarkRepository()),
    watchFoldersProvider
        .overrideWith((ref) => folderStream ?? const Stream<List<Folder>>.empty()),
    folderNotifierProvider.overrideWith(
        notifierFactory ?? _RecordingFolderNotifier.new),
  ]);
}

void main() {
  testWidgets(
      'FOLDERS section header and + IconButton render in expanded mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    expect(find.text('FOLDERS'), findsOneWidget);
    expect(find.byTooltip('New folder'), findsOneWidget);
  });

  testWidgets('FOLDERS section is hidden in collapsed (icon-only) mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 600));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(sidebar.collapsed, isTrue);
    expect(find.text('FOLDERS'), findsNothing);
    expect(find.byType(FolderTree), findsNothing);
  });

  testWidgets('+ button calls folderNotifier.addFolder() exactly once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    final notifier = container.read(folderNotifierProvider.notifier)
        as _RecordingFolderNotifier;
    expect(notifier.addCalls, 0);

    await tester.tap(find.byTooltip('New folder'));
    await tester.pump();
    await tester.pump();

    expect(notifier.addCalls, 1);
  });

  testWidgets(
      '+ button sets pendingFolderEditIdProvider to the new id when addFolder '
      'returns non-null', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    expect(container.read(pendingFolderEditIdProvider), isNull);

    await tester.tap(find.byTooltip('New folder'));
    // Two pumps: one to settle the addFolder Future microtask, another for
    // the pending-edit state propagation.
    await tester.pump();
    await tester.pump();

    expect(container.read(pendingFolderEditIdProvider), 'fake-new-id');
  });

  testWidgets(
      '+ button does NOT set pending edit id when addFolder returns null',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    _RecordingFolderNotifier factory() =>
        _RecordingFolderNotifier()..returnId = null;
    final container = _container(notifierFactory: factory);
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pump();
    await tester.pump();

    expect(container.read(pendingFolderEditIdProvider), isNull);
  });

  testWidgets(
      'Existing top-level navrail items (All Bookmarks, Folders, Tags, '
      'Settings) still render unchanged', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    expect(find.text('All Bookmarks'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  // ------------------------------------------------------------------
  // Story 2.2: selection-aware +, root-drop target, navrail clears
  // ------------------------------------------------------------------

  testWidgets(
      '+ with no folder selected calls addFolder(parentId: null)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    expect(container.read(selectedFolderIdProvider), isNull);

    await tester.tap(find.byTooltip('New folder'));
    await tester.pump();
    await tester.pump();

    final notifier = container.read(folderNotifierProvider.notifier)
        as _RecordingFolderNotifier;
    expect(notifier.addCalls, 1);
    expect(notifier.lastAddParentId, isNull);
  });

  testWidgets(
      '+ with a folder selected calls addFolder(parentId: <selectedId>)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    container.read(selectedFolderIdProvider.notifier).select('sel-1');

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pump();
    await tester.pump();

    final notifier = container.read(folderNotifierProvider.notifier)
        as _RecordingFolderNotifier;
    expect(notifier.addCalls, 1);
    expect(notifier.lastAddParentId, 'sel-1');
  });

  testWidgets(
      'DragTarget on FOLDERS section header accepts a drop and calls '
      'moveFolder(draggedId, null)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    // The first DragTarget<String> in the sidebar tree is the section header
    // wrapper (the FolderTree's per-row targets only exist when folders are
    // present; here `watchFoldersProvider` emits nothing -> empty tree, so
    // the only DragTarget<String> is the header).
    final targets = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .toList();
    expect(targets, isNotEmpty);
    final headerTarget = targets.first;

    headerTarget.onAcceptWithDetails!(
      DragTargetDetails<String>(
        data: 'drag-id',
        offset: Offset.zero,
      ),
    );
    await tester.pump();

    final notifier = container.read(folderNotifierProvider.notifier)
        as _RecordingFolderNotifier;
    expect(notifier.moveCalls, [
      ['drag-id', null]
    ]);
  });

  testWidgets(
      'Folders navrail tap clears selectedFolderIdProvider',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    container.read(selectedFolderIdProvider.notifier).select('sel-1');

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    expect(container.read(selectedFolderIdProvider), 'sel-1');

    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();

    expect(container.read(selectedFolderIdProvider), isNull,
        reason:
            'Folders navrail tap is the explicit deselection path (AC5)');
  });

  testWidgets(
      'Other navrail taps (All Bookmarks, Tags, Settings) DO NOT clear '
      'selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final container = _container();
    addTearDown(container.dispose);

    container.read(selectedFolderIdProvider.notifier).select('sel-1');

    await tester.pumpWidget(_buildApp(container: container));
    await tester.pump();

    await tester.tap(find.text('All Bookmarks'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFolderIdProvider), 'sel-1',
        reason: 'All Bookmarks tap must leave folder selection intact');

    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFolderIdProvider), 'sel-1',
        reason: 'Tags tap must leave folder selection intact');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFolderIdProvider), 'sel-1',
        reason: 'Settings tap must leave folder selection intact');
  });
}
