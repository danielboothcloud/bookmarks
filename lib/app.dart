import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class BookmarksApp extends ConsumerStatefulWidget {
  const BookmarksApp({super.key});

  @override
  ConsumerState<BookmarksApp> createState() => _BookmarksAppState();
}

class _BookmarksAppState extends ConsumerState<BookmarksApp> {
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router ??= buildRouter(ProviderScope.containerOf(context, listen: false));
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bookmarks',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: _router!,
    );
  }
}
