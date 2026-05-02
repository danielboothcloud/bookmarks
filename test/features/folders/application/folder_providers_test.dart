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

  group('flattenFolderTree', () {
    test('returns empty list when byParent is empty', () {
      expect(flattenFolderTree(<String?, List<Folder>>{}), isEmpty);
    });

    test('returns single root when no children exist', () {
      final root = _f('a', name: 'A');
      final byParent = <String?, List<Folder>>{
        null: [root],
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.length, 1);
      expect(flat[0].folder.id, 'a');
      expect(flat[0].depth, 0);
    });

    test('root + two children returns pre-order [root, c1, c2]', () {
      final root = _f('a', name: 'A');
      final c1 = _f('b', name: 'B', parentId: 'a');
      final c2 = _f('c', name: 'C', parentId: 'a');
      final byParent = <String?, List<Folder>>{
        null: [root],
        'a': [c1, c2],
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.map((e) => e.folder.id).toList(), ['a', 'b', 'c']);
      expect(flat.map((e) => e.depth).toList(), [0, 1, 1]);
    });

    test('three-deep chain A -> B -> C is emitted in pre-order', () {
      final byParent = <String?, List<Folder>>{
        null: [_f('a', name: 'A')],
        'a': [_f('b', name: 'B', parentId: 'a')],
        'b': [_f('c', name: 'C', parentId: 'b')],
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.map((e) => e.folder.id).toList(), ['a', 'b', 'c']);
      expect(flat.map((e) => e.depth).toList(), [0, 1, 2]);
    });

    test(
        'two roots with mixed children: each root is followed by its own '
        'descendants before the next root is emitted', () {
      // Tree:
      //   root1
      //     childA
      //     childB
      //   root2
      //     childC
      final byParent = <String?, List<Folder>>{
        null: [_f('root1'), _f('root2')],
        'root1': [
          _f('childA', parentId: 'root1'),
          _f('childB', parentId: 'root1'),
        ],
        'root2': [_f('childC', parentId: 'root2')],
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.map((e) => e.folder.id).toList(),
          ['root1', 'childA', 'childB', 'root2', 'childC']);
      expect(flat.map((e) => e.depth).toList(), [0, 1, 1, 0, 1]);
    });

    test('cyclic byParent (a -> b -> a) terminates without duplicates', () {
      final byParent = <String?, List<Folder>>{
        null: [_f('a')],
        'a': [_f('b', parentId: 'a')],
        'b': [_f('a', parentId: 'b')], // cycle back to root
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.map((e) => e.folder.id).toList(), ['a', 'b']);
    });

    test('sibling order matches byParent list order (no internal sorting)', () {
      // The repo emits createdAt asc; the function must NOT re-sort.
      final byParent = <String?, List<Folder>>{
        null: [
          _f('z', name: 'Zeta', t: 100),
          _f('a', name: 'Alpha', t: 200),
        ],
      };
      final flat = flattenFolderTree(byParent);
      expect(flat.map((e) => e.folder.id).toList(), ['z', 'a']);
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

  group('pendingFolderDeleteIdProvider', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pendingFolderDeleteIdProvider), isNull);
    });

    test('prompt sets state; clear resets to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');
      expect(container.read(pendingFolderDeleteIdProvider), 'a');

      container.read(pendingFolderDeleteIdProvider.notifier).clear();
      expect(container.read(pendingFolderDeleteIdProvider), isNull);
    });

    test('prompt(b) after prompt(a) migrates state to b (single confirmation)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pendingFolderDeleteIdProvider.notifier).prompt('a');
      container.read(pendingFolderDeleteIdProvider.notifier).prompt('b');
      expect(container.read(pendingFolderDeleteIdProvider), 'b');
    });
  });

  group('ExpandedFolderIdsNotifier.replace', () {
    test('replaces the set with a different membership', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(expandedFolderIdsProvider.notifier);
      n.expand('a');
      n.expand('b');

      n.replace({'a', 'c'});
      expect(container.read(expandedFolderIdsProvider), {'a', 'c'});
    });

    test('setEquals-equal replacement emits no notification', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(expandedFolderIdsProvider.notifier);
      n.expand('a');
      n.expand('b');

      var notifications = 0;
      final sub = container.listen<Set<String>>(
        expandedFolderIdsProvider,
        (_, _) => notifications++,
      );
      addTearDown(sub.close);

      n.replace({'a', 'b'}); // identity-equal in setEquals terms
      expect(notifications, 0);
    });
  });

  group('visibleFolderListProvider', () {
    // The walker reads byParent + the expansion set and emits a flat
    // depth-ordered list. Tests below override folderChildrenIndexProvider
    // directly so we exercise the walk in isolation from watchFoldersProvider.
    ProviderContainer makeContainer({
      required Map<String?, List<Folder>> byParent,
      Set<String> expanded = const <String>{},
    }) {
      final container = ProviderContainer(overrides: [
        folderChildrenIndexProvider.overrideWithValue(byParent),
      ]);
      addTearDown(container.dispose);
      // Pre-populate expansion set after construction so the override above
      // is the only injection point we need.
      final n = container.read(expandedFolderIdsProvider.notifier);
      for (final id in expanded) {
        n.expand(id);
      }
      return container;
    }

    test('empty byParent yields an empty list', () {
      final c = makeContainer(byParent: const <String?, List<Folder>>{});
      expect(c.read(visibleFolderListProvider), isEmpty);
    });

    test('roots only, none expanded -> roots in createdAt asc order', () {
      final c = makeContainer(byParent: <String?, List<Folder>>{
        null: [_f('a', t: 1000), _f('b', t: 2000), _f('c', t: 3000)],
      });
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('collapsed parent hides its children even when they exist', () {
      final c = makeContainer(byParent: <String?, List<Folder>>{
        null: [_f('a')],
        'a': [_f('b', parentId: 'a')],
      });
      // 'a' is NOT in the expanded set.
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a'],
      );
    });

    test('expanded parent reveals direct children in pre-order', () {
      final c = makeContainer(
        byParent: <String?, List<Folder>>{
          null: [_f('a')],
          'a': [_f('b', parentId: 'a', t: 1000), _f('c', parentId: 'a', t: 2000)],
        },
        expanded: {'a'},
      );
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('deep nesting with all expanded -> full pre-order DFS', () {
      // Tree:
      //   a
      //     b
      //       c
      //   d
      final c = makeContainer(
        byParent: <String?, List<Folder>>{
          null: [_f('a', t: 1000), _f('d', t: 4000)],
          'a': [_f('b', parentId: 'a', t: 2000)],
          'b': [_f('c', parentId: 'b', t: 3000)],
        },
        expanded: {'a', 'b'},
      );
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('mixed expansion: only expanded parents reveal children', () {
      // Tree:
      //   a (expanded)
      //     b
      //   c (collapsed)
      //     d
      final c = makeContainer(
        byParent: <String?, List<Folder>>{
          null: [_f('a', t: 1000), _f('c', t: 3000)],
          'a': [_f('b', parentId: 'a', t: 2000)],
          'c': [_f('d', parentId: 'c', t: 4000)],
        },
        expanded: {'a'},
      );
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('expanding an unknown id (no entry in byParent) is a silent no-op', () {
      final c = makeContainer(
        byParent: <String?, List<Folder>>{null: [_f('a')]},
        expanded: {'ghost'}, // not present in any byParent value
      );
      expect(
        c.read(visibleFolderListProvider).map((f) => f.id).toList(),
        ['a'],
      );
    });
  });
}
