import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/util/url_launcher_service.dart';
import '../../../../core/widgets/favicon_widget.dart';
import '../../../tags/application/tag_notifier.dart';
import '../../../tags/application/tag_providers.dart';
import '../../../tags/domain/tag.dart';
import '../../application/bookmark_notifier.dart';
import '../../application/bookmark_providers.dart';
import '../../domain/bookmark.dart';
import 'bookmark_folder_field.dart';

/// Inline-edit detail pane for the currently-selected bookmark (Story 1.4).
/// Three visual states:
///   - **Empty (AC7):** no selection -> neutral placeholder.
///   - **Populated (AC1):** selection -> favicon + 3 editable fields + Open
///     button + trash icon (Story 1.5 trigger).
///   - **Confirming delete (Story 1.5):** trash icon was clicked or Delete key
///     pressed -> the pane swaps to a centered "Delete this bookmark?" view
///     with Cancel / Delete buttons. Replaces the inline-row confirmation
///     called for in the original story spec; the inline pattern is preserved
///     (no modal dialog) but moved to the detail pane for discoverability.
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

  /// Atomic save from focus loss / Enter. Delegates to [_writeNext] so the
  /// merge logic stays single-source.
  void _saveDirty() => _writeNext();

  /// Builds the next bookmark from the LIVE bookmark + current controller
  /// text + an optional folder override, then dispatches a single
  /// `updateBookmark`. Reading fresh state inside this method (rather than
  /// trusting a closure-captured bookmark) prevents a lost-update race when
  /// a folder pick lands between `_saveDirty`'s text-save dispatch and the
  /// Drift stream's re-emit -- without the merge, the folder write would
  /// copyWith over the stale closure values and clobber the in-flight text
  /// edit. Same atomic-merge rationale as Story 1.4's per-field save fix.
  void _writeNext({String? Function()? folderIdOverride}) {
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

    final nextFolderId =
        folderIdOverride != null ? folderIdOverride() : bookmark.folderId;

    if (nextTitle == bookmark.title &&
        nextUrl == bookmark.url &&
        nextNotes == bookmark.notes &&
        nextFolderId == bookmark.folderId) {
      return;
    }

    ref.read(bookmarkNotifierProvider.notifier).updateBookmark(
          bookmark.copyWith(
            title: nextTitle,
            url: nextUrl,
            notes: nextNotes,
            folderId: nextFolderId,
          ),
        );
  }

  /// Confirm delete from the detail-pane confirmation view. Computes the
  /// next-item id from the live list BEFORE dispatching the delete so
  /// selection migration uses the correct successor (the deleted item is
  /// still present in the list at this point). Mirrors the selection-flow
  /// laid out in the Story 1.5 spec, but driven from the pane rather than
  /// the list-item widget.
  void _confirmDelete(Bookmark bookmark) {
    final list = ref.read(watchBookmarksProvider).value;
    String? nextId;
    if (list != null) {
      final idx = list.indexWhere((b) => b.id == bookmark.id);
      if (idx >= 0 && idx + 1 < list.length) {
        nextId = list[idx + 1].id;
      }
    }

    // Capture BEFORE clearing pendingDelete / dispatching delete -- once the
    // stream emits the post-delete list, selectedBookmarkProvider derives null
    // for the deleted id and the comparison loses meaning.
    final wasSelected =
        ref.read(selectedBookmarkIdProvider) == bookmark.id;

    ref.read(pendingDeleteIdProvider.notifier).clear();
    ref.read(bookmarkNotifierProvider.notifier).deleteBookmark(bookmark.id);

    // Only migrate selection when the deleted bookmark IS the selected one.
    // Today every code path into _confirmDelete has the bookmark selected
    // (trash icon shows on the selected detail-pane body; AppShell shortcut
    // prompts the selected id). The guard is anti-fragility for any future
    // surface (context menu, batch delete) that prompts a non-selected id --
    // without it, a delete from such a surface would silently clobber the
    // user's deliberate selection on a different bookmark.
    if (wasSelected) {
      final selection = ref.read(selectedBookmarkIdProvider.notifier);
      if (nextId != null) {
        selection.select(nextId);
      } else {
        selection.clear();
      }
    }
  }

  void _cancelDelete() =>
      ref.read(pendingDeleteIdProvider.notifier).clear();

  /// Routes a folder pick from `BookmarkFolderField` through the merged-write
  /// path. Going through [_writeNext] (rather than dispatching a folder-only
  /// copyWith) means any uncommitted text-controller edit is folded into the
  /// SAME write, eliminating the stale-closure race. The idempotent guard --
  /// "no-op when nothing changed" -- lives inside [_writeNext] and now covers
  /// folderId too, so re-picking the current folder still avoids a write.
  void _onFolderChanged(String? newFolderId) {
    _writeNext(folderIdOverride: () => newFolderId);
  }

  @override
  Widget build(BuildContext context) {
    final bookmark = ref.watch(selectedBookmarkProvider);
    final pendingDeleteId = ref.watch(pendingDeleteIdProvider);
    final isConfirming =
        bookmark != null && pendingDeleteId == bookmark.id;

    return Container(
      width: AppSpacing.detailPaneWidth,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContent,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: bookmark == null
          ? const _EmptyPlaceholder()
          : isConfirming
              ? _DeleteConfirmation(
                  bookmark: bookmark,
                  onCancel: _cancelDelete,
                  onConfirm: () => _confirmDelete(bookmark),
                )
              : _PopulatedBody(
                  bookmark: bookmark,
                  titleController: _titleController,
                  urlController: _urlController,
                  notesController: _notesController,
                  titleFocus: _titleFocus,
                  urlFocus: _urlFocus,
                  notesFocus: _notesFocus,
                  onSave: _saveDirty,
                  onPromptDelete: () => ref
                      .read(pendingDeleteIdProvider.notifier)
                      .prompt(bookmark.id),
                  onFolderChanged: _onFolderChanged,
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
    required this.onPromptDelete,
    required this.onFolderChanged,
  });

  final Bookmark bookmark;
  final TextEditingController titleController;
  final TextEditingController urlController;
  final TextEditingController notesController;
  final FocusNode titleFocus;
  final FocusNode urlFocus;
  final FocusNode notesFocus;
  final VoidCallback onSave;
  final VoidCallback onPromptDelete;
  final ValueChanged<String?> onFolderChanged;

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
              // Header: counterweight + centered favicon + trash icon. The
              // 48-px counterweight matches IconButton's default min-size so
              // the favicon stays visually centered.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 48, height: 48),
                  FaviconWidget(
                    bookmarkId: bookmark.id,
                    faviconBase64: bookmark.faviconBase64,
                    size: 36,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.textMuted,
                    ),
                    tooltip: 'Delete bookmark',
                    onPressed: onPromptDelete,
                  ),
                ],
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
              // Folder assignment (Story 2.3). Sits between URL and Notes --
              // matches the UX-spec form-field order (URL -> Title -> Folder
              // -> Tags -> Notes). Selection commits immediately on pick;
              // does NOT participate in the focus-loss save cascade.
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: BookmarkFolderField(
                  currentFolderId: bookmark.folderId,
                  onChanged: onFolderChanged,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Tags row (Story 2.5). Slots between Folder (3) and Notes (5)
              // per the UX-spec form-field order URL -> Title -> Folder ->
              // Tags -> Notes. Notes/Open renumbered from 4/5 to 5/6 to make
              // room.
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: _TagsRow(bookmarkId: bookmark.id, editable: true),
              ),
              const SizedBox(height: AppSpacing.md),
              FocusTraversalOrder(
                order: const NumericFocusOrder(5),
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
                order: const NumericFocusOrder(6),
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

class _ConfirmDeleteIntent extends Intent {
  const _ConfirmDeleteIntent();
}

class _DeleteConfirmation extends StatefulWidget {
  const _DeleteConfirmation({
    required this.bookmark,
    required this.onCancel,
    required this.onConfirm,
  });

  final Bookmark bookmark;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  State<_DeleteConfirmation> createState() => _DeleteConfirmationState();
}

class _DeleteConfirmationState extends State<_DeleteConfirmation> {
  // Held on a FocusNode (NOT a button's focus) so Enter routes through
  // Shortcuts -> _ConfirmDeleteIntent. Pre-arming the Delete button would
  // mean any stray Enter triggers deletion -- using a sibling Focus node
  // forces the user's Enter through the explicit shortcut path.
  final _focusNode = FocusNode(debugLabel: 'delete-confirmation');

  @override
  void initState() {
    super.initState();
    // initState fires in the same frame as the rebuild that swapped the
    // populated body for this confirmation. requestFocus is queued for the
    // next frame so the FocusNode is fully registered first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): _ConfirmDeleteIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter):
            _ConfirmDeleteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ConfirmDeleteIntent: CallbackAction<_ConfirmDeleteIntent>(
            onInvoke: (_) {
              widget.onConfirm();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          child: _confirmationBody(context, textTheme),
        ),
      ),
    );
  }

  Widget _confirmationBody(BuildContext context, TextTheme textTheme) {
    return Semantics(
      container: true,
      label: 'Confirm delete bookmark: ${widget.bookmark.title}',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.delete_outline,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Delete this bookmark?',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.bookmark.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Cancel-first ordering: established Apple HIG / GNOME / WCAG
            // guidance places the destructive action LAST so users don't
            // reach for it instinctively.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: widget.onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton(
                    onPressed: widget.onConfirm,
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of tag FilterChips for the currently-displayed bookmark with an inline
/// add input below. Lives inside the detail pane (Story 2.5 Task 6) because
/// it's tightly coupled to the pane's selection lifecycle. Read-only chip
/// rows used by BookmarkListItem / BookmarkCard live in
/// `features/tags/presentation/widgets/bookmark_tag_chip_row.dart`.
class _TagsRow extends ConsumerStatefulWidget {
  const _TagsRow({
    required this.bookmarkId,
    required this.editable,
  });

  final String bookmarkId;
  final bool editable;

  @override
  ConsumerState<_TagsRow> createState() => _TagsRowState();
}

class _TagsRowState extends ConsumerState<_TagsRow> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'detail-tags-input');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text;
    // Comma-separated batch entry: "design, ux, typography" creates three tags
    // in one Enter-press. Mirrors the chip-input idiom from Slack / Notion /
    // GitHub. Trim each part; empty parts (from "design,,ux") are silently
    // skipped.
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      // Whitespace-only or empty: no-op, just clear the field.
      _controller.clear();
      return;
    }
    for (final name in parts) {
      ref.read(tagNotifierProvider.notifier).addTagToBookmark(
            bookmarkId: widget.bookmarkId,
            name: name,
          );
    }
    _controller.clear();
    // Sticky focus -- user stays in "adding tags" mode without re-clicking.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync =
        ref.watch(watchTagsForBookmarkProvider(widget.bookmarkId));
    final tags = tagsAsync.value ?? const <Tag>[];
    return Semantics(
      container: true,
      label: 'Tags',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isEmpty)
            const Text(
              'No tags',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in tags)
                  FilterChip(
                    label: Text(tag.name),
                    // Selected state is "this tag is on this bookmark"; every
                    // chip we render IS selected, so set true. The visual is
                    // the chip's accent fill.
                    selected: true,
                    onSelected: (_) {},
                    onDeleted: widget.editable
                        ? () => ref
                            .read(tagNotifierProvider.notifier)
                            .removeTagFromBookmark(
                              bookmarkId: widget.bookmarkId,
                              tagId: tag.id,
                            )
                        : null,
                    deleteIconColor: AppColors.textMuted,
                    selectedColor:
                        AppColors.accent.withValues(alpha: 0.15),
                    backgroundColor: AppColors.surfaceContent,
                    side: const BorderSide(color: AppColors.border),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textBody,
                    ),
                  ),
              ],
            ),
          if (widget.editable) ...[
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commit(),
              // Comma triggers commit so the user can enter "ux, design" in
              // one go; comma-as-commit is widely understood from
              // Slack/Notion. Listening on onChanged for the comma character
              // (rather than a TextInputFormatter) means pasted text with
              // commas also triggers commits.
              onChanged: (next) {
                if (next.endsWith(',')) {
                  _commit();
                }
              },
              decoration: const InputDecoration(
                hintText: 'Add a tag',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
