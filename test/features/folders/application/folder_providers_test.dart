import 'dart:async';

import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Folder _f(
  String id, {
  String name = 'F',
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

({ProviderContainer container, StreamController<List<Folder>> stream})
    _setup() {
  final stream = StreamController<List<Folder>>.broadcast();
  addTearDown(stream.close);
  final container = ProviderContainer(overrides: [
    watchFoldersProvider.overrideWith((ref) => stream.stream),
  ]);
  addTearDown(container.dispose);
  return (container: container, stream: stream);
}

void main() {
  group('folderChildrenIndexProvider', () {
    test('groups folders by parentId, with null bucket for roots', () async {
      final s = _setup();
      // Subscribe so the StreamProvider emits.
      s.container.listen<AsyncValue<List<Folder>>>(
          watchFoldersProvider, (_, _) {});

      s.stream.add([
        _f('a', parentId: null),
        _f('b', parentId: 'a'),
        _f('c', parentId: 'a'),
      ]);
      await Future<void>.delayed(Duration.zero);

      final byParent = s.container.read(folderChildrenIndexProvider);
      expect(byParent[null]?.map((f) => f.id).toList(), ['a']);
      expect(byParent['a']?.map((f) => f.id).toList(), ['b', 'c']);
      expect(byParent.containsKey('b'), isFalse,
          reason: 'leaves should not appear as keys');
    });

    test('returns empty map when watchFoldersProvider has no value yet', () {
      final s = _setup();
      // No emission; AsyncValue.value will be null.

      final byParent = s.container.read(folderChildrenIndexProvider);
      expect(byParent, isEmpty);
    });
  });

  group('collectFolderDescendants', () {
    test('returns root + all descendants for a 4-deep nested chain', () {
      final byParent = <String?, List<Folder>>{
        'a': [_f('b', parentId: 'a')],
        'b': [_f('c', parentId: 'b')],
        'c': [_f('d', parentId: 'c')],
      };
      expect(collectFolderDescendants('a', byParent),
          equals({'a', 'b', 'c', 'd'}));
    });

    test('returns just the leaf id when leaf has no children', () {
      final byParent = <String?, List<Folder>>{};
      expect(collectFolderDescendants('leaf', byParent), equals({'leaf'}));
    });

    test('terminates on a corrupted byParent map containing a cycle', () {
      // a -> b -> a (corrupted). The visited set must prevent infinite
      // iteration; result is the closure of reachable ids.
      final byParent = <String?, List<Folder>>{
        'a': [_f('b', parentId: 'a')],
        'b': [_f('a', parentId: 'b')],
      };
      expect(collectFolderDescendants('a', byParent), equals({'a', 'b'}));
    });

    test(
        'returns descendants on a wide tree (root has multiple direct '
        'children)', () {
      final byParent = <String?, List<Folder>>{
        'a': [
          _f('b', parentId: 'a'),
          _f('c', parentId: 'a'),
        ],
        'b': [_f('d', parentId: 'b')],
      };
      expect(collectFolderDescendants('a', byParent),
          equals({'a', 'b', 'c', 'd'}));
    });
  });

  group('expandedFolderIdsProvider', () {
    test('toggle adds and removes the id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(expandedFolderIdsProvider.notifier);
      n.toggle('a');
      expect(container.read(expandedFolderIdsProvider), {'a'});
      n.toggle('a');
      expect(container.read(expandedFolderIdsProvider), <String>{});
    });

    test('expand is idempotent -- calling twice leaves the set unchanged',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(expandedFolderIdsProvider.notifier);
      n.expand('a');
      final first = container.read(expandedFolderIdsProvider);
      n.expand('a');
      final second = container.read(expandedFolderIdsProvider);

      expect(second, {'a'});
      // Second call must not have allocated a new set on no-op.
      expect(identical(first, second), isTrue);
    });

    test('collapse removes when present, no-op when absent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(expandedFolderIdsProvider.notifier);
      n.expand('a');
      n.expand('b');

      n.collapse('a');
      expect(container.read(expandedFolderIdsProvider), {'b'});

      // No-op collapse on absent id should keep the same set reference.
      final beforeNoOp = container.read(expandedFolderIdsProvider);
      n.collapse('zzz');
      final afterNoOp = container.read(expandedFolderIdsProvider);
      expect(identical(beforeNoOp, afterNoOp), isTrue);
    });

    test('initial state is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(expandedFolderIdsProvider), isEmpty);
    });
  });

  group('selectedFolderIdProvider', () {
    test('select sets state; clear resets to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedFolderIdProvider), isNull);

      container.read(selectedFolderIdProvider.notifier).select('a');
      expect(container.read(selectedFolderIdProvider), 'a');

      container.read(selectedFolderIdProvider.notifier).clear();
      expect(container.read(selectedFolderIdProvider), isNull);
    });
  });
}
