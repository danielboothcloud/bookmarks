import 'import_failure_reason.dart';
import 'import_progress.dart';
import 'import_result.dart';

/// The state machine driving the import surface.
///
/// Transition graph:
///   ImportIdle
///     -> ImportPicking (user clicked the button; OS file picker open)
///        -> ImportIdle (user cancelled the picker; silent return)
///        -> ImportParsing (file chosen; parser running on the main thread)
///           -> ImportFailed(invalidFile) (empty tree)
///           -> ImportWriting (parse produced rows; writer running)
///              -> ImportSucceeded(result)
///              -> ImportFailed(storageError)
///   ImportSucceeded / ImportFailed
///     -> ImportIdle (via resetToIdle())
///
/// Sealed Dart class (no Freezed) — pattern parity with
/// `lib/core/drive/drive_auth_state.dart` predates the sealed-Freezed
/// migration; staying consistent with the local idiom matters more
/// here than codegen brevity. Pattern-match with `switch` in
/// consumers.
sealed class ImportState {
  const ImportState();
}

final class ImportIdle extends ImportState {
  const ImportIdle();
}

final class ImportPicking extends ImportState {
  const ImportPicking();
}

final class ImportParsing extends ImportState {
  const ImportParsing();
}

final class ImportWriting extends ImportState {
  const ImportWriting(this.progress);
  final ImportProgress progress;
}

final class ImportSucceeded extends ImportState {
  const ImportSucceeded(this.result);
  final ImportResult result;
}

final class ImportFailed extends ImportState {
  const ImportFailed(this.reason);
  final ImportFailureReason reason;
}
