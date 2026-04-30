import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static List<String> get _fontFallback {
    if (Platform.isMacOS) {
      return const ['SF Pro Text', 'SF Pro Display', '.AppleSystemUIFont'];
    }
    if (Platform.isWindows) {
      return const ['Segoe UI'];
    }
    return const ['Ubuntu', 'Cantarell', 'DejaVu Sans'];
  }

  static TextTheme buildTextTheme(Color body, Color muted) {
    final fallback = _fontFallback;
    return TextTheme(
      titleLarge: TextStyle(
        fontFamilyFallback: fallback,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: body,
      ),
      titleMedium: TextStyle(
        fontFamilyFallback: fallback,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: body,
      ),
      bodyMedium: TextStyle(
        fontFamilyFallback: fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: body,
      ),
      bodySmall: TextStyle(
        fontFamilyFallback: fallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontFamilyFallback: fallback,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: muted,
      ),
    );
  }

  static TextTheme get contentTextTheme =>
      buildTextTheme(AppColors.textBody, AppColors.textMuted);

  static TextTheme get sidebarTextTheme =>
      buildTextTheme(AppColors.textSidebar, AppColors.textSidebar);
}
