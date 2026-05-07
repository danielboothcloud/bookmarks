import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/tags/application/tag_notifier.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:bookmarks/features/tags/domain/tag_with_count.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTagRepository implements ITagRepository {
  final List<String> upsertByNameCalls = <String>[];
  final List<({String bookmarkId, String tagId})> linkCalls =
      <({String bookmarkId, String tagId})>[];
  final List<({String bookmarkId, String tagId})> unlinkCalls =
      <({String bookmarkId, String tagId})>[];

  Result<Tag, AppError> Function(String name)? upsertByNameResult;
  Result<void, AppError> Function(String b, String t)? linkResult;
  Result<void, AppError> Function(String b, String t)? unlinkResult;

  @override
  Stream<List<Tag>> watchAll() => const Stream<List<Tag>>.empty();

  @override
  Stream<List<TagWithCount>> watchAllWithCounts() =>
      const Stream<List<TagWithCount>>.empty();

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) =>
      const Stream<List<Tag>>.empty();

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async {
    upsertByNameCalls.add(name);
    final override = upsertByNameResult;
    if (override != null) return override(name);
    return Ok<Tag, AppError>(
      Tag(
        id: 'tag-${name.toLowerCase()}',
        name: name,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  @override
  Future<Result<void, AppError>> linkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    linkCalls.add((bookmarkId: bookmarkId, tagId: tagId));
    final override = linkResult;
    if (override != null) return override(bookmarkId, tagId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<void, AppError>> unlinkBookmarkTag(
    String bookmarkId,
    String tagId,
  ) async {
    unlinkCalls.add((bookmarkId: bookmarkId, tagId: tagId));
    final override = unlinkResult;
    if (override != null) return override(bookmarkId, tagId);
    return const Ok<void, AppError>(null);
  }

  @override
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  }) async =>
      const Ok<List<Tag>, AppError>(<Tag>[]);
}

ProviderContainer _container(ITagRepository repo) {
  final container = ProviderContainer(overrides: [
    tagRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'addTagToBookmark with empty name: repo NOT called; state stays .data(null)',
      () async {
    final repo = _RecordingTagRepository();
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).addTagToBookmark(
          bookmarkId: 'b1',
          name: '   ',
        );
    await _drain();

    expect(repo.upsertByNameCalls, isEmpty);
    expect(repo.linkCalls, isEmpty);
    final state = container.read(tagNotifierProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
  });

  test(
      'addTagToBookmark with "Flutter": upserts then links; state ends '
      '.data(null)', () async {
    final repo = _RecordingTagRepository();
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).addTagToBookmark(
          bookmarkId: 'b1',
          name: 'Flutter',
        );
    await _drain();

    expect(repo.upsertByNameCalls, ['Flutter']);
    expect(repo.linkCalls.length, 1);
    expect(repo.linkCalls.single.bookmarkId, 'b1');
    expect(repo.linkCalls.single.tagId, 'tag-flutter');
    expect(container.read(tagNotifierProvider).hasError, isFalse);
  });

  test(
      'addTagToBookmark when upsertByName returns Err: state .error; '
      'linkBookmarkTag NOT called', () async {
    final repo = _RecordingTagRepository()
      ..upsertByNameResult = (_) =>
          const Err<Tag, AppError>(StorageError('upsert blew up'));
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).addTagToBookmark(
          bookmarkId: 'b1',
          name: 'Flutter',
        );
    await _drain();

    expect(repo.linkCalls, isEmpty);
    expect(container.read(tagNotifierProvider).hasError, isTrue);
  });

  test('addTagToBookmark when linkBookmarkTag returns Err: state .error',
      () async {
    final repo = _RecordingTagRepository()
      ..linkResult = (_, _) =>
          const Err<void, AppError>(StorageError('link blew up'));
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).addTagToBookmark(
          bookmarkId: 'b1',
          name: 'Flutter',
        );
    await _drain();

    expect(repo.upsertByNameCalls, ['Flutter']);
    expect(repo.linkCalls.length, 1);
    expect(container.read(tagNotifierProvider).hasError, isTrue);
  });

  test('removeTagFromBookmark calls repo.unlink; state .data(null) on Ok',
      () async {
    final repo = _RecordingTagRepository();
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).removeTagFromBookmark(
          bookmarkId: 'b1',
          tagId: 't1',
        );
    await _drain();

    expect(repo.unlinkCalls.length, 1);
    expect(repo.unlinkCalls.single.bookmarkId, 'b1');
    expect(repo.unlinkCalls.single.tagId, 't1');
    expect(container.read(tagNotifierProvider).hasError, isFalse);
  });

  test('removeTagFromBookmark when repo returns Err: state .error', () async {
    final repo = _RecordingTagRepository()
      ..unlinkResult = (_, _) =>
          const Err<void, AppError>(StorageError('unlink blew up'));
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).removeTagFromBookmark(
          bookmarkId: 'b1',
          tagId: 't1',
        );
    await _drain();

    expect(container.read(tagNotifierProvider).hasError, isTrue);
  });

  test(
      'addTagToBookmark trims leading/trailing whitespace before dispatch',
      () async {
    final repo = _RecordingTagRepository();
    final container = _container(repo);

    await container.read(tagNotifierProvider.notifier).addTagToBookmark(
          bookmarkId: 'b1',
          name: '  Dart  ',
        );
    await _drain();

    expect(repo.upsertByNameCalls, ['Dart']);
  });
}
