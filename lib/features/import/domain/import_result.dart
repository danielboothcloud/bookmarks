import 'package:freezed_annotation/freezed_annotation.dart';

part 'import_result.freezed.dart';

/// Aggregate counters produced by [BookmarkImportService.importTree] on
/// a successful import. [itemsSkipped] folds in
/// `ParsedBookmarksTree.unparseableItems` plus any write-time skips
/// (e.g. empty-URL bookmarks). [elapsed] is wall-clock duration from
/// the start of the writer to its return. [importedBookmarkIds] holds
/// the UUIDs of every bookmark the writer successfully persisted, in
/// walk order; consumed by the Story 5.2 background favicon backfill.
/// Folders are NOT included — folders don't have favicons.
@freezed
abstract class ImportResult with _$ImportResult {
  const factory ImportResult({
    required int foldersCreated,
    required int bookmarksImported,
    required int itemsSkipped,
    required Duration elapsed,
    required List<String> importedBookmarkIds,
  }) = _ImportResult;
}
