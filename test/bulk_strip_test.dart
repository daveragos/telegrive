import 'dart:async';

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

/// A long move under way, counting the times Stop is pressed.
class _Bulk extends BulkEdits {
  int stops = 0;

  @override
  BulkEdit? build() => const BulkEdit(
    label: 'Moving 500 items',
    icon: Icons.drive_file_move_outline,
    done: 212,
    total: 500,
  );

  @override
  void stop() => stops++;
}

void main() {
  /// The shell with its three tabs and Trash over it, as the app routes
  /// them, with a long move under way.
  Future<GoRouter> pumpShell(WidgetTester tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'backup_prompt_shown': true});
    final prefs = await SharedPreferences.getInstance();

    Widget page(String label) => Scaffold(body: Center(child: Text(label)));
    final popups = PopupRoutes();
    addTearDown(popups.dispose);
    final router = GoRouter(
      initialLocation: '/home',
      observers: [popups],
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
          builder: (context, child) =>
              BulkStripOverShell(router: router, popups: popups, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the bulk line follows onto screens opened over the shell', (tester) async {
    final router = await pumpShell(tester);

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

  testWidgets('a dialog over the screen keeps Stop out of reach', (tester) async {
    final router = await pumpShell(tester);
    final bulk =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)))
                .read(bulkEditsProvider.notifier)
            as _Bulk;
    router.push('/trash');
    await tester.pumpAndSettle();

    /// The colours of the barriers the navigator draws over the screen, or
    /// of the one over the line.
    Iterable<Color?> barriers({required bool overLine}) {
      final overScreen = find
          .descendant(of: find.byType(Navigator), matching: find.byType(ModalBarrier))
          .evaluate()
          .toSet();
      return find
          .byType(ModalBarrier)
          .evaluate()
          .where((barrier) => overScreen.contains(barrier) != overLine)
          .map((barrier) => (barrier.widget as ModalBarrier).color);
    }

    final semantics = tester.ensureSemantics();
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('Trash page')),
        builder: (_) => const AlertDialog(content: Text('Rename')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moving 500 items'), findsOneWidget);
    // The line's barrier keeps only the line from a screen reader, not the
    // dialog it sits under.
    expect(find.bySemanticsLabel('Rename'), findsOneWidget);

    // Where Stop is, a tap lands on the dialog's barrier: the dialog closes
    // and the move carries on.
    await tester.tap(find.text('Stop'), warnIfMissed: false);
    // Part way out, the line is still as dim as the screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final dimmed = barriers(overLine: false).nonNulls.single;
    expect(dimmed.a, greaterThan(0));
    expect(barriers(overLine: true).single!.a, moreOrLessEquals(dimmed.a, epsilon: 0.01));

    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    expect(barriers(overLine: true), isEmpty);
    expect(bulk.stops, 0);

    await tester.tap(find.text('Stop'));
    expect(bulk.stops, 1);
    semantics.dispose();
  });
}
