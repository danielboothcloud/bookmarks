import 'dart:async';

import 'package:bookmarks/features/folders/application/folder_notifier.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/folders/presentation/widgets/folder_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFolderNotifier extends FolderNotifier {
  int addCalls = 0;
  String? lastAddParentId;
  final List<List<String>> renameCalls = <List<String>>[];
  final List<List<String?>> moveCalls = <List<String?>>[];
  final List<String> deleteCascadeCalls = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<String?> addFolder({String? parentId}) async {
    addCalls += 1;
    lastAddParentId = parentId;
    return 'fake-new-id';
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    renameCalls.add([id, newName]);
  }

  @override
  Future<void> moveFolder(String folderId, String? newParentId) async {
    moveCalls.add([folderId, newParentId]);
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
  int? updatedAt,
}) =>
    Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt ?? createdAt),
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

Widget _wrap(ProviderContainer container, {Widget? body}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: body ?? const FolderTree()),
    ),
  );
}

void main() {
  testWidgets('Empty state: renders "No folders yet" and no FolderRow',
      (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add(<Folder>[]);
    await tester.pump();

    expect(find.text('No folders yet'), findsOneWidget);
    expect(find.byType(FolderRow), findsNothing);
  });

  testWidgets('Renders a single folder row showing the folder name',
      (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(find.byType(FolderRow), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('Order: rows appear in createdAt asc order', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'Older', createdAt: 1000),
      _f('b', name: 'Newer', createdAt: 2000),
    ]);
    await tester.pump();

    final rows = tester.widgetList<FolderRow>(find.byType(FolderRow)).toList();
    expect(rows.map((r) => r.folder.id).toList(), ['a', 'b']);
  });

  testWidgets('Display row by default: Text present, no TextField',
      (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(find.text('Personal'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
      'Edit row appears when pendingFolderEditIdProvider == folder.id; '
      'TextField holds folder name and selects all',
      (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tfFinder = find.byType(TextField);
    expect(tfFinder, findsOneWidget);
    final tf = tester.widget<TextField>(tfFinder);
    expect(tf.controller!.text, 'Personal');
    expect(tf.controller!.selection.baseOffset, 0);
    expect(tf.controller!.selection.extentOffset, 'Personal'.length);
  });

  testWidgets('Double-tap on folder name enters edit mode', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();

    expect(s.container.read(pendingFolderEditIdProvider), isNull);

    final detector = tester.widget<GestureDetector>(
      find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onDoubleTap != null),
    );
    detector.onDoubleTap!();
    await tester.pump();

    expect(s.container.read(pendingFolderEditIdProvider), 'a');
  });

  testWidgets(
      'Enter (onSubmitted) saves: notifier.renameFolder called and pending '
      'id cleared', (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(_readNotifier(s.container).renameCalls, [
      ['a', 'Renamed']
    ]);
    expect(s.container.read(pendingFolderEditIdProvider), isNull);
  });

  testWidgets(
      'Esc cancels: renameFolder NOT called, pending cleared, controller '
      'reset to original name', (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tfFinder = find.byType(TextField);
    final controller = tester.widget<TextField>(tfFinder).controller!;

    await tester.enterText(tfFinder, 'TypedButCancelled');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_readNotifier(s.container).renameCalls, isEmpty);
    expect(s.container.read(pendingFolderEditIdProvider), isNull);
    expect(controller.text, 'Personal');
  });

  testWidgets('onTapOutside saves on blur', (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.pump();

    final tf = tester.widget<TextField>(find.byType(TextField));
    tf.onTapOutside!(const PointerDownEvent(position: Offset(0, 250)));
    await tester.pump();

    expect(_readNotifier(s.container).renameCalls, [
      ['a', 'Renamed']
    ]);
  });

  testWidgets('Esc-then-tapOutside-race: renameFolder NOT called twice',
      (tester) async {
    final s = _setup();

    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tf = tester.widget<TextField>(find.byType(TextField));
    final tapOutside = tf.onTapOutside!;

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    tapOutside(const PointerDownEvent(position: Offset(0, 250)));
    await tester.pump();

    expect(_readNotifier(s.container).renameCalls, isEmpty,
        reason: 'Esc cancelled; the post-cancel tap-outside must not save');
  });

  testWidgets(
      'ValueKey(folder.id) preserves FolderRow State across stream '
      're-emissions when a new folder is inserted', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', createdAt: 1000),
      _f('b', name: 'B', createdAt: 2000),
    ]);
    await tester.pump();

    final stateA1 = tester.state(
      find.byWidgetPredicate(
          (w) => w is FolderRow && w.folder.id == 'a'),
    );
    final stateB1 = tester.state(
      find.byWidgetPredicate(
          (w) => w is FolderRow && w.folder.id == 'b'),
    );

    s.stream.add([
      _f('c', name: 'C', createdAt: 500),
      _f('a', name: 'A', createdAt: 1000),
      _f('b', name: 'B', createdAt: 2000),
    ]);
    await tester.pump();

    final stateA2 = tester.state(
      find.byWidgetPredicate(
          (w) => w is FolderRow && w.folder.id == 'a'),
    );
    final stateB2 = tester.state(
      find.byWidgetPredicate(
          (w) => w is FolderRow && w.folder.id == 'b'),
    );

    expect(identical(stateA1, stateA2), isTrue,
        reason: 'A row state must persist across stream re-emissions');
    expect(identical(stateB1, stateB2), isTrue,
        reason: 'B row state must persist across stream re-emissions');
  });

  // ------------------------------------------------------------------
  // Story 2.2: tree shape, chevron, drag, navigate
  // ------------------------------------------------------------------

  testWidgets(
      'Chevron renders only when hasChildren; not for childless rows',
      (tester) async {
    final s = _setup();
    s.container
        .read(expandedFolderIdsProvider.notifier)
        .expand('a'); // ensure b is rendered

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: 'a', createdAt: 2000),
    ]);
    await tester.pump();

    // A has child B -> exactly one chevron icon. B has no children -> none.
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets(
      'Chevron tap toggles expandedFolderIdsProvider; row InkWell does NOT '
      'fire (HitTestBehavior.opaque consumes it)', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: 'a', createdAt: 2000),
    ]);
    await tester.pump();

    expect(s.container.read(expandedFolderIdsProvider), isEmpty);
    expect(s.container.read(selectedFolderIdProvider), isNull);

    // Find the chevron's GestureDetector (the opaque one wrapping the
    // chevron Icon). tester.tap on the icon goes through the gesture arena
    // which doesn't always pick the right detector in tests, so invoke the
    // callback directly.
    final chevronGesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.byIcon(Icons.chevron_right),
            matching: find.byWidgetPredicate((w) =>
                w is GestureDetector &&
                w.behavior == HitTestBehavior.opaque),
          )
          .first,
    );
    chevronGesture.onTap!();
    await tester.pump();

    expect(s.container.read(expandedFolderIdsProvider), {'a'});
    expect(s.container.read(selectedFolderIdProvider), isNull,
        reason: 'chevron tap must NOT propagate to the row InkWell');

    // Tap again -> collapse.
    chevronGesture.onTap!();
    await tester.pump();
    expect(s.container.read(expandedFolderIdsProvider), <String>{});
  });

  testWidgets(
      'Children render only when parent is expanded; collapsed children '
      'are skipped from the widget tree', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: 'a', createdAt: 2000),
    ]);
    await tester.pump();

    // a is collapsed by default -> b's row not in the tree.
    expect(find.byKey(const ValueKey('b')), findsNothing);

    s.container.read(expandedFolderIdsProvider.notifier).expand('a');
    await tester.pump();
    expect(find.byKey(const ValueKey('b')), findsOneWidget);

    s.container.read(expandedFolderIdsProvider.notifier).collapse('a');
    await tester.pump();
    expect(find.byKey(const ValueKey('b')), findsNothing);
  });

  testWidgets(
      'Single-tap on row updates selectedFolderIdProvider; idempotent on '
      'already-selected', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'A', parentId: null)]);
    await tester.pump();

    // Find the InkWell inside the row and invoke its onTap directly --
    // bypasses GoRouter (no shell in this test harness; the InkWell handler
    // falls back to GoRouter.of which isn't installed in this MaterialApp,
    // so we just stub by reading the provider state.)
    final inkWells = tester
        .widgetList<InkWell>(find.byType(InkWell))
        .where((w) => w.onTap != null)
        .toList();
    // Pick the InkWell that toggles selection -- the row's outer InkWell.
    // There is only one row so it's the only InkWell with an onTap here.
    expect(inkWells, isNotEmpty);
    inkWells.first.onTap!();
    await tester.pump();

    expect(s.container.read(selectedFolderIdProvider), 'a');

    // Re-tap: idempotent. Spy by re-reading; the `if (isSelected) return`
    // guard means the notifier's state must remain unchanged (still 'a').
    inkWells.first.onTap!();
    await tester.pump();
    expect(s.container.read(selectedFolderIdProvider), 'a');
  });

  testWidgets('Selected folder gets accent text colour; sibling stays muted',
      (tester) async {
    final s = _setup();
    s.container.read(selectedFolderIdProvider.notifier).select('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('c', name: 'C', parentId: null, createdAt: 2000),
    ]);
    await tester.pump();

    final aText = tester.widget<Text>(find.text('A'));
    final cText = tester.widget<Text>(find.text('C'));
    expect(aText.style?.color?.toARGB32(),
        const Color(0xFFD05A58).toARGB32(),
        reason: 'A is selected -> accent colour');
    expect(cText.style?.color?.toARGB32(),
        const Color(0xFFABABAB).toARGB32(),
        reason: 'C is unselected -> textSidebar colour');
  });

  testWidgets(
      'Drag onto another folder calls moveFolder via DragTarget.onAccept',
      (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: null, createdAt: 2000),
    ]);
    await tester.pump();

    // Find each FolderRow's DragTarget and invoke onAcceptWithDetails.
    // Drag-and-drop testing in Flutter is fiddly; the documented pattern
    // (also used by Story 2.1's onTapOutside test) is to invoke the
    // callback directly.
    final dragTargets = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .toList();
    // The second target is B's row (row order in tree = 'a','b').
    expect(dragTargets.length, greaterThanOrEqualTo(2));
    final targetB = dragTargets[1];

    // Validate willAccept first: dragging A onto B should be accepted.
    final willAccept = targetB.onWillAcceptWithDetails!(
      DragTargetDetails<String>(
        data: 'a',
        offset: Offset.zero,
      ),
    );
    expect(willAccept, isTrue);

    targetB.onAcceptWithDetails!(
      DragTargetDetails<String>(
        data: 'a',
        offset: Offset.zero,
      ),
    );
    await tester.pump();

    final notifier = _readNotifier(s.container);
    expect(notifier.moveCalls, [
      ['a', 'b']
    ]);
  });

  testWidgets('Drag onto self is rejected at onWillAccept', (tester) async {
    final s = _setup();

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([_f('a', name: 'A', parentId: null)]);
    await tester.pump();

    final targetA = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .first;
    final willAccept = targetA.onWillAcceptWithDetails!(
      DragTargetDetails<String>(
        data: 'a',
        offset: Offset.zero,
      ),
    );
    expect(willAccept, isFalse);
  });

  testWidgets('Drag onto own descendant is rejected at onWillAccept',
      (tester) async {
    final s = _setup();
    s.container.read(expandedFolderIdsProvider.notifier).expand('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: 'a', createdAt: 2000),
    ]);
    await tester.pump();

    final dragTargets = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .toList();
    // Find the target on B's row (B is the descendant of A).
    expect(dragTargets.length, greaterThanOrEqualTo(2));
    final targetB = dragTargets[1];

    // Dragging A onto B (its own child) should be rejected.
    final willAccept = targetB.onWillAcceptWithDetails!(
      DragTargetDetails<String>(
        data: 'a',
        offset: Offset.zero,
      ),
    );
    expect(willAccept, isFalse);
  });

  testWidgets(
      'Edit-mode row remains a DragTarget so drops on a folder being '
      'renamed still call moveFolder', (tester) async {
    final s = _setup();

    // Put 'a' into edit mode BEFORE rendering so the build path enters
    // the edit branch.
    s.container.read(pendingFolderEditIdProvider.notifier).start('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: null, createdAt: 2000),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Confirm 'a' is in edit mode (TextField present in that row).
    expect(find.byType(TextField), findsOneWidget);

    // Find the DragTarget for row 'a' (its key is on the FolderRow which is
    // inside the DragTarget builder). DragTargets in this tree are
    // FolderRow-scoped; first DragTarget corresponds to row 'a'.
    final dragTargets = tester
        .widgetList<DragTarget<String>>(find.byType(DragTarget<String>))
        .toList();
    expect(dragTargets.length, greaterThanOrEqualTo(2));
    final targetA = dragTargets.first;

    // Drop B onto A while A is being renamed -- moveFolder must still fire.
    targetA.onAcceptWithDetails!(
      DragTargetDetails<String>(data: 'b', offset: Offset.zero),
    );
    await tester.pump();

    expect(_readNotifier(s.container).moveCalls, [
      ['b', 'a']
    ]);
  });

  testWidgets(
      'Indentation: child rows have greater leading padding than their '
      'parent (per-depth 16px)', (tester) async {
    final s = _setup();
    s.container.read(expandedFolderIdsProvider.notifier).expand('a');

    await tester.pumpWidget(_wrap(s.container));
    s.stream.add([
      _f('a', name: 'A', parentId: null, createdAt: 1000),
      _f('b', name: 'B', parentId: 'a', createdAt: 2000),
    ]);
    await tester.pump();

    final aRect = tester.getTopLeft(find.text('A'));
    final bRect = tester.getTopLeft(find.text('B'));
    // B is one depth deeper than A -> exactly 16px more leading padding.
    expect(bRect.dx - aRect.dx, closeTo(16.0, 0.01));
  });

  // ------------------------------------------------------------------
  // _FolderDeleteConfirmation tests (Story 2.4)
  // ------------------------------------------------------------------

  group('_FolderDeleteConfirmation', () {
    testWidgets(
        'with pendingFolderDeleteIdProvider == null, confirmation NOT rendered',
        (tester) async {
      final s = _setup();

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      expect(find.text("Delete 'Personal' and all its contents?"),
          findsNothing);
    });

    testWidgets(
        'with pendingFolderDeleteIdProvider == folder.id, confirmation '
        'is rendered with the folder name and Delete/Cancel buttons',
        (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      expect(find.text("Delete 'Personal' and all its contents?"),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Tapping Cancel clears pendingFolderDeleteIdProvider',
        (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();

      expect(s.container.read(pendingFolderDeleteIdProvider), isNull);
      expect(_readNotifier(s.container).deleteCascadeCalls, isEmpty);
    });

    testWidgets(
        'Tapping Delete invokes folderNotifier.deleteFolderCascade(folder.id) '
        'exactly once', (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();

      expect(_readNotifier(s.container).deleteCascadeCalls, ['a']);
    });

    testWidgets(
        'Enter inside the confirmation invokes deleteFolderCascade '
        '(autofocused FocusNode + Shortcuts(Enter) -- mirrors bookmark '
        'detail-pane Story 1.5 pattern)', (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      // Pump twice: first build mounts the FocusNode; postFrameCallback
      // queues requestFocus; second pump processes the focus request.
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(_readNotifier(s.container).deleteCascadeCalls, ['a'],
          reason: 'Enter inside the confirmation must confirm deletion');
    });

    testWidgets(
        'DismissIntent inside the confirmation clears '
        'pendingFolderDeleteIdProvider (local Shortcuts/Actions binding)',
        (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      // Invoke DismissIntent on a context INSIDE the confirmation so
      // resolution finds the local Action wiring (without depending on
      // primaryFocus being inside the local Shortcuts subtree -- the test
      // harness has no AppShell installed, so a key event with no in-scope
      // focus would propagate without effect).
      final ctx = tester.element(find.widgetWithText(TextButton, 'Cancel'));
      Actions.invoke(ctx, const DismissIntent());
      await tester.pump();

      expect(s.container.read(pendingFolderDeleteIdProvider), isNull);
    });

    testWidgets(
        'Switching pendingFolderDeleteIdProvider from A to B collapses A and '
        'renders B (single-confirmation invariant)', (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([
        _f('a', name: 'A', createdAt: 1000),
        _f('b', name: 'B', createdAt: 2000),
      ]);
      await tester.pump();

      expect(find.text("Delete 'A' and all its contents?"), findsOneWidget);
      expect(find.text("Delete 'B' and all its contents?"), findsNothing);

      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('b');
      await tester.pump();

      expect(find.text("Delete 'A' and all its contents?"), findsNothing);
      expect(find.text("Delete 'B' and all its contents?"), findsOneWidget);
    });

    testWidgets(
        'Confirmation indents to match the parent row (depth 0): content '
        'left edge equals the folder name left edge', (tester) async {
      final s = _setup();
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([_f('a', name: 'Personal')]);
      await tester.pump();

      final nameLeft = tester.getTopLeft(find.text('Personal')).dx;
      final promptLeft = tester
          .getTopLeft(find.text("Delete 'Personal' and all its contents?"))
          .dx;
      expect(promptLeft, closeTo(nameLeft, 0.01));
    });

    testWidgets(
        'Confirmation at deeper depth indents an additional 16px per level',
        (tester) async {
      final s = _setup();
      s.container.read(expandedFolderIdsProvider.notifier).expand('a');
      s.container.read(pendingFolderDeleteIdProvider.notifier).prompt('b');

      await tester.pumpWidget(_wrap(s.container));
      s.stream.add([
        _f('a', name: 'A', createdAt: 1000),
        _f('b', name: 'B', parentId: 'a', createdAt: 2000),
      ]);
      await tester.pump();

      final bNameLeft = tester.getTopLeft(find.text('B')).dx;
      final promptLeft = tester
          .getTopLeft(find.text("Delete 'B' and all its contents?"))
          .dx;
      expect(promptLeft, closeTo(bNameLeft, 0.01),
          reason:
              'depth-1 confirmation must align with depth-1 folder name (+16px)');
    });
  });
}
