import 'package:bookmarks/core/widgets/close_menu_on_escape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloseMenuOnEscape', () {
    testWidgets('closes the menu when Esc is pressed and the menu is open',
        (tester) async {
      final controller = MenuController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuAnchor(
              controller: controller,
              menuChildren: const [
                MenuItemButton(child: Text('item-1')),
              ],
              child: CloseMenuOnEscape(
                controller: controller,
                child: Focus(
                  focusNode: focusNode,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      controller.open();
      await tester.pump();
      expect(controller.isOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.isOpen, isFalse);
    });

    testWidgets('Esc is a no-op when the menu is already closed',
        (tester) async {
      final controller = MenuController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuAnchor(
              controller: controller,
              menuChildren: const [
                MenuItemButton(child: Text('item-1')),
              ],
              child: CloseMenuOnEscape(
                controller: controller,
                child: Focus(
                  focusNode: focusNode,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();
      expect(controller.isOpen, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.isOpen, isFalse);
    });
  });
}
