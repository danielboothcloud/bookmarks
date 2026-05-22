# Focus Model

Invariants the app maintains around Flutter's focus system. Update this document when a new focus surface is added or a new framework gotcha is discovered.

---

## Why this exists

Flutter's focus system has many implicit behaviours (Scaffold drawer interception, `EditableText` ambient focus rules, mouse clicks not claiming focus by default, dispose-time focus restoration to dead nodes). Each one was originally discovered through a bug. Treating focus as an *app-wide invariant* — not a per-widget property — keeps these from re-discovering each other.

If you are adding a new focus surface (any widget that owns a `FocusNode`, opens a menu, takes keyboard input, or is a target of `Shortcuts`), read this whole document first.

---

## Hard rules

### 1. Primary focus must stay inside `AppShell`'s `Shortcuts` subtree

The app-level shortcuts (`Cmd+N`, `Cmd+F`, Delete, Esc cascade, sidebar arrow nav) all hang off `AppShell`'s `Shortcuts` widget. If primary focus drifts above that subtree, every global shortcut bonks (macOS error beep) until the user clicks something inside.

**This means:**

- Mouse-clicked rows must explicitly claim focus (Flutter does **not** do this automatically with `InkWell` or `GestureDetector`).
- After a transient surface unmounts (form, rename field, menu), primary focus must be handed back to a node inside the shell.
- Test harnesses that wrap a widget in a bare `MaterialApp/Scaffold` (no `AppShell`) will see different focus behaviour from production. Be wary of test-only focus assertions that `pumpAndSettle` differently than a real run.

### 2. `EditableText` carve-out for global keyboard intents

Global intents that share a key with text editing (Backspace = delete-bookmark **and** delete-character; Esc = dismiss-cascade **and** clear-search) must declare `isEnabled` as `false` whenever `primaryFocus` is inside an `EditableText`. The reference implementation is `_DeleteSelectedItemAction.isEnabled` in `app_shell.dart`.

Forgetting this will silently break text input.

### 3. `DismissIntent` is poisoned at the top of the tree

`Scaffold` registers a hidden `_DismissDrawerAction` for `DismissIntent` and intercepts even when no drawer exists. **Use `AppDismissIntent` (not `DismissIntent`) for any Esc handling above `Scaffold`.** The cascade order lives in `app_shell.dart`.

`DismissIntent` is still safe in *local* scopes (a single `Shortcuts` block inside a single widget), e.g. `folder_tree.dart`'s edit-row Esc cancellation.

### 4. `MenuAnchor`'s built-in Esc only fires when focus is in the overlay

When a `MenuAnchor` is opened by **mouse**, focus stays on the anchor — `MenuAnchor`'s default Esc-to-close handler never sees the keystroke. Mouse-driven dismissal is silently broken.

**Fix pattern (used in `folder_picker.dart` and `_FolderContextMenu` in `folder_tree.dart`):**

```dart
CallbackShortcuts(
  bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
  child: GestureDetector(...the anchor...),
)
```

Combined with an explicit anchor `FocusNode` that the anchor's `GestureDetector` requests on `onTapDown` / `onSecondaryTapDown`. See §5.

### 5. Mouse clicks must claim focus on widgets that participate in shortcuts

`InkWell` and `GestureDetector` do **not** claim focus on pointer taps by default. For any widget that participates in `AppShell`'s `Shortcuts` subtree (selection rows, sidebar items, menu anchors), the tap handler must call `_focusNode.requestFocus()` before doing its work.

Reference implementations:

- `bookmark_list_item.dart` — `onTap: () { _focusNode.requestFocus(); ref.read(...).select(...); }`
- `folder_tree.dart` `_FolderContextMenu` — `onSecondaryTapDown: (_) { _rowFocusNode.requestFocus(); _menuController.open(); }`
- Sidebar tag row — owns its own `FocusNode` solely for this purpose.

This is what commit `12230be fix(focus): claim focus on mouse-click for sidebar/folder/bookmark surfaces` codified.

### 6. Transient surfaces (forms, rename, menus) must restore focus on dispose

When `InlineAddForm`, an inline rename, or a menu unmounts, primary focus must return to a live node inside `AppShell`. Two failure modes:

