import 'dart:convert';
import 'dart:io';

import 'package:bookmarks/core/drive/file_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileTokenStorage', () {
    late Directory tmp;
    late FileTokenStorage storage;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('file_token_storage_test');
      storage = FileTokenStorage(directory: tmp);
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('read on missing file returns null', () async {
      expect(await storage.read(key: 'drive.access_token'), isNull);
    });

    test('write then read round-trips', () async {
      await storage.write(key: 'drive.access_token', value: 'at-1');
      expect(await storage.read(key: 'drive.access_token'), 'at-1');
    });

    test('write creates the directory if missing', () async {
      final nested = Directory('${tmp.path}/missing/path');
      final s = FileTokenStorage(directory: nested);
      await s.write(key: 'k', value: 'v');
      expect(nested.existsSync(), isTrue);
      expect(File('${nested.path}/secrets.json').existsSync(), isTrue);
      expect(await s.read(key: 'k'), 'v');
    });

    test('write with null value deletes the key', () async {
      await storage.write(key: 'k', value: 'v');
      await storage.write(key: 'k', value: null);
      expect(await storage.read(key: 'k'), isNull);
    });

    test('delete removes a key but leaves others', () async {
      await storage.write(key: 'a', value: '1');
      await storage.write(key: 'b', value: '2');
      await storage.delete(key: 'a');
      expect(await storage.read(key: 'a'), isNull);
      expect(await storage.read(key: 'b'), '2');
    });

    test('readAll returns a snapshot copy', () async {
      await storage.write(key: 'a', value: '1');
      await storage.write(key: 'b', value: '2');
      final all = await storage.readAll();
      expect(all, {'a': '1', 'b': '2'});
    });

    test('containsKey reflects current state', () async {
      expect(await storage.containsKey(key: 'a'), isFalse);
      await storage.write(key: 'a', value: '1');
      expect(await storage.containsKey(key: 'a'), isTrue);
    });

    test('deleteAll removes the file', () async {
      await storage.write(key: 'a', value: '1');
      await storage.deleteAll();
      expect(File('${tmp.path}/secrets.json').existsSync(), isFalse);
      expect(await storage.read(key: 'a'), isNull);
    });

    test('concurrent writes serialise without corruption', () async {
      // Fire 20 concurrent writes; final state must be one of them and
      // the file must remain valid JSON throughout.
      await Future.wait(
        List.generate(20, (i) => storage.write(key: 'k', value: '$i')),
      );
      final raw = await File('${tmp.path}/secrets.json').readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['k'], isA<String>());
      // Final value must be a valid candidate.
      final v = int.parse(decoded['k'] as String);
      expect(v >= 0 && v < 20, isTrue);
    });

    test('corrupt JSON is quarantined and treated as empty', () async {
      final f = File('${tmp.path}/secrets.json');
      await f.create(recursive: true);
      await f.writeAsString('{this is not valid JSON');

      expect(await storage.read(key: 'anything'), isNull);
      expect(f.existsSync(), isFalse,
          reason: 'original file moved to .corrupt');
      expect(File('${tmp.path}/secrets.json.corrupt').existsSync(), isTrue);
    });

    test('write after corrupt quarantine still works (start fresh)',
        () async {
      final f = File('${tmp.path}/secrets.json');
      await f.create(recursive: true);
      await f.writeAsString('garbage');

      // First read triggers quarantine.
      await storage.read(key: 'irrelevant');
      // Subsequent write should succeed with empty starting state.
      await storage.write(key: 'k', value: 'v');
      expect(await storage.read(key: 'k'), 'v');
    });
  });
}
