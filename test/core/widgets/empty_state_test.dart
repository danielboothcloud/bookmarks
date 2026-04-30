import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:bookmarks/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(body: child),
    );

void main() {
  group('EmptyState.noBookmarks', () {
    testWidgets('shows title, subtitle, and CTA', (tester) async {
      await tester.pumpWidget(_wrap(
        EmptyState.noBookmarks(onAddBookmark: () {}),
      ));

      expect(find.text('No bookmarks yet'), findsOneWidget);
      expect(find.text('Press Cmd+N to save your first.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add bookmark'), findsOneWidget);
    });

    testWidgets('CTA invokes callback', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        EmptyState.noBookmarks(onAddBookmark: () => tapped++),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'Add bookmark'));
      expect(tapped, 1);
    });
  });

  group('EmptyState.noResults', () {
    testWidgets('renders inline message with query', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.noResults('flutter')));

      expect(find.text("No bookmarks match 'flutter'"), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
