import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class BookmarksApp extends StatefulWidget {
  const BookmarksApp({super.key});

  @override
  State<BookmarksApp> createState() => _BookmarksAppState();
}

class _BookmarksAppState extends State<BookmarksApp> {
  late final _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bookmarks',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: _router,
    );
  }
}
