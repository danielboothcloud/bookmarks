import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../application/bookmark_notifier.dart';
import '../../application/bookmark_providers.dart';
import '../../domain/bookmark.dart';

/// Inline-edit detail pane for the currently-selected bookmark (Story 1.4).
/// Two visual states:
///   - **Empty (AC7):** no selection -> neutral placeholder.
///   - **Populated (AC1):** selection -> favicon (36) + 3 editable fields +
///     full-width Open button.
///
/// Saves persist on Enter (single-line fields) or focus loss. The notes field
/// uses focus loss only because Enter inserts a newline in a multiline field.
class BookmarkDetailPane extends ConsumerStatefulWidget {
  const BookmarkDetailPane({super.key});

  @override
  ConsumerState<BookmarkDetailPane> createState() => _BookmarkDetailPaneState();
}

class _BookmarkDetailPaneState extends ConsumerState<BookmarkDetailPane> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();
  final _titleFocus = FocusNode(debugLabel: 'detail-title');
  final _urlFocus = FocusNode(debugLabel: 'detail-url');
  final _notesFocus = FocusNode(debugLabel: 'detail-notes');

  /// Tracks the id of the bookmark currently shown so we can re-init the
  /// controllers ONLY when the selection changes -- not on every rebuild
  /// caused by an external mutation (e.g. Story 1.3 favicon-fetch save).
  String? _lastBookmarkId;

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(_onAnyFocusLost);
    _urlFocus.addListener(_onAnyFocusLost);
    _notesFocus.addListener(_onAnyFocusLost);
    // Sync controllers off the build path so we don't mutate state during a
    // build phase. fireImmediately handles the case where a selection is
    // already set when this widget mounts.
    ref.listenManual<Bookmark?>(
      selectedBookmarkProvider,
      (_, next) => _syncControllers(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _titleFocus.removeListener(_onAnyFocusLost);
    _urlFocus.removeListener(_onAnyFocusLost);
    _notesFocus.removeListener(_onAnyFocusLost);
    _titleController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _titleFocus.dispose();
    _urlFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _syncControllers(Bookmark? bookmark) {
    if (bookmark == null) {
      if (_lastBookmarkId != null) {
        _titleController.text = '';
        _urlController.text = '';
        _notesController.text = '';
        _lastBookmarkId = null;
      }
      return;
    }
    if (_lastBookmarkId == bookmark.id) return;
    _titleController.text = bookmark.title;
    _urlController.text = bookmark.url;
    _notesController.text = bookmark.notes ?? '';
    _lastBookmarkId = bookmark.id;
  }

  // FocusNode listeners fire on BOTH gain and loss; _saveDirty is idempotent
  // (no-op when nothing changed) so calling it on every focus tick is safe
  // and avoids the bookkeeping of "previous focus state".
  void _onAnyFocusLost() => _saveDirty();

  /// Atomic save: builds the next bookmark from ALL three controllers in one
  /// pass, then writes via `updateBookmark`. This avoids a lost-update race
  /// when the user blurs across fields faster than Drift's stream can emit
  /// (each old per-field save read a stale snapshot for the OTHER two fields
  /// and overwrote concurrent edits).
  void _saveDirty() {
    final bookmark = ref.read(selectedBookmarkProvider);
    if (bookmark == null) return;

    // Empty URL guard: revert the controller silently. AC says Enter/blur
    // "saves" -- an empty URL is not a successful save path.
    final urlTrimmed = _urlController.text.trim();
    final String nextUrl;
    if (urlTrimmed.isEmpty) {
      _urlController.text = bookmark.url;
      nextUrl = bookmark.url;
    } else {
      nextUrl = urlTrimmed;
    }

    // Empty title falls back to the URL (matches addBookmark convention).
    final titleTrimmed = _titleController.text.trim();
    final nextTitle = titleTrimmed.isEmpty ? nextUrl : titleTrimmed;

    // Notes: preserve whitespace verbatim; null when empty so the column
    // round-trips through Drift's nullable mapping cleanly.
    final notesText = _notesController.text;
    final nextNotes = notesText.isEmpty ? null : notesText;

    if (nextTitle == bookmark.title &&
        nextUrl == bookmark.url &&
        nextNotes == bookmark.notes) {
      return;
    }

    ref.read(bookmarkNotifierProvider.notifier).updateBookmark(
          bookmark.copyWith(
            title: nextTitle,
            url: nextUrl,
            notes: nextNotes,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final bookmark = ref.watch(selectedBookmarkProvider);

    return Container(
      width: AppSpacing.detailPaneWidth,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContent,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: bookmark == null
          ? const _EmptyPlaceholder()
          : _PopulatedBody(
              bookmark: bookmark,
              titleController: _titleController,
              urlController: _urlController,
              notesController: _notesController,
              titleFocus: _titleFocus,
              urlFocus: _urlFocus,
              notesFocus: _notesFocus,
              onSave: _saveDirty,
            ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Select a bookmark',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}

class _PopulatedBody extends StatelessWidget {
  const _PopulatedBody({
    required this.bookmark,
    required this.titleController,
    required this.urlController,
    required this.notesController,
    required this.titleFocus,
    required this.urlFocus,
    required this.notesFocus,
    required this.onSave,
  });

  final Bookmark bookmark;
  final TextEditingController titleController;
  final TextEditingController urlController;
  final TextEditingController notesController;
  final FocusNode titleFocus;
  final FocusNode urlFocus;
  final FocusNode notesFocus;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Bookmark details: ${bookmark.title}',
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: FaviconWidget(
                  bookmarkId: bookmark.id,
                  faviconBase64: bookmark.faviconBase64,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: TextField(
                  controller: titleController,
                  focusNode: titleFocus,
                  maxLines: 1,
                  style: textTheme.titleLarge,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: onSave,
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: TextField(
                  controller: urlController,
                  focusNode: urlFocus,
                  maxLines: 1,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.accentLink,
                  ),
                  textInputAction: TextInputAction.done,
                  onEditingComplete: onSave,
                  decoration: const InputDecoration(
                    hintText: 'URL',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: TextField(
                  controller: notesController,
                  focusNode: notesFocus,
                  minLines: 3,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: () => openExternal(bookmark.url),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
