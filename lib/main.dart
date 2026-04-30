import 'dart:io' show Platform;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/theme/app_spacing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const minSize = Size(AppSpacing.minWindowWidth, AppSpacing.minWindowHeight);
    const initialSize = Size(1200, 800);
    const options = WindowOptions(
      size: initialSize,
      minimumSize: minSize,
      center: true,
      title: 'Bookmarks',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setMinimumSize(minSize);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Eagerly open the local DB so first-frame reads are instant (NFR1).
  // driftDatabase() returns a LazyDatabase that opens on first query, so we
  // force the connection here before runApp.
  final database = AppDatabase();
  await database
      .customSelect('SELECT 1', variables: <Variable<Object>>[])
      .getSingle();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const BookmarksApp(),
    ),
  );
}

/// Provider holding the singleton AppDatabase. Override in main() with the
/// eagerly-initialised instance so widgets can resolve it synchronously.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('AppDatabase must be provided via main()');
});
