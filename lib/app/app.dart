import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme.dart';
import '../features/auth/auth_repository.dart';
import '../features/library/application/book_sync.dart';
import 'providers.dart';
import 'router.dart';

class FolioApp extends ConsumerStatefulWidget {
  const FolioApp({super.key});
  @override
  ConsumerState<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends ConsumerState<FolioApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick off sync once the first frame is up (no-op in local-only mode).
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(syncControllerProvider.notifier).start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.onBackgrounded();
      case AppLifecycleState.resumed:
        lock.onResumed();
        ref.read(syncControllerProvider.notifier).syncNow();
        ref.invalidate(cloudOnlyCountProvider); // books may have been added to the cloud from another device
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    // Start syncing the moment the user signs in.
    ref.listen(sessionProvider, (prev, next) {
      if (next.value is SignedInSession && prev?.value is! SignedInSession) {
        ref.read(syncControllerProvider.notifier).syncNow();
        ref.invalidate(cloudOnlyCountProvider);
      }
    });
    return MaterialApp.router(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
