import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/error/result.dart';
import 'package:bookmarks/features/bookmarks/data/bookmark_repository.dart';
import 'package:bookmarks/features/bookmarks/domain/bookmark.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BookmarkRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = BookmarkRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Bookmark make({
    required String id,
    String url = 'https://example.com',
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = createdAt ?? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    return Bookmark(
      id: id,
      url: url,
      title: title ?? url,
      createdAt: now,
      updatedAt: updatedAt ?? now,
    );
  }

  test('save persists a new bookmark and getById returns it', () async {
    final bookmark = make(id: 'abc-1');

    final saveResult = await repository.save(bookmark);
    expect(saveResult, isA<Ok<Bookmark, Object>>());

    final getResult = await repository.getById('abc-1');
    expect(getResult, isA<Ok<Bookmark, Object>>());
    final fetched = (getResult as Ok<Bookmark, Object>).value;
    expect(fetched.id, 'abc-1');
    expect(fetched.url, 'https://example.com');
  });

  test('save upserts on conflict (same id replaces row)', () async {
    final initial = make(id: 'abc-1', title: 'first');
    await repository.save(initial);

    final updated = make(id: 'abc-1', title: 'second');
    await repository.save(updated);

    final result = await repository.getById('abc-1');
    final bookmark = (result as Ok<Bookmark, Object>).value;
    expect(bookmark.title, 'second');

    // Still only one row in DB.
    final all = await db.select(db.bookmarks).get();
    expect(all.length, 1);
  });

  test('watchAll emits new entries in createdAt desc order', () async {
    final older = make(
      id: 'older',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final newer = make(
      id: 'newer',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final stream = repository.watchAll();
    final emissions = <List<Bookmark>>[];
    final sub = stream.listen(emissions.add);

    await repository.save(older);
    await repository.save(newer);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final last = emissions.last;
    expect(last.map((b) => b.id).toList(), ['newer', 'older']);

    await sub.cancel();
  });

  test('getById returns Err for missing id', () async {
    final result = await repository.getById('does-not-exist');
    expect(result, isA<Err<Bookmark, Object>>());
  });

  test('IDs are preserved as strings (not auto-increment ints)', () async {
    final bookmark = make(id: 'string-uuid-v4-shape');
    await repository.save(bookmark);

    final raw = await db.select(db.bookmarks).getSingle();
    expect(raw.id, 'string-uuid-v4-shape');
    expect(raw.id, isA<String>());
  });
}
