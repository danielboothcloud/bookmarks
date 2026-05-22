import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/drive/drive_auth_providers.dart';
import '../../../core/drive/drive_auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/drive_account_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        _DriveSection(),
      ],
    );
  }
}

class _DriveSection extends ConsumerStatefulWidget {
  const _DriveSection();

  @override
  ConsumerState<_DriveSection> createState() => _DriveSectionState();
}

class _DriveSectionState extends ConsumerState<_DriveSection> {
  bool _showConfirmation = false;
  bool _disconnecting = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(driveAuthStateProvider).value;
    final email = switch (auth) {
      DriveAuthConnected(:final email) => email,
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drive', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (email != null) ...[
              Text(email, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Bookmarks sync to this account's Drive",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_showConfirmation)
                _DisconnectConfirmation(
                  disconnecting: _disconnecting,
                  onCancel: _disconnecting
                      ? null
                      : () => setState(() => _showConfirmation = false),
                  onConfirm: _disconnecting ? null : _runDisconnect,
                )
              else
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _showConfirmation = true),
                  child: const Text('Disconnect'),
                ),
            ] else ...[
              const Text('Not connected'),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () =>
                    ref.read(driveAuthStateProvider.notifier).connect(),
                child: const Text('Connect Google Drive'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runDisconnect() async {
    setState(() => _disconnecting = true);
    try {
      await ref.read(driveAccountControllerProvider.notifier).disconnect();
    } finally {
      // The router redirects /settings -> /welcome on auth-state change,
      // typically unmounting this widget before this runs; the `mounted`
      // guard keeps the setState safe if the router does NOT unmount
      // (e.g. an unmounted Settings inside a test harness).
      if (mounted) {
        setState(() {
          _disconnecting = false;
          _showConfirmation = false;
        });
      }
    }
  }
}

class _DisconnectConfirmation extends StatelessWidget {
  const _DisconnectConfirmation({
    required this.disconnecting,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool disconnecting;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    // Local Shortcuts/Actions wrap so Esc dismisses the confirmation
    // without bubbling to the AppShell's AppDismissIntent cascade.
    // Pattern reference: folder_tree.dart (Story 2.4 cascade-delete
    // inline confirmation).
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onCancel?.call();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disconnect from Drive? Local bookmarks stay.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  FilledButton(
                    autofocus: true,
                    onPressed: onConfirm,
                    child: const Text('Disconnect'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
