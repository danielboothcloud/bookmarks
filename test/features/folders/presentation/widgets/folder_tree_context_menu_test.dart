import 'dart:async';

import 'package:bookmarks/features/folders/application/folder_notifier.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/folders/presentation/widgets/folder_tree.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recording notifier for the context-menu tests.
///
/// Mirrors the recording-notifier pattern in `folder_tree_test.dart`, but the
/// `addFolder` override also replays the real [FolderNotifier]'s auto-expand
/// side-effect (folder_notifier.dart line 50: `expandedFolderIdsProvider.expand(parentId)`)
/// so the auto-expand contract test can assert against this notifier without
/// pulling in a fake repository.
class _RecordingFolderNotifier extends FolderNotifier {
  int addCalls = 0;
  String? lastAddParentId;
  String nextNewId = 'fake-new-id';
  final List<String> deleteCascadeCalls = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<String?> addFolder({String? parentId}) async {
    addCalls += 1;
    lastAddParentId = parentId;
    if (parentId != null) {
      ref.read(expandedFolderIdsProvider.notifier).expand(parentId);
    }
    return nextNewId;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    // No-op for context-menu tests -- rename dispatch is observable via the
    // pendingFolderEditIdProvider transition.
  }

  @override
  Future<void> deleteFolderCascade(String rootId) async {
    deleteCascadeCalls.add(rootId);
  }
}

Folder _f(
  String id, {
  required String name,
  String? parentId,
  int createdAt = 1000,
}) =>
    Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    );

({ProviderContainer container, StreamController<List<Folder>> stream})
    _setup() {
  final stream = StreamController<List<Folder>>.broadcast();
  addTearDown(stream.close);
  final container = ProviderContainer(overrides: [
    watchFoldersProvider.overrideWith((ref) => stream.stream),
    folderNotifierProvider.overrideWith(_RecordingFolderNotifier.new),
  ]);
  addTearDown(container.dispose);
  return (container: container, stream: stream);
}

_RecordingFolderNotifier _readNotifier(ProviderContainer c) =>
    c.read(folderNotifierProvider.notifier) as _RecordingFolderNotifier;

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: FolderTree()),
    ),
  );
}

/// Returns the secondary-tap GestureDetector for the folder row containing
/// [text]. There are multiple GestureDetectors per row (chevron, double-tap
/// surface, context-menu wrapper); the one that owns the right-click is
/// uniquely identified by `onSecondaryTapDown != null`.
GestureDetector _secondaryGestureFor(WidgetTester tester, String folderName) {
  return tester.widget<GestureDetector>(
    find
        .ancestor(
          of: find.text(folderName),
          matching: find.byWidgetPredicate(
            (w) => w is GestureDetector && w.onSecondaryTapDown != null,
          ),
        )
        .first,
  );
}

/// Synthesises a [TapDownDetails] at the requested local offset.
TapDownDetails _tapAt(Offset offset) =>
    TapDownDetails(localPosition: offset, kind: PointerDeviceKind.mouse);

