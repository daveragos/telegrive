import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/files/data/bulk_edits.dart';
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

class _Bulk extends BulkEdits {
  @override
  BulkEdit? build() => const BulkEdit(
    label: 'Moving 500 items',
    icon: Icons.drive_file_move_outline,
    done: 212,
    total: 500,
  );
}

void main() {
  testWidgets('the bulk line follows onto screens opened over the shell', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'backup_prompt_shown': true});
    final prefs = await SharedPreferences.getInstance();

    Widget page(String label) => Scaffold(body: Center(child: Text(label)));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/home', builder: (_, _) => page('Home page'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/files', builder: (_, _) => page('Files page'))],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/photos', builder: (_, _) => page('Photos page'))],
            ),
          ],
        ),
        GoRoute(path: '/trash', builder: (_, _) => page('Trash page')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupControllerProvider.overrideWith(_Backup.new),
          transferQueueProvider.overrideWith(_Queue.new),
          bulkEditsProvider.overrideWith(_Bulk.new),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => BulkStripOverShell(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inShell = find.descendant(
      of: find.byType(AppShell),
      matching: find.text('Moving 500 items'),
    );
    expect(find.text('Moving 500 items'), findsOneWidget);
    expect(inShell, findsOneWidget);

    router.push('/trash');
    await tester.pumpAndSettle();

    expect(find.text('Trash page'), findsOneWidget);
    expect(find.text('Moving 500 items'), findsOneWidget);
    expect(find.text('212 of 500 done'), findsOneWidget);
    expect(inShell, findsNothing);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Moving 500 items'), findsOneWidget);
    expect(inShell, findsOneWidget);
  });
}
