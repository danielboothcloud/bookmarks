import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors', () {
    test('surfaceSelected is visually distinct from surfaceHover', () {
      // Regression: Story 1.4 LOW L1 -- selected and hover used the same colour
      // so a hovered, unselected row was indistinguishable from a non-hovered,
      // selected row.
      expect(AppColors.surfaceSelected, isNot(equals(AppColors.surfaceHover)));
    });
  });
}
