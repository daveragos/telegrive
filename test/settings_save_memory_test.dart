import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/network/data/mobile_data.dart';
import 'package:telegrive/features/network/data/proxies.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/search/data/content_indexer.dart';
import 'package:telegrive/features/settings/data/settings_providers.dart';
import 'package:telegrive/features/settings/presentation/settings_screen.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();
}

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.off);
}

class _MobileData extends MobileDataController {
  @override
  MobileDataState build() => MobileDataState(
    metered: false,
    limit: null,
    renewDay: 1,
    periodStart: DateTime(2026, 10),
    periodEnd: DateTime(2026, 11),
  );
}

class _Proxies extends ProxyController {
  @override
  Future<List<ProxyEntry>> build() async => const [];
}

void main() {
  const gb = 1 << 30;
  final small = DeviceProfile(
    lowRam: false,
    memoryClassMb: 128,
    totalRamBytes: (1.9 * gb).round(),
  );
  const roomy = DeviceProfile(lowRam: false, memoryClassMb: 256, totalRamBytes: 6 * gb);

  Future<void> pumpSettings(
    WidgetTester tester,
    DeviceProfile profile, {
    Map<String, Object> prefs = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    // Tall enough that the list builds every row.
    tester.view.physicalSize = const Size(400, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          deviceProfileProvider.overrideWithValue(profile),
          driveSessionProvider.overrideWith(TestSession.new),
          driveSyncProvider.overrideWith(_Sync.new),
          backupControllerProvider.overrideWith(_Backup.new),
          mobileDataProvider.overrideWith(_MobileData.new),
          proxiesProvider.overrideWith(_Proxies.new),
          storageSummaryProvider.overrideWith((ref) => Stream.value(const StorageSummary(totals: []))),
          trashProvider.overrideWith((ref) => Stream.value(const TrashContents(folders: [], files: []))),
          offlineUsageProvider.overrideWith((ref) => Stream.value((0, 0))),
          indexedCountProvider.overrideWith((ref) => Stream.value(0)),
          cacheSizeProvider.overrideWith((ref) async => 0),
          notificationsEnabledProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final reason = find.textContaining('Turned on because');
  final saveMemory = find.widgetWithText(SwitchListTile, 'Save memory');

  bool isOn(WidgetTester tester) => tester.widget<SwitchListTile>(saveMemory).value;

  testWidgets('a small phone has Save memory on, and says why', (tester) async {
    await pumpSettings(tester, small);

    expect(isOn(tester), isTrue);
    expect(
      find.textContaining('plain previews. Turned on because this phone has 1.9 GB of memory.'),
      findsOneWidget,
    );
  });

  testWidgets('a roomy phone has it off, with nothing to explain', (tester) async {
    await pumpSettings(tester, roomy);

    expect(isOn(tester), isFalse);
    expect(reason, findsNothing);
    expect(
      find.text('Fewer transfers at once, a smaller image cache and plain previews.'),
      findsOneWidget,
    );
  });

  testWidgets('a stored choice is the person\'s, so the phone is not named', (tester) async {
    await pumpSettings(tester, small, prefs: {'save_memory': true});

    expect(isOn(tester), isTrue);
    expect(reason, findsNothing);
  });

  testWidgets('turning it off applies at once and drops the explanation', (tester) async {
    await pumpSettings(tester, small);
    expect(reason, findsOneWidget);

    await tester.tap(saveMemory);
    await tester.pumpAndSettle();
    expect(isOn(tester), isFalse);
    expect(reason, findsNothing);
  });
}
