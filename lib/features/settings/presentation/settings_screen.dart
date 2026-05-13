import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/drive/drive_auth_providers.dart';
import '../../../core/drive/drive_auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

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

class _DriveSection extends ConsumerWidget {
  const _DriveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              Row(
                children: [
                  // TODO(4.5): wire disconnect
                  const OutlinedButton(
                    onPressed: null,
                    child: Text('Disconnect'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Available in a later update',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ],
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
}
