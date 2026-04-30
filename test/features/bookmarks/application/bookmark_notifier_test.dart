import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_notifier.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:bookmarks/features/bookmarks/domain/i_bookmark_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRepository implements IBookmarkRepository {
  Bookmark? lastSaved;
  Result<Bookmark, AppError> Function(Bookmark)? saveResult;

  @override
  Stream<List<Bookmark>> watchAll() => const Stream<List<Bookmark>>.empty();

  @override
  Future<Result<Bookmark, AppError>> getById(String id) async =>
      const Err<Bookmark, AppError>(StorageError('not impl'));

  @override
  Future<Result<Bookmark, AppError>> save(Bookmark bookmark) async {
    lastSaved = bookmark;
    return (saveResult ?? Ok<Bookmark, AppError>.new)(bookmark);
  }
}

ProviderContainer _container(IBookmarkRepository repo) {
  return ProviderContainer(overrides: [
    bookmarkRepositoryProvider.overrideWithValue(repo),
  ]);
}

void main() {
  test('addBookmark generates UUID v4 and stamps createdAt/updatedAt', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    await notifier.addBookmark(url: 'https://example.com');
    final afterMs = DateTime.now().millisecondsSinceEpoch;

    final saved = repo.lastSaved!;
    // UUID v4 canonical form: 8-4-4-4-12 hex with version digit '4'
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(saved.id), isTrue,
        reason: 'expected UUID v4, got ${saved.id}');
    expect(
      saved.createdAt.millisecondsSinceEpoch,
      inInclusiveRange(beforeMs, afterMs),
    );
    expect(saved.updatedAt, saved.createdAt);
  });

  test('addBookmark falls back title to url when title empty (AC5)', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    await notifier.addBookmark(url: 'https://example.com', title: '   ');
    expect(repo.lastSaved!.title, 'https://example.com');

    await notifier.addBookmark(url: 'https://other.com');
    expect(repo.lastSaved!.title, 'https://other.com');
  });

  test('addBookmark with explicit title preserves it', () async {
    final repo = _RecordingRepository();
    final container = _container(repo);
    addTearDown(container.dispose);

    await container
        .read(bookmarkNotifierProvider.notifier)
        .addBookmark(url: 'https://example.com', title: 'Custom');
    expect(repo.lastSaved!.title, 'Custom');
  });

  test('addBookmark sets AsyncValue.error on Err without throwing', () async {
    final repo = _RecordingRepository()
      ..saveResult = (_) => const Err<Bookmark, AppError>(StorageError('boom'));
    final container = _container(repo);
    addTearDown(container.dispose);

    final notifier = container.read(bookmarkNotifierProvider.notifier);
    await notifier.addBookmark(url: 'https://example.com');

    final state = container.read(bookmarkNotifierProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<StorageError>());
  });
}
