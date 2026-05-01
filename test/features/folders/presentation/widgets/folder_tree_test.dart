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
  final List<List<String>> renameCalls = <List<String>>[];

  @override
  Future<void> build() async {}

  @override
  Future<String?> addFolder() async {
    addCalls += 1;
    return 'fake-new-id';
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    renameCalls.add([id, newName]);
  }
}

Folder _f(
  String id, {
  required String name,
  int createdAt = 1000,
  int? updatedAt,
}) =>
    Folder(
      id: id,
      name: name,
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
}
