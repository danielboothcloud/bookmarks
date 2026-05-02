import 'dart:async';

import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/folders/presentation/widgets/folder_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Folder _f(
  String id, {
  required String name,
  String? parentId,
  int t = 1000,
}) =>
    Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t),
    );

({ProviderContainer container, StreamController<List<Folder>> stream}) _setup() {
  final stream = StreamController<List<Folder>>.broadcast();
  addTearDown(stream.close);
  final container = ProviderContainer(overrides: [
    watchFoldersProvider.overrideWith((ref) => stream.stream),
  ]);
  addTearDown(container.dispose);
  return (container: container, stream: stream);
}

/// Eagerly subscribes to [folderChildrenIndexProvider] / [watchFoldersProvider]
/// so the broadcast stream emission lands BEFORE the picker rebuilds.
class _Eager extends ConsumerWidget {
  const _Eager({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchFoldersProvider);
    ref.watch(folderChildrenIndexProvider);
    return child;
  }
}

Widget _wrapEager(
  ProviderContainer container, {
  required String? currentFolderId,
  required ValueChanged<String?> onSelected,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: _Eager(
          child: Center(
            child: FolderPicker(
              currentFolderId: currentFolderId,
              onSelected: onSelected,
              child: const Text('anchor'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the anchor without opening the menu by default',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: (_) {}));
    s.stream.add(const <Folder>[]);
    await tester.pumpAndSettle();

    expect(find.text('anchor'), findsOneWidget);
    // No menu items are visible until the anchor is tapped.
    expect(find.text('No folder'), findsNothing);
  });

  testWidgets('tapping the anchor opens the menu with "No folder" first',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: (_) {}));
    s.stream.add(const <Folder>[]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();

    expect(find.text('No folder'), findsOneWidget);
  });

  testWidgets(
      'menu lists "No folder", root + descendants in pre-order with depth '
      'indent', (tester) async {
    // Tree: A (root), B (child of A), C (root). Expected pre-order:
    //   No folder, A (d0), B (d1), C (d0).
    final s = _setup();
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: (_) {}));
    s.stream.add([
      _f('a', name: 'A'),
      _f('b', name: 'B', parentId: 'a'),
      _f('c', name: 'C'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();

    final noFolder = tester.getRect(find.text('No folder'));
    final a = tester.getRect(find.text('A'));
    final b = tester.getRect(find.text('B'));
    final c = tester.getRect(find.text('C'));

    // Vertical order: No folder, A, B, C.
    expect(noFolder.top, lessThan(a.top));
    expect(a.top, lessThan(b.top));
    expect(b.top, lessThan(c.top));

    // B (depth 1) is indented 16px more than its parent A (depth 0).
    expect(b.left - a.left, closeTo(16.0, 0.5));
    // C (depth 0) sits at the same indent as A.
    expect(c.left, closeTo(a.left, 0.5));
  });

  testWidgets('current folder shows a check icon; "No folder" does not',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: 'a', onSelected: (_) {}));
    s.stream.add([_f('a', name: 'A')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();

    // Exactly one check-mark icon -- the current selection.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping "No folder" calls onSelected(null) once', (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: 'a', onSelected: calls.add));
    s.stream.add([_f('a', name: 'A')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No folder'));
    await tester.pumpAndSettle();

    expect(calls, [null]);
  });

  testWidgets('tapping a folder calls onSelected(<id>) once and closes',
      (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: calls.add));
    s.stream.add([_f('a', name: 'A')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    expect(calls, ['a']);
    // Menu closed -- A (in the menu) should no longer be findable.
    expect(find.text('No folder'), findsNothing);
  });

  testWidgets('outside-tap closes the menu without firing onSelected',
      (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: calls.add));
    s.stream.add([_f('a', name: 'A')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();
    expect(find.text('No folder'), findsOneWidget);

    // Tap outside the menu -- top-left corner of the screen.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.text('No folder'), findsNothing);
  });

  testWidgets('with empty folder list, only "No folder" appears',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: (_) {}));
    s.stream.add(const <Folder>[]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();

    expect(find.text('No folder'), findsOneWidget);
    // No other MenuItemButton labels.
    expect(find.byType(MenuItemButton), findsOneWidget);
  });

  testWidgets('pressing Esc closes the menu without firing onSelected',
      (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrapEager(s.container,
        currentFolderId: null, onSelected: calls.add));
    s.stream.add([_f('a', name: 'A')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();
    expect(find.text('No folder'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('No folder'), findsNothing,
        reason: 'Esc must close the MenuAnchor menu');
    expect(calls, isEmpty,
        reason: 'Esc dismissal must not trigger onSelected');
  });

  testWidgets(
      'cyclic byParent (a -> b -> a) terminates without duplicate rows',
      (tester) async {
    // A flat List<Folder> -> stream cannot produce a cyclic byParent map
    // (each Folder has one parentId). To exercise flattenFolderTree's
    // visited set, override folderChildrenIndexProvider directly with a
    // map where id 'a' appears as both a root AND a grandchild of itself.
    final byParent = <String?, List<Folder>>{
      null: [_f('a', name: 'A')],
      'a': [_f('b', name: 'B', parentId: 'a')],
      'b': [_f('a', name: 'A', parentId: 'b')], // cycle: id 'a' reused
    };
    final container = ProviderContainer(overrides: [
      // _Eager still listens to watchFoldersProvider via folderChildrenIndex's
      // upstream; satisfy it with an empty stream so the provider graph
      // doesn't try to reach the real database.
      watchFoldersProvider.overrideWith(
        (ref) => Stream<List<Folder>>.value(const <Folder>[]),
      ),
      folderChildrenIndexProvider.overrideWith((ref) => byParent),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrapEager(container,
        currentFolderId: null, onSelected: (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('anchor'));
    await tester.pumpAndSettle();

    // Visited set must suppress the second emission of id 'a'. Expected
    // rows: "No folder", A (root), B (child of A). The cyclic 'a' under B
    // is dropped.
    expect(find.text('A'), findsOneWidget,
        reason: 'visited set must suppress the cyclic re-entry of id "a"');
    expect(find.text('B'), findsOneWidget);
  });
}
