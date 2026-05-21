import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drive/drive_auth_providers.dart';
import '../drive/drive_auth_state.dart';
import '../drive/drive_sync_providers.dart';
import '../drive/sync_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Sidebar-footer indicator for the Drive sync engine's
/// [SyncStatus]. Story 4.2 ships the textual surface; Story 4.4 will
/// upgrade to the green/amber/grey dot palette. Not a focus surface --
/// see `docs/focus-model.md` Surface 12.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({this.collapsed = false, super.key});

  /// When the sidebar is collapsed to icon-only width, the indicator
  /// becomes a small "•" tooltip-equivalent. For 4.2 we keep it
  /// invisible in collapsed mode -- there's no icon, and a single
  /// character without context wastes vertical space.
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(driveAuthStateProvider).value;
    if (authState is! DriveAuthConnected) {
      return const SizedBox.shrink();
    }

    if (collapsed) {
      return const SizedBox.shrink();
    }

    final statusAsync = ref.watch(syncStatusProvider);
    final label = statusAsync.when(
      data: _labelFor,
      loading: () => null,
      error: (_, _) => 'Sync engine unavailable',
    );
    if (label == null) return const SizedBox.shrink();

    final baseStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  static String _labelFor(SyncStatus status) {
    return switch (status) {
      SyncIdle() => 'Synced with Drive',
      SyncPulling() => 'Pulling from Drive…',
      SyncMerging() => 'Merging changes…',
      SyncPushing() => 'Syncing…',
      SyncSynced() => 'Synced with Drive',
      SyncFailed() => "Couldn't sync — will retry",
      SyncAwaitingInitialPull() => 'Awaiting initial sync from Drive',
    };
  }
}
