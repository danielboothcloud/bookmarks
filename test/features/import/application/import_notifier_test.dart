import 'dart:async';

import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:bookmarks/features/import/application/import_providers.dart';
import 'package:bookmarks/features/import/data/file_picker_wrapper.dart';
import 'package:bookmarks/features/import/domain/import_failure_reason.dart';
import 'package:bookmarks/features/import/domain/import_state.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _BlockingBookmarkRepo implements IBookmarkRepository {
  final Completer<void> blocker = Completer<void>();
  int saves = 0;
  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Err(StorageError('unused'));
  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err(StorageError('unused'));
  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    saves++;
    await blocker.future;
    return Ok(bookmark);
  }

  @override
  Stream<List<Bookmark>> watchAll() => const Stream.empty();
  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) => const Stream.empty();
}

class _ExplodingBookmarkRepo implements IBookmarkRepository {
  @override
  Future<Result<void, AppError>> delete(String id) async =>
      const Err(StorageError('unused'));
  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err(StorageError('unused'));
  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async =>
      const Err(StorageError('disk full'));
  @override
  Stream<List<Bookmark>> watchAll() => const Stream.empty();
  @override
  Stream<List<Bookmark>> watchByTagId(String tagId) => const Stream.empty();
}

ProviderContainer _container({
  required AppDatabase db,
  required String? pickedPath,
  IBookmarkRepository? bookmarkRepoOverride,
}) {
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    filePickerProvider.overrideWithValue(
      FilePickerWrapper.fake(() => pickedPath),
    ),
    if (bookmarkRepoOverride != null)
      bookmarkRepositoryProvider.overrideWithValue(bookmarkRepoOverride),
  ]);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('happy path: idle → picking → parsing → writing → succeeded',
      () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
    );
    addTearDown(container.dispose);

    // Resolve build() so the notifier reaches ImportIdle before we
    // start observing — otherwise the first listen fires while state
    // is still AsyncLoading and we miss the idle baseline.
    await container.read(importNotifierProvider.future);
    final seen = <ImportState>[];
    container.listen(importNotifierProvider, (_, next) {
      final value = next.value;
      if (value != null) seen.add(value);
    }, fireImmediately: true);

    await container.read(importNotifierProvider.notifier).pickAndImport();

    expect(seen.first, isA<ImportIdle>());
    expect(seen.last, isA<ImportSucceeded>());
    // ensure the intermediate transitions appeared
    expect(seen.any((s) => s is ImportPicking), isTrue);
    expect(seen.any((s) => s is ImportParsing), isTrue);
    expect(seen.any((s) => s is ImportWriting), isTrue);

    final folders = await db.select(db.folders).get();
    final bookmarks = await db.select(db.bookmarks).get();
    expect(folders.length, 5);
    expect(bookmarks.length, 15);
  });

  test('user cancels: idle → picking → idle (silent return, AC7)',
      () async {
    final container = _container(db: db, pickedPath: null);
    addTearDown(container.dispose);

    await container.read(importNotifierProvider.notifier).pickAndImport();
    final state = container.read(importNotifierProvider).value;
    expect(state, isA<ImportIdle>(),
        reason: 'AC7 — cancel returns silently to idle, not failed');
    final bookmarks = await db.select(db.bookmarks).get();
    expect(bookmarks, isEmpty,
        reason: 'cancelled import must not touch the database');
  });

  test('invalid file → failed(invalidFile)', () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/malformed_bookmarks.html',
    );
    addTearDown(container.dispose);

    await container.read(importNotifierProvider.notifier).pickAndImport();
    final state = container.read(importNotifierProvider).value;
    expect(state, isA<ImportFailed>());
    expect((state! as ImportFailed).reason, ImportFailureReason.invalidFile);
  });

  test('non-existent file path → failed(invalidFile) (defensive)',
      () async {
    final container = _container(
      db: db,
      pickedPath: '/this/path/definitely/does/not/exist.html',
    );
    addTearDown(container.dispose);

    await container.read(importNotifierProvider.notifier).pickAndImport();
    final state = container.read(importNotifierProvider).value;
    expect(state, isA<ImportFailed>());
    expect((state! as ImportFailed).reason, ImportFailureReason.invalidFile);
  });

  test('storage error during write → failed(storageError); '
      'idempotent re-import allowed after resetToIdle', () async {
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
      bookmarkRepoOverride: _ExplodingBookmarkRepo(),
    );
    addTearDown(container.dispose);

    await container.read(importNotifierProvider.notifier).pickAndImport();
    var state = container.read(importNotifierProvider).value;
    expect(state, isA<ImportFailed>());
    expect((state! as ImportFailed).reason, ImportFailureReason.storageError);

    container.read(importNotifierProvider.notifier).resetToIdle();
    state = container.read(importNotifierProvider).value;
    expect(state, isA<ImportIdle>(),
        reason: 'resetToIdle clears the terminal state');
  });

  test('resetToIdle is a no-op from a non-terminal state', () async {
    // Block writes so the notifier sits in `ImportWriting`. Reset
    // should NOT short-circuit it.
    final blockingRepo = _BlockingBookmarkRepo();
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
      bookmarkRepoOverride: blockingRepo,
    );
    addTearDown(container.dispose);

    // Kick the import; don't await — it will stall inside save().
    final running =
        container.read(importNotifierProvider.notifier).pickAndImport();
    // Spin until we're past the picker and into writing/parsing.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final s = container.read(importNotifierProvider).value;
      if (s is ImportWriting) break;
    }
    final beforeReset = container.read(importNotifierProvider).value;
    expect(beforeReset, isA<ImportWriting>(),
        reason: 'import is in flight when resetToIdle is called');

    container.read(importNotifierProvider.notifier).resetToIdle();
    final afterReset = container.read(importNotifierProvider).value;
    expect(afterReset, isA<ImportWriting>(),
        reason: 'resetToIdle MUST be a no-op while an import is running');

    // Let the import finish so the test exits cleanly.
    blockingRepo.blocker.complete();
    await running;
  });

  test('concurrent pickAndImport while one is in flight is a no-op',
      () async {
    // Block on save() so the first import stalls in ImportWriting.
    final blockingRepo = _BlockingBookmarkRepo();
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/chrome_bookmarks.html',
      bookmarkRepoOverride: blockingRepo,
    );
    addTearDown(container.dispose);

    final first =
        container.read(importNotifierProvider.notifier).pickAndImport();
    // Wait until we're in ImportWriting.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final s = container.read(importNotifierProvider).value;
      if (s is ImportWriting) break;
    }
    expect(container.read(importNotifierProvider).value, isA<ImportWriting>());

    // Second click should be a no-op.
    await container.read(importNotifierProvider.notifier).pickAndImport();
    expect(container.read(importNotifierProvider).value, isA<ImportWriting>(),
        reason: 'second pickAndImport must not spawn a parallel run');
    expect(blockingRepo.saves, lessThanOrEqualTo(1),
        reason: 'only one save attempt should be inflight');

    blockingRepo.blocker.complete();
    await first;
  });

  test('progress updates flow through state on each batch', () async {
    // Use the 500-bookmark fixture so we cross the 50-batch threshold
    // multiple times.
    final container = _container(
      db: db,
      pickedPath: 'test/fixtures/large_bookmarks.html',
    );
    addTearDown(container.dispose);

    final progressCounts = <int>[];
    container.listen(importNotifierProvider, (_, next) {
      final v = next.value;
      if (v is ImportWriting) progressCounts.add(v.progress.itemsWritten);
    });

    await container.read(importNotifierProvider.notifier).pickAndImport();
    // 31 folders + 500 bookmarks = 531 writes; batches of 50 → ~10
    // mid-import emits + the terminal one. Be loose to absorb timing.
    expect(progressCounts.length, greaterThanOrEqualTo(5));
    expect(progressCounts.last, 531);
  });
}

