import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/backup/presentation/backup_screen.dart';
import 'package:telegrive/features/backup/presentation/duplicates_sheet.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// Backup switched on and up to date, without the library watchers.
class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);
}

/// A drive that is never syncing, except that the first pass to wait for it
/// fails the way a request Telegram took too long to answer does.
class _Sync extends DriveSync {
  int waits = 0;

  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {
    if (++waits == 1) throw const TelegramException(408, 'Request timeout');
  }
}

/// A backup that stopped, counting the passes it is asked to run.
class _Stopped extends BackupController {
  int passes = 0;

  @override
  BackupState build() => const BackupState(
    phase: BackupPhase.stopped,
    error: 'Telegram took too long to answer.',
  );

  @override
  void schedule({bool immediate = false}) => passes++;

  @override
  Future<List<DeviceFolder>> deviceFolders() async => const [];
}

class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photos, null),
  );

  test('a pass that crashes stops with the reason, and the next clears it', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      BackupPrefKeys.enabled: true,
      'backup_wifi_only': false,
      // Read in full, so a pass that gets that far looks at the library.
      'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
    });
    final shared = await SharedPreferences.getInstance();
    // Photo access granted, and nothing in the library.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      photos,
      (call) async => switch (call.method) {
        'getPermissionState' => PermissionState.authorized.index,
        'getAssetPathList' => {'data': <Object>[]},
        _ => null,
      },
    );
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final controller = container.read(backupControllerProvider.notifier);
    BackupState state() => container.read(backupControllerProvider);

    await controller.run();
    expect(state().phase, BackupPhase.stopped);
    expect(state().error, 'Telegram took too long to answer.');

    await controller.run();
    expect(state().phase, BackupPhase.upToDate);
    expect(state().error, isNull);
  });

  testWidgets('a stopped backup offers Retry, as Home and Photos do', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({BackupPrefKeys.enabled: true});
    final shared = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          backupControllerProvider.overrideWith(_Stopped.new),
          transferQueueProvider.overrideWith(_Queue.new),
          duplicateBackupsProvider.overrideWith((ref) async => DuplicateBackups.none),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const BackupScreen()),
      ),
    );
    await tester.pump();

    final retry = find.widgetWithText(FilledButton, 'Retry');
    expect(retry, findsOneWidget);
    await tester.tap(retry);

    final backup = ProviderScope.containerOf(tester.element(retry))
        .read(backupControllerProvider.notifier) as _Stopped;
    expect(backup.passes, 1);
  });
}
