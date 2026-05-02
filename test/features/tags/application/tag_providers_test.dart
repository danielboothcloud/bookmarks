import 'dart:async';

import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/tags/application/tag_providers.dart';
import 'package:bookmarks/features/tags/domain/i_tag_repository.dart';
import 'package:bookmarks/features/tags/domain/tag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StreamingTagRepository implements ITagRepository {
  final StreamController<List<Tag>> allController =
      StreamController<List<Tag>>.broadcast();
  final Map<String, StreamController<List<Tag>>> perBookmarkControllers =
      <String, StreamController<List<Tag>>>{};

  @override
  Stream<List<Tag>> watchAll() => allController.stream;

  @override
  Stream<List<Tag>> watchForBookmark(String bookmarkId) {
    final controller = perBookmarkControllers.putIfAbsent(
      bookmarkId,
      StreamController<List<Tag>>.broadcast,
    );
    return controller.stream;
  }

  @override
  Future<Result<Tag, AppError>> getById(String id) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> findByName(String name) async =>
      const Err<Tag, AppError>(NotFoundError());

  @override
  Future<Result<Tag, AppError>> upsertByName(String name) async => Ok<Tag,
      AppError>(Tag(
    id: name,
    name: name,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  ));

  @override
  Future<Result<void, AppError>> linkBookmarkTag(
          String bookmarkId, String tagId) async =>
      const Ok<void, AppError>(null);

  @override
  Future<Result<void, AppError>> unlinkBookmarkTag(
          String bookmarkId, String tagId) async =>
      const Ok<void, AppError>(null);

  @override
  Future<Result<List<Tag>, AppError>> upsertAndLinkAll({
    required String bookmarkId,
    required List<String> tagNames,
  }) async =>
      const Ok<List<Tag>, AppError>(<Tag>[]);
}

void main() {
  test('tagInputDraftProvider default state is ""', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(tagInputDraftProvider), '');
  });

  test('tagInputDraftProvider update("flu") then clear()', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(tagInputDraftProvider.notifier).update('flu');
    expect(container.read(tagInputDraftProvider), 'flu');

    container.read(tagInputDraftProvider.notifier).clear();
    expect(container.read(tagInputDraftProvider), '');
  });

  test('watchAllTagsProvider stream forwards values from the repo', () async {
    final repo = _StreamingTagRepository();
    final container = ProviderContainer(overrides: [
      tagRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    addTearDown(repo.allController.close);

    container.listen<AsyncValue<List<Tag>>>(watchAllTagsProvider, (_, _) {});

    final emitted = [
      Tag(
        id: 't',
        name: 't',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
    repo.allController.add(emitted);
    await Future<void>.delayed(Duration.zero);

    final value = container.read(watchAllTagsProvider).value;
    expect(value, isNotNull);
    expect(value!.single.name, 't');
  });

  test(
      'watchTagsForBookmarkProvider family is keyed by bookmark id — '
      'two ids subscribe to two distinct streams (no crosstalk)', () async {
    final repo = _StreamingTagRepository();
    final container = ProviderContainer(overrides: [
      tagRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    addTearDown(() {
      for (final c in repo.perBookmarkControllers.values) {
        c.close();
      }
    });

    container.listen<AsyncValue<List<Tag>>>(
      watchTagsForBookmarkProvider('b1'),
      (_, _) {},
    );
    container.listen<AsyncValue<List<Tag>>>(
      watchTagsForBookmarkProvider('b2'),
      (_, _) {},
    );

    repo.perBookmarkControllers['b1']!.add([
      Tag(
        id: 'x',
        name: 'x',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ]);
    repo.perBookmarkControllers['b2']!.add(<Tag>[]);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(watchTagsForBookmarkProvider('b1')).value?.single.name,
      'x',
    );
    expect(
      container.read(watchTagsForBookmarkProvider('b2')).value,
      isEmpty,
    );
  });
}
