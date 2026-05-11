import 'package:bookmarks/features/search/domain/search_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('searchTokens', () {
    test('empty input returns empty list', () {
      expect(searchTokens(''), isEmpty);
    });

    test('whitespace-only input returns empty list', () {
      expect(searchTokens('   \t\n '), isEmpty);
    });

    test('single bareword returns one token', () {
      expect(searchTokens('flutter'), ['flutter']);
    });

    test('multiple barewords return all tokens in order', () {
      expect(searchTokens('flutter docs widgets'),
          ['flutter', 'docs', 'widgets']);
    });

    test('punctuation strips to spaces (token boundary)', () {
      expect(searchTokens('dart.dev'), ['dart', 'dev']);
    });

    test('all-special-characters input returns empty list', () {
      expect(searchTokens('!!!'), isEmpty);
      expect(searchTokens('---'), isEmpty);
      expect(searchTokens('()()()'), isEmpty);
    });

    test('Unicode letters are preserved as bareword characters', () {
      expect(searchTokens('café résumé'), ['café', 'résumé']);
    });

    test('digits and underscores are bareword characters', () {
      expect(searchTokens('foo_2 bar123'), ['foo_2', 'bar123']);
    });

    test('source case is preserved (lowering happens at consumer)', () {
      expect(searchTokens('Flutter Docs'), ['Flutter', 'Docs']);
    });

    test('tabs and newlines split tokens like spaces', () {
      expect(searchTokens('foo\tbar\nbaz'), ['foo', 'bar', 'baz']);
    });

    test('mixed punctuation and barewords', () {
      expect(searchTokens('https://dart.dev/?q=foo+bar'),
          ['https', 'dart', 'dev', 'q', 'foo', 'bar']);
    });
  });
}
