import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/home/presentation/home_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart' show KindTotal;
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);
}

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();
}

class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

void main() {
  DriveFile document(int i) {
    final at = DateTime.now().subtract(Duration(hours: i + 1));
    return DriveFile(
      id: 'f$i',
      folderId: null,
      name: 'Report $i.pdf',
      mimeType: 'application/pdf',
      kind: FileKind.document,
      size: 1000,
      createdAt: at,
      modifiedAt: at,
      partCount: 1,
      starred: false,
    );
  }

  Future<SharedPreferences> prefs() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  group('Home', () {
    Future<void> pumpHome(WidgetTester tester, Stream<StorageSummary> summary) async {
      final shared = await prefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(shared),
            driveSessionProvider.overrideWith(TestSession.new),
            driveSyncProvider.overrideWith(_Sync.new),
            backupControllerProvider.overrideWith(_Backup.new),
            transferQueueProvider.overrideWith(_Queue.new),
            storageSummaryProvider.overrideWith((ref) => summary),
            // Nothing opened, and nothing added by hand.
            recentActivityProvider(12).overrideWith((ref) => Stream.value(const [])),
            starredFilesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('says nothing about an empty drive until it has been counted', (tester) async {
      final summary = StreamController<StorageSummary>();
      addTearDown(summary.close);
      await pumpHome(tester, summary.stream);
      expect(find.text('Your drive is empty', skipOffstage: false), findsNothing);
      expect(find.text('Nothing opened yet', skipOffstage: false), findsNothing);

      // Only backup photos, which Photos shows rather than Recent.
      summary.add(const StorageSummary(totals: [KindTotal(FileKind.image, 40, 40000)]));
      await tester.pump();
      expect(find.text('Your drive is empty', skipOffstage: false), findsNothing);
      expect(find.text('Nothing opened yet', skipOffstage: false), findsOneWidget);
    });

    testWidgets('an empty drive says so once counted', (tester) async {
      await pumpHome(tester, Stream.value(const StorageSummary(totals: [])));
      await tester.pump();
      expect(find.text('Your drive is empty', skipOffstage: false), findsOneWidget);
    });
  });

  testWidgets('each half of Recent opens at the top of its own list', (tester) async {
    final shared = await prefs();
    final files = [for (var i = 0; i < 40; i++) document(i)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
          recentOpenedProvider.overrideWith(
            (ref) => Stream.value([
              for (final file in files)
                RecentEntry(file, at: file.createdAt.add(const Duration(minutes: 30)), opened: true),
            ]),
          ),
          recentAddedProvider.overrideWith((ref) => Stream.value(files.reversed.toList())),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const FileListScreen.recent()),
      ),
    );
    await tester.pump();
    await tester.pump();

    double offset() => tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0));

    await tester.tap(find.text('Added'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(find.text('Report 39.pdf'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opened'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(find.text('Report 0.pdf'), findsOneWidget);
  });
}
