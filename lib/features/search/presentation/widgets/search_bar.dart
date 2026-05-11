import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../bookmarks/application/bookmark_providers.dart';
import '../../application/search_providers.dart';

/// Persistent search bar at the top of the content area (Story 3.1).
/// Custom [Material] + [TextField] rather than M3's `SearchBar` so we
/// keep the calm-utility styling consistent with the rest of the app
/// (single border, muted hint, no elevation).
///
/// The [TextEditingController] is owned by this widget and mirrors
/// [searchQueryProvider] (which is the source-of-truth). `onChanged`
/// pushes keystrokes into the provider; that's the only writer in 3.1,
/// so we don't need a `ref.listen` reverse-binding (would be required if
/// 3.2's clear button or any other external writer landed).
///
/// FocusNode is owned by [searchBarFocusNodeProvider] so AppShell's
/// `FocusSearchIntent` action can request focus from outside the widget
/// tree without a brittle GlobalKey.
class BookmarkSearchBar extends ConsumerStatefulWidget {
  const BookmarkSearchBar({super.key});

  @override
  ConsumerState<BookmarkSearchBar> createState() => _BookmarkSearchBarState();
}

class _BookmarkSearchBarState extends ConsumerState<BookmarkSearchBar> {
  late final TextEditingController _controller;
  FocusNode? _attachedFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(searchQueryProvider),
    );
  }

  @override
  void dispose() {
    _attachedFocusNode?.removeListener(_handleFocusChange);
    _controller.dispose();
    super.dispose();
  }

  void _attachFocusListener(FocusNode node) {
    if (identical(_attachedFocusNode, node)) return;
    _attachedFocusNode?.removeListener(_handleFocusChange);
    node.addListener(_handleFocusChange);
    _attachedFocusNode = node;
  }

  void _handleFocusChange() {
    final node = _attachedFocusNode;
    if (node == null || !node.hasFocus) return;
    // AC1: when focus lands in the field via Cmd+F, position the cursor at
    // end-of-text rather than selecting all. Keeps appended-typing the
    // dominant interaction. Defer one frame so any default selection
    // behaviour from TextField's own focus-handling has settled before we
    // overwrite the selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onSubmitted(String _) {
    final results = ref.read(searchResultsProvider).value;
    if (results == null || results.isEmpty) return;
    final first = results.first;
    ref.read(selectedBookmarkIdProvider.notifier).select(first.id);
    openExternal(first.url);
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = ref.watch(searchBarFocusNodeProvider);
    _attachFocusListener(focusNode);
    final searchActive = ref.watch(searchActiveProvider);
    final textTheme = Theme.of(context).textTheme;

    // Reverse-binding: provider → controller. The clear button (this widget)
    // and AppShell's Esc cascade both write to searchQueryProvider; this
    // listen propagates those external writes back to the visible field.
    // The early-return guard prevents a feedback loop with onChanged
    // (which writes the same value back to the provider).
    ref.listen<String>(searchQueryProvider, (_, next) {
      if (_controller.text == next) return;
      _controller.text = next;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContent,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TextField(
        controller: _controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          hintText: 'Search bookmarks',
          border: InputBorder.none,
          isDense: true,
          hintStyle: textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textMuted,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          suffixIcon: searchActive
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textMuted,
                  tooltip: 'Clear search',
                  splashRadius: 16,
                  onPressed: () {
                    ref.read(searchQueryProvider.notifier).clear();
                  },
                )
              : null,
        ),
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textBody),
        onChanged: (value) {
          ref.read(searchQueryProvider.notifier).set(value);
        },
        // Pressing Enter while the field has focus and results exist:
        // select + open the first result (Story 3.1 keyboard convenience).
        // Full arrow-key navigation through results is deferred to 3.2.
        onSubmitted: _onSubmitted,
      ),
    );
  }
}
