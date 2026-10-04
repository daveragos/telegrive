import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/app_phase.dart';
import 'package:telegrive/app/app_shell.dart';
import 'package:telegrive/app/launch_action.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/widgets/selection_bar.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/features/trash/data/pending_deletes.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.off);
}

/// Takes uploads without Telegram behind it.
class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;

  @override
  Future<List<String>> enqueueUploads(
    List<UploadRequest> requests, {
    String? folderId,
  }) async => const [];
}

/// The app opened to do [request], as from a tapped notification.
class _Launched extends PendingLaunchAction {
  _Launched(this.request);

  final LaunchRequest request;

  @override
  LaunchRequest? build() => request;
}

/// A picker that answers with one file called [name] straight away.
class _Picker extends FilePickerPlatform {
  _Picker(this.name);

  final String name;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [_Picked(name)];
}

/// What the picker hands back: the name, where it is and how big, which
/// is all an upload reads of it before it is queued.
final class _Picked extends PlatformFile {
  _Picked(this.name);

  @override
  final String name;

  @override
  Uri get uri => Uri.file('/picked/$name');

  @override
  int? lengthSync() => 5;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The phone's temp folder, which an upload compares picked paths against.
class _Paths extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => '/picked/tmp';
}

void main() {
  // Each test opens an empty index of its own, which an upload checks
  // names against, and leaves it open: it closes on a timer that would
  // fire after the test's clock has stopped.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late GoRouter router;
  late List<String> platformCalls;

  /// The shell with stub pages: the three tabs, a subfolder in Files, and
  /// Transfers and Settings over the shell. With [phase], the splash too,
  /// left the way the app leaves it: through the phase redirect. With
  /// [launchedInto], the app was opened to do that, as from a notification.
  Future<void> pumpShell(
    WidgetTester tester, {
    ValueNotifier<AppPhase>? phase,
    LaunchRequest? launchedInto,
  }) async {
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
    final home = Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Column(
          children: [
            const Text('Home page'),
            TextButton(
              onPressed: () => FileActions.upload(context, ref),
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
    router = GoRouter(
      initialLocation: phase == null ? '/home' : AppPhase.starting.location,
      refreshListenable: phase,
      redirect: phase == null
          ? null
          : (_, state) => phase.value.redirect(state.matchedLocation),
      routes: [
        if (phase != null)
          GoRoute(
            path: AppPhase.starting.location,
            builder: (_, _) => page('Splash page'),
          ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/home', builder: (_, _) => home)],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/files',
                  builder: (_, _) => page('Files page'),
                  routes: [
                    GoRoute(
                      path: 'sub',
                      builder: (_, _) => page('Subfolder page'),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/photos',
                  builder: (_, _) => page('Photos page'),
                ),
              ],
            ),
          ],
        ),
        GoRoute(path: '/transfers', builder: (_, _) => page('Transfers page')),
        GoRoute(path: '/settings', builder: (_, _) => page('Settings page')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory()),
          ),
          backupControllerProvider.overrideWith(_Backup.new),
          transferQueueProvider.overrideWith(_Queue.new),
          if (launchedInto != null)
            pendingLaunchActionProvider.overrideWith(
              () => _Launched(launchedInto),
            ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The shell is still there, offstage, under a page pushed over it.
  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(AppShell, skipOffstage: false)),
  );

  testWidgets('back inside a branch goes up, then home, then asks twice', (
    tester,
  ) async {
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

  testWidgets('back from Settings returns to Home', (tester) async {
    await pumpShell(tester);
    router.push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);

    await back(tester);
    expect(find.text('Settings page'), findsNothing);
    expect(find.text('Home page'), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets(
    'back from a page over the shell returns to the tab it came from',
    (tester) async {
      await pumpShell(tester);
      router.go('/files');
      await tester.pumpAndSettle();
      router.push('/transfers');
      await tester.pumpAndSettle();
      expect(find.text('Transfers page'), findsOneWidget);

      await back(tester);
      expect(find.text('Transfers page'), findsNothing);
      expect(find.text('Files page'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    },
  );

  testWidgets('View on an upload opens Transfers over Home', (tester) async {
    final picker = FilePickerPlatform.instance;
    final paths = PathProviderPlatform.instance;
    FilePickerPlatform.instance = _Picker('notes.txt');
    PathProviderPlatform.instance = _Paths();
    addTearDown(() {
      FilePickerPlatform.instance = picker;
      PathProviderPlatform.instance = paths;
    });
    await pumpShell(tester);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Uploading notes.txt'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Transfers page'), findsOneWidget);

    await back(tester);
    expect(find.text('Transfers page'), findsNothing);
    expect(find.text('Home page'), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets('opened to show transfers, Transfers sits over Home', (
    tester,
  ) async {
    await pumpShell(
      tester,
      launchedInto: const LaunchRequest(LaunchAction.transfers),
    );
    expect(find.text('Transfers page'), findsOneWidget);
    expect(container(tester).read(pendingLaunchActionProvider), isNull);

    await back(tester);
    expect(find.text('Transfers page'), findsNothing);
    expect(find.text('Home page'), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
  });

  testWidgets(
    'once the splash has given way to Home, back never shows it again',
    (tester) async {
      final phase = ValueNotifier(AppPhase.starting);
      addTearDown(phase.dispose);
      await pumpShell(tester, phase: phase);
      expect(find.text('Splash page'), findsOneWidget);

      phase.value = AppPhase.ready;
      await tester.pumpAndSettle();
      expect(find.text('Home page'), findsOneWidget);

      await back(tester);
      expect(find.text('Splash page'), findsNothing);
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    },
  );

  testWidgets('a late delete failure is said in the shell', (tester) async {
    await pumpShell(tester);
    const failure =
        'Couldn\'t delete 3 items for good: Telegram took too long to answer.';
    container(tester)
        .read(pendingDeletesProvider.notifier)
        .reportFailure(failure);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('the same failure twice is said twice', (tester) async {
    await pumpShell(tester);
    const failure = 'Couldn\'t delete 3 items from this phone';
    final pending = container(tester).read(pendingDeletesProvider.notifier);
    pending.reportFailure(failure);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(failure), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(failure), findsNothing);

    pending.reportFailure(failure);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('the navigation bar hides while a branch selects', (
    tester,
  ) async {
    await pumpShell(tester);
    router.go('/files');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    final selecting = container(tester).read(selectionActiveProvider.notifier);
    selecting.set(true);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(NavigationBar), findsNothing);

    selecting.set(false);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    // Switching tabs after that leaves the bar where it is.
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Photos page'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets(
    'a branch that selects gets the phone\'s bottom inset for its own bar',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await pumpShell(tester);
      router.go('/files');
      await tester.pumpAndSettle();
      double inset() =>
          MediaQuery.paddingOf(tester.element(find.text('Files page'))).bottom;
      expect(inset(), 0);

      container(tester).read(selectionActiveProvider.notifier).set(true);
      await tester.pump(const Duration(milliseconds: 250));
      expect(inset(), 48);

      container(tester).read(selectionActiveProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(inset(), 0);
    },
  );

  testWidgets(
    'on a wide window the rail stays while selecting, and a tab switch ends it',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpShell(tester);
      router.go('/files');
      await tester.pumpAndSettle();

      container(tester).read(selectionActiveProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('Photos page'), findsOneWidget);
      expect(container(tester).read(selectionActiveProvider), isFalse);
    },
  );
}
