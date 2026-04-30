import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/bookmark_notifier.dart';

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

  @override
  void initState() {
    super.initState();
    // Capture whatever held focus before the form opened so we can return
    // it on close (AC2: "focus returns to the previous context").
    _previousFocus = FocusManager.instance.primaryFocus;
  }

  @override
  void dispose() {
    // Restore previous focus before disposing this form's nodes.
    _previousFocus?.requestFocus();
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
    ref
        .read(bookmarkNotifierProvider.notifier)
        .addBookmark(url: url, title: _titleController.text);
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
                  // TODO(story-2.3): Folder selector slots in here.
                  // TODO(story-2.5): Tags field slots in here.
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(4),
                        child: TextButton(
                          onPressed: _cancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
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
