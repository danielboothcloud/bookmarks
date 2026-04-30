import 'package:go_router/go_router.dart';

import '../../features/bookmarks/presentation/bookmark_list_screen.dart';
import '../../features/folders/presentation/folders_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tags/presentation/tags_screen.dart';
import '../widgets/app_shell.dart';

abstract final class AppRoutes {
  static const bookmarks = '/bookmarks';
  static const folders = '/folders';
  static const tags = '/tags';
  static const settings = '/settings';
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.bookmarks,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.bookmarks,
                builder: (context, state) => const BookmarkListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.folders,
                builder: (context, state) => const FoldersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tags,
                builder: (context, state) => const TagsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
