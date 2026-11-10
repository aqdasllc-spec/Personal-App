import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/sign_in_page.dart';
import '../features/security/lock_screen.dart';
import '../features/settings/settings_page.dart';
import 'providers.dart';
import '../features/planner/presentation/planner_page.dart';
import 'shell/adaptive_shell.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/reader_page.dart';
import '../features/quran/presentation/quran_extras.dart';
import '../features/quran/presentation/quran_page.dart';
import '../features/quran/prayer/prayer_page.dart';
import '../features/quran/prayer/qibla_page.dart';
import '../features/quran/presentation/adhkar_page.dart';
import '../features/quran/presentation/tilawat_page.dart';
import '../features/library/presentation/search_all_page.dart';
import '../features/home/home_page.dart';

abstract final class Routes {
  static const signIn = '/sign-in';
  static const locked = '/locked';
  static const home = '/home';
  static const library = '/library';
  static const planner = '/planner';
  static const settings = '/settings';
  static const quran = '/home/quran';
  static const prayer = '/home/prayer';
  static const qibla = '/home/prayer/qibla';
  static const adhkar = '/home/quran/adhkar';
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(appLockProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final lock = ref.read(appLockProvider);
      final session =
          ref.read(sessionProvider).value ??
          ref.read(authRepositoryProvider).current;
      final loc = state.matchedLocation;
      if (lock.enabled && lock.locked) {
        return loc == Routes.locked ? null : Routes.locked;
      }
      if (session is SignedOutSession) {
        return loc == Routes.signIn ? null : Routes.signIn;
      }
      if (loc == Routes.locked || loc == Routes.signIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: Routes.locked, builder: (_, _) => const LockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const HomePage(),
                routes: [
                  GoRoute(
                    path: 'prayer',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const PrayerPage(),
                    routes: [
                      GoRoute(path: 'qibla', parentNavigatorKey: _rootKey, builder: (_, _) => const QiblaPage()),
                    ],
                  ),
                  GoRoute(
                    path: 'quran',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const QuranHomePage(),
                    routes: [
                      GoRoute(
                        path: 'find',
                        parentNavigatorKey: _rootKey,
                        builder: (_, _) => const QuranSearchPage(),
                      ),
                      GoRoute(
                        path: 'adhkar',
                        parentNavigatorKey: _rootKey,
                        builder: (_, _) => const AdhkarPage(),
                      ),
                      GoRoute(
                        path: ':surah',
                        parentNavigatorKey: _rootKey,
                        builder: (_, s) {
                          final n = (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114);
                          return SurahPage(
                            surah: n,
                            startAyah: int.tryParse(s.uri.queryParameters['ayah'] ?? '') ?? 1,
                          );
                        },
                        routes: [
                          GoRoute(
                            path: 'tilawat',
                            parentNavigatorKey: _rootKey,
                            builder: (_, s) => TilawatPage(
                              surah: (int.tryParse(s.pathParameters['surah'] ?? '') ?? 1).clamp(1, 114),
                              ayah: int.tryParse(s.uri.queryParameters['ayah'] ?? '') ?? 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                builder: (_, _) => const LibraryPage(),
                routes: [
                  GoRoute(
                    path: 'search',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const SearchAllPage(),
                  ),
                  GoRoute(
                    path: 'read/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, s) => ReaderPage(
                      bookId: s.pathParameters['id']!,
                      startPage: int.tryParse(s.uri.queryParameters['page'] ?? ''),
                      searchQuery: s.uri.queryParameters['q'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.planner,
                builder: (_, _) => const PlannerPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
