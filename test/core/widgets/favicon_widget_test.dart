import 'dart:convert';

import 'package:bookmarks/core/widgets/favicon_widget.dart';
import 'package:bookmarks/features/bookmarks/application/bookmark_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 transparent PNG (smallest legal PNG).
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=';

Widget _wrap(Widget child, {Set<String>? inFlight}) {
  return ProviderScope(
    overrides: [
      if (inFlight != null)
        metadataFetchInFlightProvider.overrideWith(
          () => _StaticInFlightNotifier(inFlight),
        ),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

class _StaticInFlightNotifier extends MetadataFetchInFlightNotifier {
  _StaticInFlightNotifier(this._initial);
  final Set<String> _initial;

  @override
  Set<String> build() => _initial;
}

void main() {
  setUp(FaviconWidget.debugClearCache);

  testWidgets(
      'placeholder when bookmark not in-flight and no faviconBase64',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const FaviconWidget(bookmarkId: 'b1', faviconBase64: null),
    ));

    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
      'spinner when bookmark in-flight and no faviconBase64',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const FaviconWidget(bookmarkId: 'b1', faviconBase64: null),
      inFlight: {'b1'},
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.public), findsNothing);
  });

  testWidgets('renders Image when faviconBase64 is a valid data URI',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const FaviconWidget(
        bookmarkId: 'b1',
        faviconBase64: 'data:image/png;base64,$_tinyPngBase64',
      ),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.public), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('outer constraints honour the size parameter (size: 36)',
      (tester) async {
    const key = ValueKey('fav');
    await tester.pumpWidget(_wrap(
      const FaviconWidget(
        key: key,
        bookmarkId: 'b1',
        faviconBase64: null,
        size: 36,
      ),
    ));

    expect(tester.getSize(find.byKey(key)), const Size(36, 36));
  });

  testWidgets('malformed base64 falls through to placeholder (no throw)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const FaviconWidget(
        bookmarkId: 'b1',
        faviconBase64: 'not-a-valid-data-uri-or-base64',
      ),
    ));

    // Shouldn't crash, should show placeholder.
    expect(find.byIcon(Icons.public), findsOneWidget);
  });

  testWidgets('faviconBase64 takes precedence over in-flight (loaded > spinner)',
      (tester) async {
    // If a bookmark is mid-fetch but we ALREADY have a favicon, render the
    // image (e.g. user opens an existing list while a refetch is somehow
    // pending). We never want to swap a real favicon for a spinner.
    final base64 = base64Encode(base64Decode(_tinyPngBase64));
    await tester.pumpWidget(_wrap(
      FaviconWidget(
        bookmarkId: 'b1',
        faviconBase64: 'data:image/png;base64,$base64',
      ),
      inFlight: const {'b1'},
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
