import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/sign_in_page.dart';
import '../features/security/lock_screen.dart';
import '../features/settings/settings_page.dart';
import 'providers.dart';
import 'shell/adaptive_shell.dart';
import 'shell/placeholder_pages.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const locked = '/locked';
  static const home = '/home';
  static const library = '/library';
  static const planner = '/planner';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.listen(appLockProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final lock = ref.read(appLockProvider);
      final session = ref.read(sessionProvider).value ?? ref.read(authRepositoryProvider).current;
      final loc = state.matchedLocation;
      if (lock.enabled && lock.locked) return loc == Routes.locked ? null : Routes.locked;
      if (session is SignedOutSession) return loc == Routes.signIn ? null : Routes.signIn;
      if (loc == Routes.locked || loc == Routes.signIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, __) => const SignInPage()),
      GoRoute(path: Routes.locked, builder: (_, __) => const LockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, __) => const HomePlaceholder())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.library, builder: (_, __) => const LibraryPlaceholder())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.planner, builder: (_, __) => const PlannerPlaceholder())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.settings, builder: (_, __) => const SettingsPage())]),
        ],
      ),
    ],
  );
});
