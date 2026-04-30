import 'package:bookmarks/core/theme/app_colors.dart';
import 'package:bookmarks/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('uses Material 3', () {
      final theme = AppTheme.build();
      expect(theme.useMaterial3, isTrue);
    });

    test('scaffold background uses surfaceContent token', () {
      final theme = AppTheme.build();
      expect(theme.scaffoldBackgroundColor, AppColors.surfaceContent);
    });

    test('color scheme primary uses accent token', () {
      final theme = AppTheme.build();
      expect(theme.colorScheme.primary, AppColors.accent);
    });

    test('navigationRail uses sidebar surface', () {
      final theme = AppTheme.build();
      expect(
        theme.navigationRailTheme.backgroundColor,
        AppColors.surfaceSidebar,
      );
    });

    test('compact density', () {
      final theme = AppTheme.build();
      expect(theme.visualDensity, VisualDensity.compact);
    });
  });
}
