import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/bookmarks/presentation/bookmark_list_screen.dart';
import '../../features/folders/presentation/folders_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tags/presentation/tags_screen.dart';
import '../drive/drive_auth_providers.dart';
import '../drive/drive_auth_state.dart';
import '../widgets/app_shell.dart';

abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const bookmarks = '/bookmarks';
  static const folders = '/folders';
  static const tags = '/tags';
  static const settings = '/settings';
}

/// Build the application router. Reads [driveAuthStateProvider] via
/// [container] for the [GoRouter.redirect] gating; [container] is
/// usually `ProviderContainer` from a `ProviderScope` ancestor.
///
/// [container] is nullable so legacy widget tests that pump the router
/// without a Riverpod-aware setup still compile. In that mode the
/// redirect resolves the container on-demand from `BuildContext` and
/// `refreshListenable` is omitted (state transitions still take effect
/// via direct navigation in those tests).
GoRouter buildRouter([ProviderContainer? container]) {
  final authRefresh =
      container != null ? _AuthRefreshNotifier(container) : null;
  return GoRouter(
    initialLocation: AppRoutes.bookmarks,
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final c = container ??
          ProviderScope.containerOf(context, listen: false);
      final auth = c.read(driveAuthStateProvider);
      // While the initial state is loading (secure-storage read in
      // flight), don't redirect — the loading window is sub-frame on
      // every platform we ship to and `refreshListenable` will fire
      // again the moment it resolves.
      if (auth.isLoading) return null;
      final s = auth.value;
      final atWelcome = state.matchedLocation == AppRoutes.welcome;
      if (s is DriveAuthDisconnected ||
          s is DriveAuthConnecting ||
          s is DriveAuthFailed) {
        return atWelcome ? null : AppRoutes.welcome;
      }
      // Connected (or any other future variant defaulting to "let
      // the user in").
      return atWelcome ? AppRoutes.bookmarks : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
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

/// Bridges Riverpod state changes to GoRouter's [refreshListenable]
/// channel. Without this, `redirect` would only re-evaluate on
/// navigation, so a Connect → Connected transition wouldn't
/// auto-promote the user off the welcome screen until they clicked
/// something else.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(ProviderContainer container) {
    _sub = container.listen<AsyncValue<DriveAuthState>>(
      driveAuthStateProvider,
      (_, _) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<DriveAuthState>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
