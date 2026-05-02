import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../folders/application/folder_providers.dart';
import '../../application/bookmark_notifier.dart';
import 'bookmark_folder_field.dart';

class InlineAddForm extends ConsumerStatefulWidget {
  const InlineAddForm({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<InlineAddForm> createState() => _InlineAddFormState();
}

class _InlineAddFormState extends ConsumerState<InlineAddForm> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  final _urlFocusNode = FocusNode(debugLabel: 'inline-add-url');
  final _titleFocusNode = FocusNode(debugLabel: 'inline-add-title');
  bool _urlError = false;
  FocusNode? _previousFocus;
  String? _pendingFolderId;

  @override
  void initState() {
    super.initState();
    // Capture whatever held focus before the form opened so we can return
    // it on close (AC2: "focus returns to the previous context").
    _previousFocus = FocusManager.instance.primaryFocus;
    // Pre-fill from the sidebar's current folder selection. Reads the
    // notifier directly (no BuildContext required), avoiding a post-frame
    // flicker. `selectedFolderIdProvider` is cleared by the navrail Folders
    // tap (Story 2.2), so a non-null value reliably means "user is currently
    // viewing this folder" -- the right intent signal for the new bookmark.
    _pendingFolderId = ref.read(selectedFolderIdProvider);
  }

  @override
  void dispose() {
    // Restore previous focus before disposing this form's nodes -- but ONLY
    // when the captured node is still attached. If the user opened the form
    // via the EmptyState's "Add bookmark" CTA, that button is now unmounted
    // and `_previousFocus` points at a disposed FocusNode; calling
    // requestFocus() on it leaves primary focus in a dead state OUTSIDE the
    // AppShell's Shortcuts subtree, breaking Cmd+N until the user clicks
    // back into the tree. Skipping the restore lets Flutter re-parent focus
    // to the nearest live FocusScope (which IS inside AppShell's Shortcuts).
    final prev = _previousFocus;
    if (prev != null && prev.context != null) {
      prev.requestFocus();
    }
    _urlController.dispose();
    _titleController.dispose();
    _urlFocusNode.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _save() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = true);
      _urlFocusNode.requestFocus();
      return;
    }
    ref.read(bookmarkNotifierProvider.notifier).addBookmark(
          url: url,
          title: _titleController.text,
          folderId: _pendingFolderId,
        );
    widget.onClose();
  }

  void _cancel() {
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: 'Add bookmark form opened',
      liveRegion: true,
      container: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _cancel();
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContent,
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: TextField(
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      onChanged: (v) {
                        if (_urlError && v.trim().isNotEmpty) {
                          setState(() => _urlError = false);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Paste a URL',
                        border: const OutlineInputBorder(),
                        enabledBorder: _urlError
                            ? const OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.accent),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'OPTIONAL',
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Folder selector (Story 2.3). Order 3; tags will land at
                  // order 4 in Story 2.5 -- leaving 4 reserved here means
                  // 2.5 doesn't have to renumber Save/Cancel again.
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(3),
                    child: BookmarkFolderField(
                      currentFolderId: _pendingFolderId,
                      onChanged: (next) =>
                          setState(() => _pendingFolderId = next),
                    ),
                  ),
                  // TODO(story-2.5): Tags field slots in here at order 4.
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(6),
                        child: TextButton(
                          onPressed: _cancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(5),
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
