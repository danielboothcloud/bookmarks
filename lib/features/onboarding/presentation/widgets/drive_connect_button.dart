import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/drive/drive_auth_providers.dart';
import '../../../../core/drive/drive_auth_state.dart';

/// The single CTA on the welcome screen. Disabled (label changes to
/// "Waiting for browser…") while a flow is in flight; the rest of the
/// time it's the primary entry point into [DriveAuthNotifier.connect].
class DriveConnectButton extends ConsumerWidget {
  const DriveConnectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(driveAuthStateProvider).value;
    final isConnecting = auth is DriveAuthConnecting;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isConnecting
            ? null
            : () => ref.read(driveAuthStateProvider.notifier).connect(),
        child: Text(
          isConnecting ? 'Waiting for browser…' : 'Connect Google Drive',
        ),
      ),
    );
  }
}
