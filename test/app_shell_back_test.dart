import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.off);
}

class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

void main() {
  late GoRouter router;
  late List<String> platformCalls;

  Future<void> pumpShell(WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'backup_prompt_shown': true});
    final prefs = await SharedPreferences.getInstance();
    platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    Widget page(String label) => Scaffold(body: Center(child: Text(label)));
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/home', builder: (_, _) => page('Home page'))],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/files',
                  builder: (_, _) => page('Files page'),
                  routes: [
                    GoRoute(path: 'sub', builder: (_, _) => page('Subfolder page')),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/photos', builder: (_, _) => page('Photos page'))],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupControllerProvider.overrideWith(_Backup.new),
          transferQueueProvider.overrideWith(_Queue.new),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('back inside a branch goes up, then home, then asks twice', (tester) async {
    await pumpShell(tester);

    router.go('/files');
    await tester.pumpAndSettle();
    router.push('/files/sub');
    await tester.pumpAndSettle();
    expect(find.text('Subfolder page'), findsOneWidget);

    await back(tester);
    expect(find.text('Files page'), findsOneWidget);

    await back(tester);
    expect(find.text('Home page'), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));

    await back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));

    await back(tester);
    expect(platformCalls, contains('SystemNavigator.pop'));
  });

  testWidgets('a second press after a pause only asks again', (tester) async {
    await pumpShell(tester);
    await back(tester);
    await tester.pump(const Duration(seconds: 3));
    await back(tester);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
  });
}
