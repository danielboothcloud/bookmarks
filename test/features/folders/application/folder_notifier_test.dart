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
    final state = container.read(folderNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
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
}