void main() {
  testWidgets(
      'Right-clicking a folder row opens a menu with three items: '
      'Rename, New subfolder, Delete (in order)', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(find.byType(MenuItemButton), findsNothing,
        reason: 'menu starts closed');

    _secondaryGestureFor(tester, 'Personal').onSecondaryTapDown!(
      _tapAt(const Offset(40, 8)),
    );
    await tester.pump();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'New subfolder'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Delete'), findsOneWidget);

    // Order: Rename appears above Delete in the overlay.
    final renameTop =
        tester.getTopLeft(find.widgetWithText(MenuItemButton, 'Rename')).dy;
    final newSubTop = tester
        .getTopLeft(find.widgetWithText(MenuItemButton, 'New subfolder'))
        .dy;
    final deleteTop =
        tester.getTopLeft(find.widgetWithText(MenuItemButton, 'Delete')).dy;
    expect(renameTop, lessThan(newSubTop));
    expect(newSubTop, lessThan(deleteTop));
  });

  testWidgets(
      'Tapping Rename invokes pendingFolderEditIdProvider.start with '
      'folder.id and closes the menu', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    await tester.tap(find.widgetWithText(MenuItemButton, 'Rename'));
    await tester.pump();

    expect(s.container.read(pendingFolderEditIdProvider), 'a');
    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsNothing,
        reason: 'menu must close after a menu item is selected');
  });

  testWidgets(
      'Tapping New subfolder calls addFolder(parentId: folder.id), starts '
      'rename on the new id, and closes the menu', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    await tester.tap(find.widgetWithText(MenuItemButton, 'New subfolder'));
    // addFolder is async -- pump once to settle the menu close, then a
    // microtask drain so the awaited Future resolves before assertions.
    await tester.pump();
    await tester.pumpAndSettle();

    final notifier = _readNotifier(s.container);
    expect(notifier.addCalls, 1);
    expect(notifier.lastAddParentId, 'a',
        reason: 'parent is the right-clicked folder, not the selected one');
    expect(s.container.read(pendingFolderEditIdProvider), 'fake-new-id',
        reason: 'new child enters rename mode immediately');
  });

  testWidgets(
      'New subfolder auto-expands the parent so the new child row is '
      'visible (mirrors FolderNotifier.addFolder side-effect)', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(s.container.read(expandedFolderIdsProvider), isEmpty);

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    await tester.tap(find.widgetWithText(MenuItemButton, 'New subfolder'));
    await tester.pumpAndSettle();

    expect(s.container.read(expandedFolderIdsProvider), contains('a'));
  });

  testWidgets(
      'Tapping Delete invokes pendingFolderDeleteIdProvider.prompt and '
      'does NOT call deleteFolderCascade until confirmed', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
    await tester.pump();

    expect(s.container.read(pendingFolderDeleteIdProvider), 'a',
        reason: 'menu Delete prompts the inline confirmation');
    expect(_readNotifier(s.container).deleteCascadeCalls, isEmpty,
        reason:
            'cascade must NOT execute until the inline confirmation is accepted');
  });

  testWidgets('Outside-click closes the menu', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget);

    // Tap a region outside the menu. The Scaffold body extends beyond the
    // tiny folder row; tap near the bottom-right where neither the row nor
    // the menu overlay live.
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsNothing);
  });

  testWidgets('Right-click does NOT change selectedFolderIdProvider',
      (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(s.container.read(selectedFolderIdProvider), isNull);

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(s.container.read(selectedFolderIdProvider), isNull,
        reason: 'right-click is non-selecting (AC1)');
  });

  testWidgets(
      'Right-click does NOT navigate / does not require a shell '
      '(secondary-tap handler must not call goBranch)', (tester) async {
    // Rebuild a wrap WITHOUT a StatefulShellRoute -- if the secondary-tap
    // handler ever called shell.goBranch it would throw on the missing shell.
    // The fact that this test passes with no exceptions documents that
    // contract.
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget);
  });

  testWidgets(
      'Right-click on the second folder while the first is in rename mode: '
      'the second folder still gets a menu (the first folder\'s rename '
      'commit happens via the TextField onTapOutside path, exercised in '
      'folder_tree_test.dart -- this test asserts the menu coexists)',
      (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'Alpha', createdAt: 1000),
      _f('b', name: 'Beta', createdAt: 2000),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Alpha is in edit mode -> TextField present; Beta is in display mode
    // and therefore wrapped in _FolderContextMenu.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    _secondaryGestureFor(tester, 'Beta')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget,
        reason: 'Beta\'s context menu must open even while Alpha is renaming');
  });

  testWidgets(
      'Right-click on a row already showing a delete confirmation re-opens '
      'menu normally; subsequent Delete tap re-prompts (idempotent)',
      (tester) async {
    final s = _setup();

    s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(find.text("Delete 'Personal' and all its contents?"),
        findsOneWidget);

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(find.widgetWithText(MenuItemButton, 'Delete'), findsOneWidget);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
    await tester.pump();

    expect(s.container.read(pendingFolderDeleteIdProvider), 'a',
        reason: 're-prompting the same id is idempotent (no toggle off)');
  });

  testWidgets(
      'Esc closes the menu when overlay focus is inside the menu items '
      '(MenuAnchor default Esc handling)', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget);

    // Focus the first menu item so Esc is routed to MenuAnchor's overlay
    // (in production a keyboard-driven open would auto-focus; mouse-driven
    // open does not, hence the explicit focus claim here).
    final renameItemCtx =
        tester.element(find.widgetWithText(MenuItemButton, 'Rename'));
    FocusScope.of(renameItemCtx).requestFocus(
      Focus.of(renameItemCtx).children.isNotEmpty
          ? Focus.of(renameItemCtx).children.first
          : Focus.of(renameItemCtx),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsNothing);
  });
}
