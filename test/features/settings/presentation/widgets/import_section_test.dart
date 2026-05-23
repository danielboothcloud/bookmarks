import 'package:bookmarks/core/database/app_database.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/features/import/application/import_notifier.dart';
import 'package:bookmarks/features/import/application/import_providers.dart';
import 'package:bookmarks/features/import/data/file_picker_wrapper.dart';
import 'package:bookmarks/features/import/domain/import_failure_reason.dart';
import 'package:bookmarks/features/import/domain/import_progress.dart';
import 'package:bookmarks/features/import/domain/import_result.dart';
import 'package:bookmarks/features/import/domain/import_state.dart';
import 'package:bookmarks/features/settings/presentation/widgets/import_section.dart';
import 'package:bookmarks/main.dart' show appDatabaseProvider;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeImportNotifier extends ImportNotifier {
  _FakeImportNotifier(this._initial);
  final ImportState _initial;
  int pickAndImportCalls = 0;
  int resetCalls = 0;

  @override
  Future<ImportState> build() async => _initial;

  @override
  Future<void> pickAndImport() async {
    pickAndImportCalls++;
  }

  @override
  void resetToIdle() {
    resetCalls++;
  }
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.build(),
      home: const Scaffold(body: ImportSection()),
    ),
  );
}

ProviderContainer _container({required ImportState initial}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    filePickerProvider.overrideWithValue(FilePickerWrapper.fake(() => null)),
    importNotifierProvider.overrideWith(() => _FakeImportNotifier(initial)),
  ]);
}

void main() {
  testWidgets('idle: renders subtitle + enabled Import button',
      (tester) async {
    final container = _container(initial: const ImportIdle());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Import bookmarks'), findsOneWidget);
    expect(find.text('Import from a browser bookmark export (HTML file).'),
        findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import from HTML file'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('picking: button disabled while OS picker is up',
      (tester) async {
    final container = _container(initial: const ImportPicking());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import from HTML file'),
    );
    expect(button.onPressed, isNull,
        reason: 'button is precautionary-disabled during picker');
  });

  testWidgets('writing: shows N / M copy and LinearProgressIndicator',
      (tester) async {
    final container = _container(
      initial: const ImportWriting(
        ImportProgress(itemsWritten: 250, totalItems: 500),
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Importing... 250 / 500'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Import from HTML file'),
        findsNothing,
        reason: 'button hidden during writing');
  });

  testWidgets('succeeded: shows summary copy and "Import another file" link',
      (tester) async {
    final container = _container(
      initial: const ImportSucceeded(
        ImportResult(
          foldersCreated: 34,
          bookmarksImported: 487,
          itemsSkipped: 3,
          elapsed: Duration(seconds: 2),
          importedBookmarkIds: <String>[],
        ),
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Imported 487 bookmarks, 34 folders. 3 items skipped.'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Import another file'),
        findsOneWidget);
  });

  testWidgets('succeeded with zero skipped: summary omits the skip clause',
      (tester) async {
    final container = _container(
      initial: const ImportSucceeded(
        ImportResult(
          foldersCreated: 5,
          bookmarksImported: 20,
          itemsSkipped: 0,
          elapsed: Duration(milliseconds: 80),
          importedBookmarkIds: <String>[],
        ),
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Imported 20 bookmarks, 5 folders.'), findsOneWidget);
    expect(find.textContaining('items skipped'), findsNothing);
  });

  testWidgets('failed(invalidFile): renders calm inline message + button',
      (tester) async {
    final container = _container(
      initial: const ImportFailed(ImportFailureReason.invalidFile),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text("This file doesn't appear to be a browser bookmark export."),
        findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import from HTML file'),
    );
    expect(button.onPressed, isNotNull,
        reason: 'button remains enabled so user can pick a different file');
  });

  testWidgets('idle after cancel: no error surface, no failed copy',
      (tester) async {
    // Post-cancel the notifier transitions straight back to ImportIdle
    // (AC7). The widget must render the calm idle body without
    // surfacing any "doesn't appear" / "couldn't save" copy.
    final container = _container(initial: const ImportIdle());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text('Import from a browser bookmark export (HTML file).'),
        findsOneWidget,
        reason: 'cancel returns to idle — no error surface');
    expect(find.textContaining("doesn't appear"), findsNothing);
    expect(find.textContaining("Couldn't save"), findsNothing);
  });

  testWidgets('failed(storageError): renders muted retry copy + button',
      (tester) async {
    final container = _container(
      initial: const ImportFailed(ImportFailureReason.storageError),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save imported bookmarks. Try again?"),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Import from HTML file'),
        findsOneWidget);
  });
}
