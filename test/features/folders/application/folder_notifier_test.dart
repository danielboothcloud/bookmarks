import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/folders/application/folder_notifier.dart';
import 'package:bookmarks/features/folders/application/folder_providers.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:bookmarks/features/folders/domain/i_folder_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingFolderRepository implements IFolderRepository {
  final List<Folder> savedFolders = <Folder>[];
  final Map<String, Folder> store = <String, Folder>{};

  Result<Folder, AppError> Function(Folder)? saveResult;
  Result<Folder, AppError> Function(String)? getByIdResult;

  @override
  Stream<List<Folder>> watchAll() => const Stream<List<Folder>>.empty();

  @override
  Future<Result<Folder, AppError>> getById(String id) async {
    final override = getByIdResult;
    if (override != null) return override(id);
    final f = store[id];
    if (f == null) return const Err<Folder, AppError>(NotFoundError());
    return Ok<Folder, AppError>(f);
  }

  @override
  Future<Result<Folder, AppError>> save(Folder folder) async {
    savedFolders.add(folder);
    store[folder.id] = folder;
    return (saveResult ?? Ok<Folder, AppError>.new)(folder);
  }
}

ProviderContainer _container(IFolderRepository repo) {
  return ProviderContainer(overrides: [
    folderRepositoryProvider.overrideWithValue(repo),
  ]);
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('addFolder calls repo.save once, returns id, ends with hasValue',
      () async {
    final repo = _RecordingFolderRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final newId = await container
        .read(folderNotifierProvider.notifier)
        .addFolder();
    await _drain();

    expect(newId, isNotNull);
    expect(repo.savedFolders.length, 1);
    expect(repo.savedFolders.first.id, newId);
    expect(repo.savedFolders.first.parentId, isNull,
        reason: 'addFolder() with no arg defaults to root (parentId == null)');
    final state = container.read(folderNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
  });

  test(
      'addFolder() with no arg does NOT touch expandedFolderIdsProvider '
      '(no parent to expand)', () async {
    final repo = _RecordingFolderRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(folderNotifierProvider.notifier).addFolder();
    await _drain();

    expect(container.read(expandedFolderIdsProvider), isEmpty);
  });

  test(
      'addFolder(parentId: ...) saves folder with that parentId and '
      'auto-expands the parent', () async {
    final repo = _RecordingFolderRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final newId = await container
        .read(folderNotifierProvider.notifier)
        .addFolder(parentId: 'p-1');
    await _drain();

    expect(newId, isNotNull);
    expect(repo.savedFolders.single.parentId, 'p-1');
    expect(container.read(expandedFolderIdsProvider), contains('p-1'),
        reason:
            'parent must auto-expand so the new child row is visible (AC1)');
  });

  test('addFolder returns null and sets hasError on Err', () async {
    final repo = _RecordingFolderRepository()
      ..saveResult = (_) => const Err<Folder, AppError>(StorageError('boom'));
    final container = _container(repo);
    addTearDown(container.dispose);

    final newId = await container
        .read(folderNotifierProvider.notifier)
        .addFolder();

    expect(newId, isNull);
    final state = container.read(folderNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StorageError>());
  });

  test(
      'addFolder saves folder with default name, null parentId, and '
      'createdAt == updatedAt at construction', () async {
    final repo = _RecordingFolderRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    await container.read(folderNotifierProvider.notifier).addFolder();
    await _drain();

    final saved = repo.savedFolders.single;
    expect(saved.name, 'New folder');
    expect(saved.parentId, isNull);
    expect(saved.createdAt, saved.updatedAt);
  });

  test(
      'renameFolder calls getById then save with new name and a bumped '
      'updatedAt', () async {
    final repo = _RecordingFolderRepository();
    final original = Folder(
      id: 'f-1',
      name: 'Old',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    repo.store[original.id] = original;

    final container = _container(repo);
    addTearDown(container.dispose);

    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('f-1', 'New name');
    await _drain();

    expect(repo.savedFolders.length, 1);
    final saved = repo.savedFolders.single;
    expect(saved.id, 'f-1');
    expect(saved.name, 'New name');
    expect(saved.createdAt, original.createdAt,
        reason: 'createdAt must not change on rename');
    expect(
      saved.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(beforeMs),
    );
  });

  test('renameFolder with whitespace-only name is a silent no-op', () async {
    final repo = _RecordingFolderRepository();
    repo.store['f-1'] = Folder(
      id: 'f-1',
      name: 'Old',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('f-1', '   ');

    expect(repo.savedFolders, isEmpty);
  });

  test('renameFolder with empty string is a silent no-op', () async {
    final repo = _RecordingFolderRepository();
    repo.store['f-1'] = Folder(
      id: 'f-1',
      name: 'Old',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('f-1', '');

    expect(repo.savedFolders, isEmpty);
  });

  test('renameFolder with identical name is a silent no-op (no save)',
      () async {
    final repo = _RecordingFolderRepository();
    repo.store['f-1'] = Folder(
      id: 'f-1',
      name: 'Personal',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('f-1', 'Personal');

    expect(repo.savedFolders, isEmpty);
  });

  test('renameFolder empty/whitespace clears stale error state', () async {
    final repo = _RecordingFolderRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    // Seed an error state via a failing rename on an unknown id.
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('missing', 'whatever');
    expect(container.read(folderNotifierProvider).hasError, isTrue);

    // A subsequent empty-name rename should clear the error -- treating
    // empty as a calm cancel rather than preserving the phantom failure.
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('missing', '');

    expect(container.read(folderNotifierProvider).hasError, isFalse);
    expect(container.read(folderNotifierProvider).hasValue, isTrue);
  });

  test('renameFolder identical-name clears stale error state', () async {
    final repo = _RecordingFolderRepository();
    repo.store['f-1'] = Folder(
      id: 'f-1',
      name: 'Personal',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final container = _container(repo);
    addTearDown(container.dispose);

    // Seed an error via a failing rename on a different (missing) id.
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('missing', 'whatever');
    expect(container.read(folderNotifierProvider).hasError, isTrue);

    // Identical-name rename short-circuits but should clear the prior error.
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('f-1', 'Personal');

    expect(repo.savedFolders, isEmpty);
    expect(container.read(folderNotifierProvider).hasError, isFalse);
    expect(container.read(folderNotifierProvider).hasValue, isTrue);
  });

  test(
      'renameFolder with unknown id does not call save and ends with '
      'hasError when getById returns Err', () async {
    final repo = _RecordingFolderRepository();
    // No entry in store -> getById returns Err(NotFoundError).
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('missing', 'whatever');

    expect(repo.savedFolders, isEmpty);
    final state = container.read(folderNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<NotFoundError>());
  });

  // ------------------------------------------------------------------
  // moveFolder tests (Story 2.2)
  // ------------------------------------------------------------------

  Folder seedFolder(
    _RecordingFolderRepository repo, {
    required String id,
    String? parentId,
    String name = 'F',
    int t = 1000,
  }) {
    final f = Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(t),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(t),
    );
    repo.store[id] = f;
    return f;
  }

  test(
      'moveFolder updates parentId, bumps updatedAt, and calls expand on '
      'the new parent', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: null, t: 1000);
    seedFolder(repo, id: 'b', parentId: null, t: 1500);
    final container = _container(repo);
    addTearDown(container.dispose);

    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    expect(repo.savedFolders.length, 1);
    expect(repo.savedFolders.single.id, 'a');
    expect(repo.savedFolders.single.parentId, 'b');
    expect(
      repo.savedFolders.single.updatedAt.millisecondsSinceEpoch,
      greaterThanOrEqualTo(beforeMs),
    );
    expect(container.read(expandedFolderIdsProvider), contains('b'));
    expect(container.read(folderNotifierProvider).hasValue, isTrue);
  });

  test(
      'moveFolder(id, null) moves to root, does NOT call expand '
      '(no parent)', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: 'b', t: 1000);
    seedFolder(repo, id: 'b', parentId: null, t: 1500);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', null);

    expect(repo.savedFolders.length, 1);
    expect(repo.savedFolders.single.parentId, isNull);
    expect(container.read(expandedFolderIdsProvider), isEmpty);
  });

  test('moveFolder onto self is a silent no-op (no save)', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: null);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'a');

    expect(repo.savedFolders, isEmpty);
    expect(container.read(folderNotifierProvider).hasError, isFalse);
  });

  test(
      'moveFolder onto a direct child (a -> b, move a under b) is rejected '
      'as a cycle (no save)', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: null);
    seedFolder(repo, id: 'b', parentId: 'a');
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    expect(repo.savedFolders, isEmpty);
    expect(container.read(folderNotifierProvider).hasError, isFalse);
  });

  test(
      'moveFolder onto a deeper descendant (a -> x -> b) is rejected as a '
      'cycle (cycle walker traverses the chain)', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: null);
    seedFolder(repo, id: 'x', parentId: 'a');
    seedFolder(repo, id: 'b', parentId: 'x');
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    expect(repo.savedFolders, isEmpty);
    expect(container.read(folderNotifierProvider).hasError, isFalse);
  });

  test(
      'moveFolder to current parent (already there) is a silent no-op and '
      'clears stale error', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: 'b');
    seedFolder(repo, id: 'b', parentId: null);
    final container = _container(repo);
    addTearDown(container.dispose);

    // Seed an error state via a failing rename on a missing id.
    await container
        .read(folderNotifierProvider.notifier)
        .renameFolder('missing', 'whatever');
    expect(container.read(folderNotifierProvider).hasError, isTrue);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    expect(repo.savedFolders, isEmpty,
        reason: 'parentId already equals newParentId -> idempotent no-op');
    expect(container.read(folderNotifierProvider).hasError, isFalse);
    expect(container.read(folderNotifierProvider).hasValue, isTrue);
  });

  test(
      'moveFolder with an unknown moving id ends with hasError (getById Err)',
      () async {
    final repo = _RecordingFolderRepository();
    // Seed a valid candidate parent so the cycle check passes (chain ends
    // at root) and we proceed to getById on the moving id.
    seedFolder(repo, id: 'b', parentId: null);
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('unknown', 'b');

    expect(repo.savedFolders, isEmpty);
    expect(container.read(folderNotifierProvider).hasError, isTrue);
  });

  test(
      'moveFolder with a corrupted parent chain (parent vanished) does NOT '
      'infinite-loop -- cycle walker terminates and the move proceeds',
      () async {
    final repo = _RecordingFolderRepository();
    // 'b' claims its parent is 'ghost' which is not in the store. The
    // walker should treat the broken chain as "no cycle" and proceed.
    seedFolder(repo, id: 'a', parentId: null);
    seedFolder(repo, id: 'b', parentId: 'ghost');
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    expect(repo.savedFolders.length, 1,
        reason: 'broken chain is treated as no cycle; move should proceed');
    expect(repo.savedFolders.single.parentId, 'b');
  });

  test('moveFolder save Err sets hasError', () async {
    final repo = _RecordingFolderRepository();
    seedFolder(repo, id: 'a', parentId: null);
    seedFolder(repo, id: 'b', parentId: null);
    repo.saveResult =
        (_) => const Err<Folder, AppError>(StorageError('boom'));
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(folderNotifierProvider.notifier)
        .moveFolder('a', 'b');

    final state = container.read(folderNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StorageError>());
  });
}
