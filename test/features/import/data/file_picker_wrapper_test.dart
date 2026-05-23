import 'package:bookmarks/features/import/data/file_picker_wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilePickerWrapper.fake', () {
    test('returns the configured path on the happy path', () async {
      final picker = FilePickerWrapper.fake(() => '/tmp/fixture.html');
      expect(await picker.pickHtmlFile(), '/tmp/fixture.html');
    });

    test('returns null when the fake reports cancel', () async {
      final picker = FilePickerWrapper.fake(() => null);
      expect(await picker.pickHtmlFile(), isNull);
    });
  });
}
