import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/drive/drive_auth_providers.dart';
import '../../../core/drive/drive_auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'widgets/drive_connect_button.dart';

/// The single guided flow in the app. Mounted by [AppRoutes.welcome]
/// as a top-level [GoRoute] (NOT inside [StatefulShellRoute]), so the
/// three-pane [AppShell] chrome never wraps it. Empty state from
/// Story 1.1 takes over the moment Drive is connected.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surfaceContent,
      body: SafeArea(
        // Horizontal centring only; vertical pin to upper-third via
        // the xxl top spacer below — matches the calm-utility tone of
        // existing empty states (Story 1.1).
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Bookmarks',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: AppColors.textBody,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                const DriveConnectButton(),
                const SizedBox(height: AppSpacing.md),
                const _WelcomeStatusMessage(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStatusMessage extends ConsumerWidget {
  const _WelcomeStatusMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(driveAuthStateProvider).value;
    final hasAttempted = ref.watch(hasAttemptedConnectProvider);

    String? message;
    switch (auth) {
      case null:
        message = null;
      case DriveAuthDisconnected():
        message = hasAttempted ? 'Drive connection needed to sync' : null;
      case DriveAuthConnecting():
        message =
            "We've opened your browser. Complete sign-in to continue.";
      case DriveAuthFailed():
        message = "Couldn't connect — try again";
      case DriveAuthConnected():
        message = null;
    }

    if (message == null) return const SizedBox.shrink();
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
      textAlign: TextAlign.center,
    );
  }
}
