import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

/// Backup switched on, without the library watchers, counting the passes it
/// is asked to start.
class _Backup extends BackupController {
  int passes = 0;

  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);

  @override
  void schedule({bool immediate = false}) => passes++;
}

void main() {
  late ProviderContainer container;
  late BackupController controller;
  late Preferences prefs;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    controller = container.read(backupControllerProvider.notifier);
    prefs = container.read(preferencesProvider);
  });

  tearDown(() => container.dispose());

  int passes() => (controller as _Backup).passes;

  test('Screenshots and chat folders start kept out, the rest shown', () {
    expect(controller.modeOf('Camera'), FolderBackupMode.shown);
    expect(controller.modeOf('Screenshots'), FolderBackupMode.keptOut);
    expect(controller.modeOf('whatsapp images'), FolderBackupMode.keptOut);
    expect(controller.modeOf('Telegram Video'), FolderBackupMode.keptOut);
  });

  test('showing a kept-out folder changes Photos only', () async {
    await controller.setFolderMode('Screenshots', FolderBackupMode.shown);
    expect(controller.modeOf('Screenshots'), FolderBackupMode.shown);
    expect(prefs.photosHiddenFolders, isNot(contains('Screenshots')));
    expect(prefs.photosHiddenFolders, contains('WhatsApp Images'));
    expect(prefs.backupExcludedFolders, isEmpty);
    expect(passes(), 0);
  });

  test('keeping a folder out matches its name whatever the case', () async {
    await controller.setFolderMode('camera', FolderBackupMode.keptOut);
    expect(controller.modeOf('Camera'), FolderBackupMode.keptOut);

    await controller.setFolderMode('CAMERA', FolderBackupMode.shown);
    expect(controller.modeOf('Camera'), FolderBackupMode.shown);
    expect(prefs.photosHiddenFolders.where((f) => f.toLowerCase() == 'camera'), isEmpty);
  });

  test('turning a folder off keeps its Photos choice and starts a pass', () async {
    await controller.setFolderMode('Screenshots', FolderBackupMode.off);
    expect(controller.modeOf('Screenshots'), FolderBackupMode.off);
    expect(prefs.backupExcludedFolders, {'Screenshots'});
    expect(prefs.photosHiddenFolders, contains('Screenshots'));
    expect(passes(), 1);

    // Off again changes nothing about what is backed up.
    await controller.setFolderMode('screenshots', FolderBackupMode.off);
    expect(prefs.backupExcludedFolders, hasLength(1));
    expect(passes(), 1);

    await controller.setFolderMode('Screenshots', FolderBackupMode.shown);
    expect(controller.modeOf('Screenshots'), FolderBackupMode.shown);
    expect(prefs.backupExcludedFolders, isEmpty);
    expect(prefs.photosHiddenFolders, isNot(contains('Screenshots')));
    expect(passes(), 2);
  });
}
