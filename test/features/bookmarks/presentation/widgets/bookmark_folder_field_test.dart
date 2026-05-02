import 'dart:async';

import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/bookmarks/presentation/widgets/bookmark_folder_field.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:flutter/material.dart';
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

Widget _wrap(
  ProviderContainer container, {
  required String? currentFolderId,
  required ValueChanged<String?> onChanged,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: _Eager(
          child: Center(
            child: SizedBox(
              width: 280,
              child: BookmarkFolderField(
                currentFolderId: currentFolderId,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('with null folderId renders "No folder" in italic muted style',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: null, onChanged: (_) {}));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('No folder'));
    expect(label.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('with assigned folderId renders the folder name in body style',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: 'a', onChanged: (_) {}));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Personal'));
    expect(label.style?.fontStyle, FontStyle.normal);
  });

  testWidgets('falls back to "No folder" when assigned id is missing',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: 'gone-id', onChanged: (_) {}));
    s.stream.add(const <Folder>[]);
    await tester.pumpAndSettle();

    expect(find.text('No folder'), findsOneWidget);
    final label = tester.widget<Text>(find.text('No folder'));
    expect(label.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('tapping the field opens the picker with all folders',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: null, onChanged: (_) {}));
    s.stream.add([_f('a', name: 'Personal'), _f('b', name: 'Work')]);
    await tester.pumpAndSettle();

    // Tap the visible label inside the field; opens the picker.
    await tester.tap(find.text('No folder'));
    await tester.pumpAndSettle();

    // Picker shows "No folder" (the menu item) plus every folder name.
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('selecting a folder fires onChanged(<id>) exactly once',
      (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: null, onChanged: calls.add));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BookmarkFolderField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();

    expect(calls, ['a']);
  });

  testWidgets('selecting "No folder" fires onChanged(null) exactly once',
      (tester) async {
    final s = _setup();
    final calls = <String?>[];
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: 'a', onChanged: calls.add));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BookmarkFolderField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No folder'));
    await tester.pumpAndSettle();

    expect(calls, [null]);
  });

  testWidgets('renders folder + chevron icons', (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: null, onChanged: (_) {}));
    s.stream.add(const <Folder>[]);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  });

  testWidgets('semantics label includes the resolved folder name',
      (tester) async {
    final s = _setup();
    await tester.pumpWidget(_wrap(s.container,
        currentFolderId: 'a', onChanged: (_) {}));
    s.stream.add([_f('a', name: 'Personal')]);
    await tester.pumpAndSettle();

    final semantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(BookmarkFolderField),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Folder: Personal',
        ),
      ),
    );
    expect(semantics.properties.button, isTrue);
  });
}
