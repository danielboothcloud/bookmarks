import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drive/drive_auth_providers.dart';
import '../drive/drive_auth_state.dart';
import '../drive/drive_sync_providers.dart';
import '../drive/sync_status.dart';
import '../error/app_error.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Sidebar-footer indicator for the Drive sync engine's [SyncStatus].
///
/// Story 4.4 ships the green/amber/grey dot palette on top of the
/// textual label from 4.2. The displayed state is a pure function of
/// three inputs — `SyncStatus`, the live `sync_queue` pending count,
/// and the session-scoped `hasEverSynced` flag (see
/// [_indicatorStateFor] for the truth-table).
///
/// **Not a focus surface** — `docs/focus-model.md` Surface 12. The dot
/// itself is decorative (wrapped in [ExcludeSemantics]); the label is
/// the screen-reader surface and wraps the whole row in
/// [Semantics] with `liveRegion: true` so changes are announced
/// without explicit focus (NFR12).
///
/// **Collapsed mode** — when the sidebar is icon-only, the indicator
/// renders just the centred dot wrapped in a [Tooltip] surfacing the
/// full label on hover. The collapse breakpoint lives in
/// `AppSpacing.sidebarCollapseBreakpoint`; the indicator does not
/// observe the breakpoint itself, the parent sidebar passes the
/// `collapsed` flag.
///
/// **Reduce-motion** — the in-progress pulse animation honours
/// `MediaQuery.disableAnimations`. When true, the dot renders static.
/// See [_PulsingDot].
///
/// **Contrast** — `textMuted` (#9A9A9A) on `surfaceSidebar` (#2C2C2C)
/// is ~5.2:1 (WCAG AA for text). The three dot tokens
/// (`syncSynced` #6A9E6A, `syncUnsynced` #C8873A,
/// `syncUnavailable` #9A9A9A) each pass WCAG 1.4.11 Non-text Contrast
/// (3:1) at 7×7 px against the dark sidebar.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({this.collapsed = false, super.key});

  /// Passed by [Sidebar]: `true` when the sidebar is in icon-only
  /// mode. Drives the collapsed-tooltip layout branch.
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(driveAuthStateProvider).value;
    if (authState is! DriveAuthConnected) {
      return const SizedBox.shrink();
    }

    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus.idle();
    final pendingCount = ref.watch(syncQueuePendingCountProvider).value ?? 0;
    final hasEverSynced = ref.watch(hasEverSyncedProvider).value ?? false;

    final state = indicatorStateFor(
      status: status,
      pendingCount: pendingCount,
      hasEverSynced: hasEverSynced,
    );

    final Widget dot = state.pulsing
        ? _PulsingDot(color: state.dot, key: const ValueKey('sync-pulse'))
        : Container(
            width: _kDotSize,
            height: _kDotSize,
            decoration: BoxDecoration(
              color: state.dot,
              shape: BoxShape.circle,
            ),
          );

    final Widget decoratedDot = ExcludeSemantics(child: dot);

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 0,
          vertical: AppSpacing.sm,
        ),
        child: Semantics(
          liveRegion: true,
          label: state.label,
          child: Tooltip(
            message: state.label,
            child: Center(child: decoratedDot),
          ),
        ),
      );
    }

    final baseStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Semantics(
        liveRegion: true,
        label: state.label,
        child: Row(
          children: [
            decoratedDot,
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                state.label,
                overflow: TextOverflow.ellipsis,
                style: (baseStyle ?? const TextStyle()).copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 7×7 px dot. Local magic number — no other widget uses this size, so
/// keeping it out of `AppSpacing` avoids a token of single-use scope.
const double _kDotSize = 7;

/// Displayed state derived by [indicatorStateFor]. A vanilla Dart
/// record — no freezed type required. Exposed at library scope so
/// `@visibleForTesting` consumers can name the return type.
typedef IndicatorState = ({Color dot, String label, bool pulsing});

/// Pure mapping from `(SyncStatus, pendingCount, hasEverSynced)` to the
/// displayed indicator state.
///
/// **Truth table** (also reproduced in `docs/sync-model.md` § "The
/// status surface (Story 4.4)" and in `_bmad-output/planning-artifacts/
/// architecture.md` § "Status surface (Story 4.4)"):
///
/// | status                                     | pendingCount | hasEverSynced | dot                       | label                              |
/// |--------------------------------------------|--------------|----------------|---------------------------|-------------------------------------|
/// | `SyncPulling`                              | n/a          | n/a            | amber pulse               | `Pulling from Drive…`              |
/// | `SyncMerging`                              | n/a          | n/a            | amber pulse               | `Merging changes…`                 |
/// | `SyncPushing`                              | n/a          | n/a            | amber pulse               | `Syncing…`                         |
/// | `SyncFailed(NetworkError | AuthError)`     | n/a          | n/a            | grey                      | `Drive unavailable`                |
/// | `SyncFailed(other)`                        | n/a          | n/a            | grey                      | `Couldn't sync — will retry`       |
/// | `SyncAwaitingInitialPull`                  | n/a          | n/a            | amber                     | `Awaiting initial sync from Drive` |
/// | `SyncIdle` / `SyncSynced`                  | `> 0`        | n/a            | amber                     | `Unsynced changes`                 |
/// | `SyncIdle` / `SyncSynced`                  | `0`          | `true`         | green                     | `Synced with Drive`                |
/// | `SyncIdle` / `SyncSynced`                  | `0`          | `false`        | amber                     | `Awaiting initial sync from Drive` |
///
/// **Precedence** — in-progress states beat queue count; `SyncFailed`
/// beats both. The `switch` expression branches on `status` first;
/// queue count is the secondary discriminator only for the
/// idle/synced cases.
///
/// **AC coverage** — Story 4.4 AC2; satisfies FR25 (status surface),
/// FR26 (in-progress visual), FR27 (offline / unsynced surface);
/// NFR12 (sync failures are never silent — every grey state carries a
/// label).
///
/// Pure (no `this`, no widget context, no provider reads) so it is
/// unit-testable as a plain mapping. Exposed at library scope (rather
/// than as a static method) and annotated `@visibleForTesting` so the
/// indicator widget's tests can exercise the truth table directly
/// without spinning up a Widget tree.
@visibleForTesting
IndicatorState indicatorStateFor({
  required SyncStatus status,
  required int pendingCount,
  required bool hasEverSynced,
}) {
  return switch (status) {
    SyncPulling() => (
      dot: AppColors.syncUnsynced,
      label: 'Pulling from Drive…',
      pulsing: true,
    ),
    SyncMerging() => (
      dot: AppColors.syncUnsynced,
      label: 'Merging changes…',
      pulsing: true,
    ),
    SyncPushing() => (
      dot: AppColors.syncUnsynced,
      label: 'Syncing…',
      pulsing: true,
    ),
    SyncFailed(error: NetworkError()) ||
    SyncFailed(error: AuthError()) => (
      dot: AppColors.syncUnavailable,
      label: 'Drive unavailable',
      pulsing: false,
    ),
    SyncFailed() => (
      dot: AppColors.syncUnavailable,
      label: "Couldn't sync — will retry",
      pulsing: false,
    ),
    SyncAwaitingInitialPull() => (
      dot: AppColors.syncUnsynced,
      label: 'Awaiting initial sync from Drive',
      pulsing: false,
    ),
    SyncIdle() || SyncSynced() => switch ((pendingCount, hasEverSynced)) {
      (0, true) => (
        dot: AppColors.syncSynced,
        label: 'Synced with Drive',
        pulsing: false,
      ),
      (0, false) => (
        dot: AppColors.syncUnsynced,
        label: 'Awaiting initial sync from Drive',
        pulsing: false,
      ),
      _ => (
        dot: AppColors.syncUnsynced,
        label: 'Unsynced changes',
        pulsing: false,
      ),
    },
  };
}

/// 7×7 px dot whose opacity pulses 1.0 ↔ 0.4 over 1.2 s, used while
/// the engine is in any in-progress state (`SyncPulling`,
/// `SyncMerging`, `SyncPushing`).
///
/// **Reduce-motion** — when `MediaQuery.disableAnimations` is true,
/// the build returns a static dot with no [FadeTransition]. The
/// underlying [AnimationController] is still created (so a runtime
/// flip of the accessibility flag doesn't require disposing /
/// recreating the controller); the vsync overhead of a paused
/// ticker is negligible and avoids a fragile lifecycle edge case.
///
/// **Repaint scope** — wrapped in [RepaintBoundary] so the per-frame
/// repaint stays inside the 7×7 bounds, never invalidating the
/// surrounding sidebar.
///
/// **Lifecycle** — the controller is created in `initState` and
/// disposed in `dispose`; when the parent state machine transitions
/// away from in-progress, the element diff disposes this widget,
/// the controller releases its ticker, and the new static dot
/// takes its place.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, super.key});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.4).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: _kDotSize,
      height: _kDotSize,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
      ),
    );
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: disableAnimations
          ? dot
          : FadeTransition(opacity: _opacity, child: dot),
    );
  }
}
