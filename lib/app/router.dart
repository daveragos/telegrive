import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/files/file_kind.dart';
import '../features/auth/presentation/code_screen.dart';
import '../features/auth/presentation/password_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/qr_screen.dart';
import '../features/auth/presentation/unsupported_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/files/presentation/file_list_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/photos/presentation/photos_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/setup/presentation/setup_screen.dart';
import '../features/setup/presentation/splash_screen.dart';
import '../features/transfers/presentation/transfers_screen.dart';
import '../features/trash/presentation/trash_screen.dart';
import '../features/viewer/presentation/image_viewer_screen.dart';
import 'app_phase.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Routes follow [appPhaseProvider]: until the drive is open, the phase
/// alone decides which screen shows; after that, normal navigation.
final routerProvider = Provider<GoRouter>((ref) {
  final phase = ValueNotifier<AppPhase>(ref.read(appPhaseProvider));
  ref.listen<AppPhase>(appPhaseProvider, (_, next) => phase.value = next);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppPhase.starting.location,
    refreshListenable: phase,
    redirect: (context, state) {
      final current = phase.value;
      final location = state.matchedLocation;
      if (current == AppPhase.ready) {
        return AppPhase.isGateLocation(location) ? AppPhase.ready.location : null;
      }
      return location == current.location ? null : current.location;
    },
    routes: [
      _gate(AppPhase.starting, const SplashScreen()),
      _gate(AppPhase.welcome, const WelcomeScreen()),
      _gate(AppPhase.phone, const PhoneScreen()),
      _gate(AppPhase.code, const CodeScreen()),
      _gate(AppPhase.password, const PasswordScreen()),
      _gate(AppPhase.qr, const QrScreen()),
      _gate(AppPhase.unsupported, const UnsupportedAuthScreen()),
      _gate(AppPhase.setup, const SetupScreen()),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            _fade(state, AppShell(shell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/files',
                builder: (_, _) => const FilesScreen(),
                routes: [
                  GoRoute(
                    path: ':folderId',
                    builder: (_, state) =>
                        FilesScreen(folderId: state.pathParameters['folderId']),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/photos', builder: (_, _) => const PhotosScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SearchScreen(),
      ),
      GoRoute(
        path: '/transfers',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const TransfersScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/backup',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const BackupScreen(),
      ),
      GoRoute(
        path: '/trash',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const TrashScreen(),
      ),
      GoRoute(
        path: '/starred',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const FileListScreen.starred(),
      ),
      GoRoute(
        path: '/recent',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const FileListScreen.recent(),
      ),
      GoRoute(
        path: '/category/:kind',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            FileListScreen.kind(FileKind.fromName(state.pathParameters['kind'])),
      ),
      GoRoute(
        path: '/viewer/:fileId',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => _fade(
          state,
          ImageViewerScreen(
            fileId: state.pathParameters['fileId']!,
            fromTimeline: state.uri.queryParameters['from'] == 'photos',
          ),
        ),
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    phase.dispose();
  });
  return router;
});

/// Sign-in steps replace each other with a cross-fade rather than a push:
/// they are states, not a stack to go back through.
GoRoute _gate(AppPhase phase, Widget screen) => GoRoute(
  path: phase.location,
  pageBuilder: (_, state) => _fade(state, screen),
);

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  ),
);
