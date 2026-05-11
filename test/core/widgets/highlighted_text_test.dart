import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/widgets/highlighted_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Returns the root [TextSpan] of the [RichText] inside the
/// [HighlightedText] under test. Picks the FIRST `RichText` whose
/// flattened plain text is non-empty (skips any tooltip / hint
/// descendants that Material may have inserted).
TextSpan? _rootSpan(WidgetTester tester) {
  final richTextFinder = find.descendant(
    of: find.byType(HighlightedText),
    matching: find.byType(RichText),
  );
  for (final rt in tester.widgetList<RichText>(richTextFinder)) {
    final ts = rt.text;
    if (ts is TextSpan) return ts;
  }
  return null;
}

/// Flatten every leaf [TextSpan] (text != null) from the root, in source
/// order. Mirrors what the user actually sees on-screen.
List<TextSpan> _leafSpans(TextSpan? root) {
  if (root == null) return const <TextSpan>[];
  final leaves = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) {
        leaves.add(span);
      }
      final children = span.children;
      if (children != null) {
        for (final c in children) {
          walk(c);
        }
      }
    }
  }

  walk(root);
  return leaves;
}

bool _isHighlighted(TextSpan span) =>
    span.style?.backgroundColor == AppColors.highlightSearch;

void main() {
  group('HighlightedText', () {
    testWidgets('empty terms list renders plain Text (no highlights)',
        (tester) async {
      await _pump(
          tester, const HighlightedText('flutter docs', terms: <String>[]));

      expect(find.text('flutter docs'), findsOneWidget);
      final highlighted = _leafSpans(_rootSpan(tester))
          .where(_isHighlighted)
          .toList();
      expect(highlighted, isEmpty);
    });

    testWidgets('single term, single match', (tester) async {
      await _pump(tester,
          const HighlightedText('flutter docs', terms: <String>['flu']));

      final leaves = _leafSpans(_rootSpan(tester));
      expect(leaves.map((s) => s.text), ['flu', 'tter docs']);
      expect(_isHighlighted(leaves[0]), isTrue);
      expect(_isHighlighted(leaves[1]), isFalse);
    });

    testWidgets('single term, multiple matches', (tester) async {
      await _pump(tester,
          const HighlightedText('flu flux fluffy', terms: <String>['flu']));

      final leaves = _leafSpans(_rootSpan(tester));
      final highlightedTexts =
          leaves.where(_isHighlighted).map((s) => s.text).toList();
      expect(highlightedTexts, ['flu', 'flu', 'flu']);
    });

    testWidgets('multiple terms each highlight independently', (tester) async {
      await _pump(
        tester,
        const HighlightedText(
          'Flutter widgets',
          terms: <String>['flu', 'wid'],
        ),
      );

      final leaves = _leafSpans(_rootSpan(tester));
      final highlightedTexts =
          leaves.where(_isHighlighted).map((s) => s.text).toList();
      expect(highlightedTexts, ['Flu', 'wid']);
    });

    testWidgets('case-insensitive matching preserves source case',
        (tester) async {
      await _pump(
          tester, const HighlightedText('Flutter', terms: <String>['flu']));

      final leaves = _leafSpans(_rootSpan(tester));
      expect(leaves.first.text, 'Flu');
      expect(_isHighlighted(leaves.first), isTrue);
    });

    testWidgets('prefix matching, not whole-word', (tester) async {
      await _pump(
          tester, const HighlightedText('flutter', terms: <String>['flu']));

      final leaves = _leafSpans(_rootSpan(tester));
      expect(leaves.map((s) => s.text), ['flu', 'tter']);
      expect(_isHighlighted(leaves[0]), isTrue);
      expect(_isHighlighted(leaves[1]), isFalse);
    });

    testWidgets('overlapping intervals merge into one highlight',
        (tester) async {
      await _pump(
        tester,
        const HighlightedText('abcabc', terms: <String>['ab', 'bc']),
      );

      final leaves = _leafSpans(_rootSpan(tester));
      final highlighted = leaves.where(_isHighlighted).toList();
      expect(highlighted, hasLength(1));
      expect(highlighted.single.text, 'abcabc');
    });

    testWidgets('adjacent intervals merge into one highlight', (tester) async {
      await _pump(
        tester,
        const HighlightedText(
          'flutterdocs',
          terms: <String>['flutter', 'docs'],
        ),
      );

      final leaves = _leafSpans(_rootSpan(tester));
      final highlighted = leaves.where(_isHighlighted).toList();
      expect(highlighted, hasLength(1));
      expect(highlighted.single.text, 'flutterdocs');
    });

    testWidgets('term not present renders as plain text', (tester) async {
      await _pump(
          tester, const HighlightedText('flutter', terms: <String>['xyz']));

      expect(find.text('flutter'), findsOneWidget);
      final highlighted = _leafSpans(_rootSpan(tester))
          .where(_isHighlighted)
          .toList();
      expect(highlighted, isEmpty);
    });

    testWidgets('empty source renders an empty Text', (tester) async {
      await _pump(
          tester, const HighlightedText('', terms: <String>['flu']));

      expect(find.byType(HighlightedText), findsOneWidget);
      final highlighted = _leafSpans(_rootSpan(tester))
          .where(_isHighlighted)
          .toList();
      expect(highlighted, isEmpty);
    });

    testWidgets('maxLines and overflow are forwarded to Text.rich',
        (tester) async {
      await _pump(
        tester,
        const HighlightedText(
          'flutter docs',
          terms: <String>['flu'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

      // The underlying Text.rich passes maxLines/overflow into RichText.
      final richText = tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(HighlightedText),
          matching: find.byType(RichText),
        ),
      ).first;
      expect(richText.maxLines, 1);
      expect(richText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('highlight span carries the highlight backgroundColor',
        (tester) async {
      await _pump(
        tester,
        const HighlightedText(
          'Flutter',
          terms: <String>['flu'],
          style: TextStyle(color: Color(0xFFFF0000)),
        ),
      );

      final highlighted =
          _leafSpans(_rootSpan(tester)).firstWhere(_isHighlighted);
      expect(highlighted.style?.backgroundColor, AppColors.highlightSearch);
    });
  });
}
