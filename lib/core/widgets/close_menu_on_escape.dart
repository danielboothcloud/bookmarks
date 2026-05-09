import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Closes [controller] on Escape when focus is anywhere inside [child].
///
/// `MenuAnchor`'s built-in Esc handler only fires when focus is *inside the
/// overlay* — i.e. on keyboard-driven open. Mouse-driven opens leave focus on
/// the anchor, so Esc is silently ignored. Wrap the anchor child in this
/// widget to close that gap.
///
/// Used by both menu surfaces in the codebase: the folder picker (left-click
/// menu over the bookmark detail pane's folder field) and the folder context
/// menu (right-click menu over sidebar folder rows). Both must own a focus
/// node on the anchor and call `requestFocus()` on tap so this widget's
/// `CallbackShortcuts` actually receives the keystroke — see
/// `docs/focus-model.md` §4 and §5.
class CloseMenuOnEscape extends StatelessWidget {
  const CloseMenuOnEscape({
    required this.controller,
    required this.child,
    super.key,
  });

  final MenuController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (controller.isOpen) controller.close();
        },
      },
      child: child,
    );
  }
}
