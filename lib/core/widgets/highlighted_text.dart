import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A drop-in replacement for [Text] that highlights occurrences of any
/// term in [terms] inside [source]. Matching is case-insensitive and
/// prefix-based (so `flu` highlights `flu` inside `flutter`). Pass an
/// empty `terms` list to render plain text — same glyph output as a
/// regular [Text], no [TextSpan] overhead.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.source, {
    required this.terms,
    this.style,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String source;
  final List<String> terms;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty || source.isEmpty) {
      return Text(
        source,
        style: style,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
      );
    }
    final spans = _spansFor(source, terms);
    if (spans.length == 1 && spans.first is TextSpan) {
      final only = spans.first as TextSpan;
      if (only.style == null) {
        return Text(
          only.text ?? source,
          style: style,
          maxLines: maxLines,
          overflow: overflow ?? TextOverflow.clip,
        );
      }
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

/// Builds the inline-span list. Strategy:
///   1. Lower-case both source and terms once.
///   2. Find every match interval.
///   3. Merge overlapping / adjacent intervals.
///   4. Emit plain spans for gaps and highlighted spans for intervals
///      using the original-case substring.
List<InlineSpan> _spansFor(String source, List<String> terms) {
  final lowerSource = source.toLowerCase();
  final lowerTerms = <String>{
    for (final t in terms)
      if (t.isNotEmpty) t.toLowerCase(),
  };
  if (lowerTerms.isEmpty) {
    return <InlineSpan>[TextSpan(text: source)];
  }

  final intervals = <_Interval>[];
  for (final term in lowerTerms) {
    var start = 0;
    while (true) {
      final idx = lowerSource.indexOf(term, start);
      if (idx < 0) break;
      intervals.add(_Interval(idx, idx + term.length));
      start = idx + term.length;
    }
  }

  if (intervals.isEmpty) {
    return <InlineSpan>[TextSpan(text: source)];
  }

  intervals.sort((a, b) => a.start.compareTo(b.start));

  final merged = <_Interval>[];
  for (final iv in intervals) {
    if (merged.isEmpty || iv.start > merged.last.end) {
      merged.add(iv);
    } else {
      final last = merged.last;
      merged[merged.length - 1] = _Interval(
        last.start,
        math.max(last.end, iv.end),
      );
    }
  }

  const highlightStyle = TextStyle(backgroundColor: AppColors.highlightSearch);
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final iv in merged) {
    if (iv.start > cursor) {
      spans.add(TextSpan(text: source.substring(cursor, iv.start)));
    }
    spans.add(
      TextSpan(
        text: source.substring(iv.start, iv.end),
        style: highlightStyle,
      ),
    );
    cursor = iv.end;
  }
  if (cursor < source.length) {
    spans.add(TextSpan(text: source.substring(cursor)));
  }
  return spans;
}

class _Interval {
  _Interval(this.start, this.end);
  final int start;
  final int end;
}
