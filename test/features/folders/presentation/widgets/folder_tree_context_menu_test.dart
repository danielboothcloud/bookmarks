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
  final List<({String id, String name})> renameCalls =
      <({String id, String name})>[];

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
    renameCalls.add((id: id, name: newName));
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
      'Secondary-tap handler does NOT reach into StatefulNavigationShell '
      '(no shell mounted, no exception, no selection change, no branch swap)',
      (tester) async {
    // Wrap WITHOUT a StatefulShellRoute. If the secondary-tap handler ever
    // called shell.goBranch (or otherwise depended on inherited shell state)
    // it would throw on the missing shell -- so the no-exception assertion
    // doubles as a structural guard against accidental shell coupling.
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    final selectedBefore = s.container.read(selectedFolderIdProvider);

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason:
            'no shell-coupling: secondary-tap must not call StatefulNavigationShell.maybeOf or goBranch');
    expect(s.container.read(selectedFolderIdProvider), selectedBefore,
        reason: 'right-click is non-selecting (selection drives navigation)');
    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget,
        reason: 'menu still opens cleanly without a shell');
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
      'Real secondary-button pointer event on Beta\'s row dismisses Alpha\'s '
      'in-flight rename via TextField.onTapOutside (AC6 commit-on-right-click)',
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

    // Type a fresh value into Alpha's rename TextField so we can observe the
    // commit on tap-outside.
    await tester.enterText(find.byType(TextField), 'Alpha-edited');
    await tester.pump();

    // Drive a *real* secondary-button gesture on Beta's row. Calling the
    // GestureDetector's onSecondaryTapDown directly (the pattern used in
    // sibling tests) bypasses the gesture arena -- which means the
    // TextField's TapRegion doesn't see a pointer-down event, and
    // onTapOutside never fires. A real PointerDownEvent via startGesture is
    // the only way to exercise the AC6 commit path end-to-end.
    final betaCenter = tester.getCenter(find.text('Beta'));
    final gesture = await tester.startGesture(
      betaCenter,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final notifier = _readNotifier(s.container);
    expect(notifier.renameCalls, isNotEmpty,
        reason: 'TextField.onTapOutside must commit Alpha\'s pending edit');
    expect(notifier.renameCalls.last,
        (id: 'a', name: 'Alpha-edited'),
        reason: 'commit carries the edited value, not the original');
    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget,
        reason: 'Beta\'s menu opens on the same gesture that committed Alpha');
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
      'Right-click + Delete on folder B while folder A is mid-confirmation '
      'migrates the confirmation from A to B (AC7 single-id semantics, '
      'second branch)', (tester) async {
    final s = _setup();

    s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'Alpha', createdAt: 1000),
      _f('b', name: 'Beta', createdAt: 2000),
    ]);
    await tester.pump();

    expect(find.text("Delete 'Alpha' and all its contents?"), findsOneWidget,
        reason: 'Alpha\'s confirmation is the starting state');

    _secondaryGestureFor(tester, 'Beta')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pump();

    await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(s.container.read(pendingFolderDeleteIdProvider), 'b',
        reason: 'Notifier single-id state migrates from Alpha to Beta');
    expect(find.text("Delete 'Alpha' and all its contents?"), findsNothing,
        reason: 'Alpha\'s confirmation collapses on the migration');
    expect(find.text("Delete 'Beta' and all its contents?"), findsOneWidget,
        reason: 'Beta\'s confirmation renders in its place');
  });

  testWidgets(
      'Esc closes the menu when opened via mouse right-click (focus stays on '
      'the row anchor; CallbackShortcuts on the anchor catches Esc -- '
      'mirrors folder_picker.dart)', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    _secondaryGestureFor(tester, 'Personal')
        .onSecondaryTapDown!(_tapAt(const Offset(40, 8)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsOneWidget);

    // No explicit focus claim into the menu items -- in production a
    // mouse-opened menu leaves focus on the row's _rowFocusNode. The Esc
    // path must work from there, otherwise AC5 is broken in the dominant
    // open-style.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Rename'), findsNothing);
  });
}
