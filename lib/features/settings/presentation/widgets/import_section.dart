import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../import/application/import_providers.dart';
import '../../../import/domain/import_failure_reason.dart';
import '../../../import/domain/import_state.dart';

/// Settings → Import card. Sibling to `_DriveSection`; switches on
/// [ImportState] to render the correct subtree.
///
/// Visual / interaction rules:
///   * Idle / invalid-file-failed / storage-error-failed: title + body +
///     `FilledButton("Import from HTML file")`. (User cancel returns
///     straight to ImportIdle — no failed state recorded; see AC7.)
///   * Picking / writing / parsing: button hidden, progress text +
///     `LinearProgressIndicator` visible while writing.
///   * Succeeded: muted summary + a small "Import another file"
///     button that flips back to idle.
///
/// No cancel-mid-import surface in 5.1 — Esc during writing is a no-op
/// (out of scope; the import is fast enough that cancel adds more
/// complexity than user value).
class ImportSection extends ConsumerWidget {
  const ImportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(importNotifierProvider).value ?? const ImportIdle();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import bookmarks',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _ImportBody(state: state),
          ],
        ),
      ),
    );
  }
}

class _ImportBody extends ConsumerWidget {
  const _ImportBody({required this.state});

  final ImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textMuted,
    );

    switch (state) {
      case ImportIdle():
        return _IdleBody(
          subtitle:
              'Import from a browser bookmark export (HTML file).',
          mutedStyle: muted,
          onPressed: () =>
              ref.read(importNotifierProvider.notifier).pickAndImport(),
        );

      case ImportPicking():
        // Same body as idle but the button is disabled while the OS
        // picker is up — the picker is modal at the OS level, so the
        // disable is precautionary against a stray re-click.
        return _IdleBody(
          subtitle:
              'Import from a browser bookmark export (HTML file).',
          mutedStyle: muted,
          onPressed: null,
        );

      case ImportParsing():
        // Parsing is usually too fast to flash a dedicated UI; render
        // the writing-shape with a 0/0 bar so the transition isn't
        // visually jumpy.
        return const _WritingBody(itemsWritten: 0, totalItems: 0);

      case ImportWriting(:final progress):
        return _WritingBody(
          itemsWritten: progress.itemsWritten,
          totalItems: progress.totalItems,
        );

      case ImportSucceeded(:final result):
        final skipClause = result.itemsSkipped == 0
            ? ''
            : ' ${result.itemsSkipped} items skipped.';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Imported ${result.bookmarksImported} bookmarks, '
              '${result.foldersCreated} folders.$skipClause',
              style: muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => ref
                  .read(importNotifierProvider.notifier)
                  .resetToIdle(),
              child: const Text('Import another file'),
            ),
          ],
        );

      case ImportFailed(:final reason):
        return _FailedBody(reason: reason, mutedStyle: muted);
    }
  }
}

class _IdleBody extends StatelessWidget {
  const _IdleBody({
    required this.subtitle,
    required this.mutedStyle,
    required this.onPressed,
  });

  final String subtitle;
  final TextStyle? mutedStyle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(subtitle, style: mutedStyle),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: onPressed,
          child: const Text('Import from HTML file'),
        ),
      ],
    );
  }
}

class _WritingBody extends StatelessWidget {
  const _WritingBody({required this.itemsWritten, required this.totalItems});

  final int itemsWritten;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final value = totalItems == 0 ? null : itemsWritten / totalItems;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Importing... $itemsWritten / $totalItems',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(value: value),
      ],
    );
  }
}

class _FailedBody extends ConsumerWidget {
  const _FailedBody({
    required this.reason,
    required this.mutedStyle,
  });

  final ImportFailureReason reason;
  final TextStyle? mutedStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (reason) {
      case ImportFailureReason.invalidFile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This file doesn't appear to be a browser bookmark export.",
              style: mutedStyle,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: () => ref
                  .read(importNotifierProvider.notifier)
                  .pickAndImport(),
              child: const Text('Import from HTML file'),
            ),
          ],
        );

      case ImportFailureReason.storageError:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Couldn't save imported bookmarks. Try again?",
              style: mutedStyle,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: () => ref
                  .read(importNotifierProvider.notifier)
                  .pickAndImport(),
              child: const Text('Import from HTML file'),
            ),
          ],
        );
    }
  }
}
