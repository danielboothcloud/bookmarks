import 'package:file_picker/file_picker.dart';

/// Thin seam over `file_picker` so tests can inject a deterministic
/// outcome (a fixture path, or `null` for cancel) without spinning up
/// a real OS file dialog.
///
/// Production code reads the [.real] singleton; tests override
/// `filePickerProvider` with [.fake]. Mirrors the pattern used by
/// `httpClientProvider` / `flutterSecureStorageProvider` from Epic 4
/// — a one-method abstraction is enough; any extra surface area would
/// be guesswork until the test suite or a second caller demands it.
abstract class FilePickerWrapper {
  const FilePickerWrapper._();

  factory FilePickerWrapper.real() = _RealFilePicker;

  /// Builds a fake whose [pickHtmlFile] returns the value produced by
  /// [pickPath] on each call. Pass `() => null` for the cancel path.
  factory FilePickerWrapper.fake(String? Function() pickPath) =
      _FakeFilePicker;

  /// Opens an OS file picker filtered to `.html` / `.htm` and returns
  /// the chosen absolute path, or `null` if the user cancelled.
  Future<String?> pickHtmlFile();
}

class _RealFilePicker extends FilePickerWrapper {
  _RealFilePicker() : super._();

  @override
  Future<String?> pickHtmlFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // `.htm` accepted as a defensive against Safari which sometimes
      // uses the short extension; the parser doesn't care which form
      // it gets.
      allowedExtensions: const ['html', 'htm'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null) return null;
    final files = result.files;
    if (files.isEmpty) return null;
    return files.single.path;
  }
}

class _FakeFilePicker extends FilePickerWrapper {
  _FakeFilePicker(this._pick) : super._();

  final String? Function() _pick;

  @override
  Future<String?> pickHtmlFile() async => _pick();
}
