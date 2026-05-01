import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/app_error.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/folders/data/folder_repository.dart';
import 'package:bookmarks/features/folders/domain/folder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FolderRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FolderRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Folder make({
    required String id,
    String name = 'New folder',
    String? parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now =
        createdAt ?? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  test('save persists a new folder and getById returns it', () async {
    final folder = make(id: 'f-1', name: 'Personal');

    final saveResult = await repository.save(folder);
    expect(saveResult, isA<Ok<Folder, AppError>>());

    final getResult = await repository.getById('f-1');
    expect(getResult, isA<Ok<Folder, AppError>>());
    final fetched = (getResult as Ok<Folder, AppError>).value;
    expect(fetched.id, 'f-1');
    expect(fetched.name, 'Personal');
    expect(fetched.parentId, isNull);
  });

  test('save upserts on conflict (same id replaces row)', () async {
    final initial = make(id: 'f-1', name: 'first');
    await repository.save(initial);

    final updated = make(id: 'f-1', name: 'second');
    await repository.save(updated);

    final result = await repository.getById('f-1');
    final folder = (result as Ok<Folder, AppError>).value;
    expect(folder.name, 'second');

    final all = await db.select(db.folders).get();
    expect(all.length, 1);
  });

  test('watchAll emits new entries in createdAt asc order (oldest first)',
      () async {
    final older = make(
      id: 'older',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final newer = make(
      id: 'newer',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final stream = repository.watchAll();
    final emissions = <List<Folder>>[];
    final sub = stream.listen(emissions.add);

    await repository.save(older);
    await repository.save(newer);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final last = emissions.last;
    expect(last.map((f) => f.id).toList(), ['older', 'newer']);

    await sub.cancel();
  });

  test('getById returns Err(NotFoundError) for missing id', () async {
    final result = await repository.getById('does-not-exist');
    expect(result, isA<Err<Folder, AppError>>());
    final err = (result as Err<Folder, AppError>).error;
    expect(err, isA<NotFoundError>());
  });

  test('parentId round-trips correctly through save/getById', () async {
    final folder = make(id: 'child-1', name: 'Child', parentId: 'root-x');

    await repository.save(folder);
    final result = await repository.getById('child-1');

    final fetched = (result as Ok<Folder, AppError>).value;
    expect(fetched.parentId, 'root-x');
  });
}
