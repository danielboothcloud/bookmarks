import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../folders/application/folder_providers.dart';
import '../../../folders/domain/folder.dart';
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
  List<String> _pendingTags = <String>[];

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
          tagNames: _pendingTags,
        );
    widget.onClose();
  }

  void _cancel() {
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    // Self-heal: when a folder referenced by [_pendingFolderId] is removed
    // (cascade-delete in Story 2.4 or a future sync-merge removal), reset
    // the pending id so Save doesn't dispatch a dead folderId. The
    // BookmarkFolderField already shows "No folder" defensively when the
    // id is missing (Story 2.3); resetting here makes the SAVED bookmark
    // match what the field displays. ref.listen is build-safe in
    // flutter_riverpod -- no manual disposal needed (vs ref.listenManual).
    ref.listen<AsyncValue<List<Folder>>>(
      watchFoldersProvider,
      (_, next) {
        final pending = _pendingFolderId;
        if (pending == null) return;
        final folders = next.value ?? const <Folder>[];
        if (folders.any((f) => f.id == pending)) return;
        if (mounted) {
          setState(() => _pendingFolderId = null);
        }
      },
    );
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
                  const SizedBox(height: AppSpacing.md),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(4),
                    child: _InlineFormTagsField(
                      initialTags: _pendingTags,
                      onChanged: (next) =>
                          setState(() => _pendingTags = next),
                    ),
                  ),
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

/// Form-local tags input. Holds the pending tag list in StatefulWidget state
/// (NOT a Notifier) because the list's lifecycle matches the form: Esc / Save
/// closes the form and the list goes with it. Uses M3 InputChip (in-flight
/// unconfirmed entry semantic) rather than FilterChip (which would claim the
/// tag is "currently filtering" the not-yet-existent bookmark).
class _InlineFormTagsField extends StatefulWidget {
  const _InlineFormTagsField({
    required this.initialTags,
    required this.onChanged,
  });

  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_InlineFormTagsField> createState() => _InlineFormTagsFieldState();
}

class _InlineFormTagsFieldState extends State<_InlineFormTagsField> {
  late final List<String> _tags = List<String>.from(widget.initialTags);
  final _controller = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'inline-add-tags');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text;
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      _controller.clear();
      return;
    }
    // Dedup case-insensitively while preserving insertion order.
    final seen = _tags.map((s) => s.toLowerCase()).toSet();
    var changed = false;
    for (final p in parts) {
      if (seen.add(p.toLowerCase())) {
        _tags.add(p);
        changed = true;
      }
    }
    _controller.clear();
    if (changed) {
      widget.onChanged(List<String>.from(_tags));
      setState(() {});
    }
  }

  void _remove(String tag) {
    _tags.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
    widget.onChanged(List<String>.from(_tags));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => _remove(tag),
                    deleteIconColor: AppColors.textMuted,
                    backgroundColor:
                        AppColors.accent.withValues(alpha: 0.10),
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textBody,
                    ),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          onChanged: (next) {
            if (next.endsWith(',')) _commit();
          },
          decoration: const InputDecoration(
            hintText: 'Add tags (comma to separate)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
