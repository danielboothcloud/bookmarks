import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/folder_notifier.dart';
import '../../application/folder_providers.dart';
import '../../domain/folder.dart';

class FolderTree extends ConsumerWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(watchFoldersProvider);
    return foldersAsync.when(
      data: (folders) {
        if (folders.isEmpty) {
          return const _FolderTreeEmpty();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final folder in folders)
              FolderRow(key: ValueKey(folder.id), folder: folder),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _FolderTreeEmpty extends StatelessWidget {
  const _FolderTreeEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        'No folders yet',
        style: TextStyle(fontSize: 12, color: AppColors.textSidebar),
      ),
    );
  }
}

class FolderRow extends ConsumerStatefulWidget {
  const FolderRow({required this.folder, super.key});
  final Folder folder;

  @override
  ConsumerState<FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends ConsumerState<FolderRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _wasEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.folder.name);
    _focusNode = FocusNode(debugLabel: 'folder-row-${widget.folder.id}');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingEditId = ref.watch(pendingFolderEditIdProvider);
    final isEditing = pendingEditId == widget.folder.id;

    // Edge: the displayed name may have been updated externally (e.g. a
    // remote sync in a future story); resync the controller text on entering
    // edit mode so the user sees the freshest value. Done in the postframe
    // callback so build() stays pure -- in-build controller mutations notify
    // listeners during build and surface as widget-test instability.
    if (isEditing && !_wasEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.text = widget.folder.name;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        _focusNode.requestFocus();
      });
    }
    _wasEditing = isEditing;

    if (isEditing) {
      return _buildEditRow(context);
    }
    return _buildDisplayRow(context);
  }

  Widget _buildDisplayRow(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () => ref
          .read(pendingFolderEditIdProvider.notifier)
          .start(widget.folder.id),
      // TODO(post-2.1): right-click context menu for Rename/Delete.
      child: InkWell(
        onTap: () {
          // No-op in 2.1. Story 2.2 will navigate to the folder view.
        },
        child: _FolderRowFrame(
          child: Text(
            widget.folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSidebar,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditRow(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              // Cancel edit -- do NOT save the buffer. Restore the controller
              // text to the on-disk name so the next edit starts clean.
              _controller.text = widget.folder.name;
              ref.read(pendingFolderEditIdProvider.notifier).clear();
              return null;
            },
          ),
        },
        child: _FolderRowFrame(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSidebar,
            ),
            cursorColor: AppColors.accent,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: _commit,
            onTapOutside: (_) => _commit(_controller.text),
          ),
        ),
      ),
    );
  }

  void _commit(String value) {
    // Snapshot pending state synchronously so a tap-outside arriving after Esc
    // (via DismissIntent) doesn't double-fire the save.
    if (ref.read(pendingFolderEditIdProvider) != widget.folder.id) return;
    ref.read(pendingFolderEditIdProvider.notifier).clear();
    // Empty/identical name short-circuits inside renameFolder -- safe to call
    // unconditionally.
    ref
        .read(folderNotifierProvider.notifier)
        .renameFolder(widget.folder.id, value);
  }
}

/// Shared layout shell so the row height and chevron-slot reservation stay
/// identical between display and edit states (no layout shift).
class _FolderRowFrame extends StatelessWidget {
  const _FolderRowFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          // Reserve a 12px chevron slot for Story 2.2's expand/collapse
          // affordance. Empty in 2.1.
          const SizedBox(width: 12),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}