- **Restoration to a dead node.** If the surface that opened the form has itself unmounted (e.g. form opened via the EmptyState's CTA, EmptyState unmounted while form was open), the `_previousFocus.requestFocus()` call lands on a disposed `FocusNode`. **Guard with `prev.context != null` before requesting.** See `inline_add_form.dart`.
- **Restoration to a dead scope.** A trailing `unfocus()` in a cascade can move primary focus to a non-existent scope, breaking subsequent `Cmd+N` until the next interaction. **Don't unfocus at the end of a cascade.** Removed from `app_shell.dart` Esc cascade.

Commit `a447de5 fix(focus): hand focus back inside AppShell after form/rename mounts` codified the restore-on-mount pattern.

### 7. List/grid rows that participate in shortcuts use `skipTraversal: true`

Rows in `BookmarkListItem`, sidebar tag rows, etc. own `FocusNode(skipTraversal: true)`. The node exists *only* so a mouse click can claim focus inside the shell — the row should never be a Tab-traversal stop.

If keyboard list navigation lands as a feature, replace `skipTraversal: true` with a proper traversal policy *and* keep the `requestFocus()` on click.

### 8. Cross-bookmark widget identity needs `ValueKey(bookmarkId)`

Stateful widgets that hold draft input (e.g. `_TagsRow` with an in-flight tag string) **must** declare `ValueKey(bookmarkId)` on the consumer. Without it, switching the selected bookmark reuses the same `State` instance and the draft persists across selections.

Story 2.5 H1 was this exact bug. Pattern: any `Consumer*StatefulWidget` whose state depends on a parent-supplied identity key must declare that identity in its `Key`.

---

## Catalogue of focus surfaces (current)

| # | Surface | File | Owns FocusNode? | Claims focus on click? | Notes |
|---|---|---|---|---|---|
| 1 | AppShell body | `app_shell.dart` | `Focus(autofocus: true)` wrap | n/a (root) | Without this, mouse-clicking the workspace doesn't put focus inside the shell — Backspace beeps. |
| 2 | `BookmarkListItem` row | `bookmark_list_item.dart` | yes (`skipTraversal: true`) | yes (`onTap`) | Reference for the click-claims-focus pattern. |
| 3 | `BookmarkCard` | `bookmark_card.dart` | implicit via Material | yes (`onTap`) | Folder grid view. |
| 4 | Sidebar folder row | `folder_tree.dart` `_FolderRow` | yes (`_rowFocusNode`) | yes (`onTap` + `onSecondaryTapDown`) | |
| 5 | Sidebar tag row | `tag_list.dart` | yes | yes | "Solely to keep primary focus inside AppShell's Shortcuts subtree on mouse click." |
| 6 | `InlineAddForm` URL field | `inline_add_form.dart` | yes (autofocus) | n/a (auto-focused on mount) | Restores `_previousFocus` on dispose — must guard `prev.context != null`. |
| 7 | Folder/bookmark inline rename | `folder_tree.dart` / detail pane | yes | n/a (auto-focused on edit) | Local `Shortcuts(SingleActivator(escape): DismissIntent())` — local scope, not app scope. |
| 8 | `FolderPicker` `MenuAnchor` | `folder_picker.dart` | yes (anchor) | yes | Reference for the `MenuAnchor` mouse-Esc fix. |
| 9 | `_FolderContextMenu` `MenuAnchor` | `folder_tree.dart` | yes (`_rowFocusNode`) | yes (`onSecondaryTapDown`) | Same `CallbackShortcuts(escape)` idiom. |
| 10 | `BookmarkSearchBar` `TextField` | `features/search/presentation/widgets/search_bar.dart` | yes (via `searchBarFocusNodeProvider`) | yes (`TextField` self-claim on tap) | Tab-traversal slot 2 (sidebar → search bar → content → detail). FocusNode is provider-owned so AppShell's `FocusSearchIntent` action can request focus from outside the widget tree without a GlobalKey. The State adds a focus-gain listener that positions the cursor at end-of-text in a post-frame callback. |
| 11 | `DriveConnectButton` (welcome screen) | `features/onboarding/presentation/widgets/drive_connect_button.dart` | implicit via Material `FilledButton` | yes (button self-claim on tap) | Sole focusable widget on `/welcome` — Tab moves focus to it from the natural focus root; Enter / Space invoke `DriveAuthNotifier.connect()`. The welcome screen is a top-level GoRoute outside `AppShell`'s `Shortcuts` subtree, so Hard Rule 1 doesn't apply here (no app-level shortcuts are bound on /welcome). |
| 12 | `SyncStatusIndicator` (sidebar footer) | `core/widgets/sync_status_indicator.dart` | no | no | Story 4.4 shipped the green/amber/grey dot palette + the in-progress `_PulsingDot` (vanilla `AnimationController` + `FadeTransition`, reduce-motion gated via `MediaQuery.disableAnimations`). Still NOT a focus surface — Tab passes through. The collapsed-mode `Tooltip` is hover-only (Flutter built-in); no keyboard surface added. The `Semantics(liveRegion: true)` wrap announces status transitions; the dot itself is `ExcludeSemantics`. Story 4.5 will revisit IF the disconnect/reconnect flow needs an interactive sidebar control; until then, the indicator stays read-only. |

When adding a new surface, append a row here.

---

## Framework gotchas (Flutter-specific)

| Gotcha | Discovered in | Fix idiom |
|---|---|---|
| `Scaffold._DismissDrawerAction` intercepts `DismissIntent` | Story 1.5 | Use `AppDismissIntent` for app-scope Esc cascades. |
| `EditableText` ambient focus suppresses global character keys | Story 1.5 | `Action.isEnabled` returns `false` when `primaryFocus` is inside `EditableText`. |
| `InkWell` / `GestureDetector` don't claim focus on tap | Story 2.4 / commit `12230be` | Call `_focusNode.requestFocus()` in `onTap`. |
| `MenuAnchor` Esc-on-mouse-open silently broken | Stories 2.3 + 2.7 | `CallbackShortcuts({Escape: close})` on the anchor. |
| `_previousFocus.requestFocus()` to a disposed node | Story 1.5 | Guard with `prev.context != null`. |
| Trailing `unfocus()` in a cascade kills next `Cmd+N` | Story 1.5 | Don't unfocus at the cascade tail. |
| `LongPressDraggable(delay: zero)` classifies clicks as drags | Story 2.2 | Use plain `Draggable<T>` + `ImmediateMultiDragGestureRecognizer`. |
| `GestureDetector(onDoubleTap)` defers single-tap by ~300ms | Story 2.2 (debug log) | Don't combine `onTap` + `onDoubleTap` on focus-claiming surfaces. |
| Test harness `MaterialApp` (no AppShell) gives different focus paths from production | Story 2.4 | Either wrap tests in a real shell or assert the local `Shortcuts` subtree directly — don't assume AppShell-style focus claiming applies. |
| `Focus(autofocus: true)` is one-shot at mount; clicks on inert surfaces (Container padding, empty content area) leak primary focus outside the shell, breaking subsequent global shortcuts | Story 3.1 | Wrap the AppShell body in a translucent `Listener` that on `onPointerDown` schedules a post-frame reclaim onto the shell's `FocusNode` (`appShellFocusNodeProvider`) if focus ended up outside the shell subtree. Force a frame via `WidgetsBinding.instance.scheduleFrame()` because pointer events don't auto-schedule one. See `_AppShellFocusReclaimer` in `app_shell.dart`. |

When a new framework gotcha is discovered, append a row here.

---

## Checklist before merging a new focus surface

- [ ] Owns its own `FocusNode` (or uses a parent-owned one explicitly).
- [ ] Mouse tap calls `_focusNode.requestFocus()` before doing its work.
- [ ] If it opens a transient surface (form/menu/rename), restoration on dispose is guarded against dead nodes.
- [ ] If it uses `MenuAnchor`, includes the `CallbackShortcuts(escape: close)` idiom.
- [ ] If it has a `Consumer*StatefulWidget` with parent-identity-dependent state, declares `ValueKey(parentId)`.
- [ ] If it intercepts a key that doubles as a text-edit key (Backspace, Esc), declares `Action.isEnabled` to suppress when focus is in `EditableText`.
- [ ] Added to the catalogue table above.
- [ ] Real keystroke test (`tester.sendKeyEvent` or `tester.startGesture(...kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton)`) — not just `Actions.invoke`.
