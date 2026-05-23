import 'package:freezed_annotation/freezed_annotation.dart';

part 'import_progress.freezed.dart';

/// Per-batch progress fired by [BookmarkImportService.importTree] via
/// its optional `onProgress` callback. [itemsWritten] is monotonically
/// increasing and never exceeds [totalItems]. UI rendering should
/// derive the bar fill via `itemsWritten / totalItems` and the copy via
/// "Importing... $itemsWritten / $totalItems".
@freezed
abstract class ImportProgress with _$ImportProgress {
  const factory ImportProgress({
    required int itemsWritten,
    required int totalItems,
  }) = _ImportProgress;
}
