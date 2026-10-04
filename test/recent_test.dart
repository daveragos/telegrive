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
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_list_screen.dart';
import 'package:telegrive/features/home/presentation/home_screen.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/player/data/play_positions.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart'
    show FolderSize, KindTotal;
import 'package:telegrive/infrastructure/storage/preferences.dart';

import 'support/fake_telegram.dart';

class _Backup extends BackupController {
  @override
  BackupState build() => const BackupState(phase: BackupPhase.upToDate);
}

/// Nothing waiting to reach Telegram, without an index to read it from.
class _Outbox extends EditOutbox {
  @override
  OutboxState build() => const OutboxState();
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
    Future<void> pumpHome(
      WidgetTester tester,
      Stream<StorageSummary> summary, {
      List<DriveFolder> starredFolders = const [],
      // Null stands for sizes that haven't arrived yet.
      Map<String, FolderSize>? starredSizes = const {},
      // Null stands for positions that can't be read.
      List<ContinueItem>? continuing = const [],
    }) async {
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
            recentActivityProvider(12)
                .overrideWith((ref) => Stream.value(const [])),
            starredFilesProvider.overrideWith((ref) => Stream.value(const [])),
            starredFoldersProvider.overrideWith(
              (ref) => Stream.value(starredFolders),
            ),
            starredFolderSizesProvider.overrideWith(
              (ref) => starredSizes == null
                  ? const Stream.empty()
                  : Stream.value(starredSizes),
            ),
            // Nothing kept offline either.
            offlinePinsProvider.overrideWith((ref) => Stream.value(const {})),
            offlineUsageProvider.overrideWith((ref) => Stream.value((0, 0))),
            offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
            // Nothing changed without a connection.
            editOutboxProvider.overrideWith(_Outbox.new),
            pendingItemIdsProvider.overrideWith((ref) => Stream.value(const {})),
            continuePlayingProvider.overrideWith(
              (ref) => continuing == null
                  ? Stream.error(StateError('closed'))
                  : Stream.value(continuing),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
        ),
      );
      await tester.pump();
    }

    DriveFolder folder(String name, {bool starred = false}) => DriveFolder(
      id: name,
      parentId: null,
      name: name,
      createdAt: DateTime(2026, 9),
      modifiedAt: DateTime(2026, 9),
      starred: starred,
    );

    testWidgets('starred folders sit above Recent, each with what it holds', (
      tester,
    ) async {
      // Tall enough that the whole of Home is laid out.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHome(
        tester,
        Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.document, 3, 3000)]),
        ),
        starredFolders: [
          folder('Invoices', starred: true),
          folder('Drafts', starred: true),
        ],
        starredSizes: {
          'Invoices': const FolderSize(
            'Invoices',
            'Invoices',
            12,
            340 * 1024 * 1024,
          ),
          'Drafts': const FolderSize('Drafts', 'Drafts', 0, 0),
        },
      );
      await tester.pump();

      expect(find.text('Starred', skipOffstage: false), findsWidgets);
      expect(find.text('Invoices', skipOffstage: false), findsOneWidget);
      expect(
        find.text('12 items · 340 MB', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Empty folder', skipOffstage: false), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Invoices', skipOffstage: false)).dy,
        lessThan(
          tester.getTopLeft(find.text('Recent', skipOffstage: false)).dy,
        ),
      );
      // The row under Recent counts the folders among what is starred.
      expect(find.text('2', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a starred folder keeps its plain line until it is counted', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHome(
        tester,
        Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.document, 3, 3000)]),
        ),
        starredFolders: [folder('Invoices', starred: true)],
        starredSizes: null,
      );
      await tester.pump();
      expect(find.text('Empty folder', skipOffstage: false), findsNothing);
      expect(
        find.textContaining('Folder · ', skipOffstage: false),
        findsOneWidget,
      );
    });

    DriveFile playable(String name, FileKind kind, {String? folderId}) =>
        DriveFile(
          id: name,
          folderId: folderId,
          name: name,
          mimeType: kind == FileKind.video ? 'video/mp4' : 'audio/mpeg',
          kind: kind,
          size: 48 * 1024 * 1024,
          createdAt: DateTime(2026, 9),
          modifiedAt: DateTime(2026, 9),
          partCount: 1,
          starred: false,
        );

    testWidgets('Continue watching lists what is partway through', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHome(
        tester,
        Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.video, 3, 3000)]),
        ),
        continuing: [
          ContinueItem(
            file: playable('Lecture 7.mp4', FileKind.video, folderId: 'lec'),
            position: const Duration(minutes: 34),
            length: const Duration(minutes: 72),
            place: 'Lectures',
          ),
        ],
      );
      await tester.pump();

      expect(
        find.text('Continue watching', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Lecture 7.mp4', skipOffstage: false), findsOneWidget);
      expect(
        find.text('38 min left · Lectures', skipOffstage: false),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator, skipOffstage: false),
      );
      expect(bar.value, closeTo(34 / 72, 0.001));
      expect(
        tester.getTopLeft(find.text('Lecture 7.mp4', skipOffstage: false)).dy,
        lessThan(
          tester.getTopLeft(find.text('Storage', skipOffstage: false)).dy,
        ),
      );
    });

    testWidgets('a recording among the rows makes it Continue playing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHome(
        tester,
        Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.video, 3, 3000)]),
        ),
        continuing: [
          ContinueItem(
            file: playable('Lecture 7.mp4', FileKind.video),
            position: const Duration(minutes: 34),
            length: const Duration(minutes: 72),
            place: 'Files',
          ),
          ContinueItem(
            file: playable('Chapter 3.mp3', FileKind.audio),
            position: const Duration(minutes: 40),
            length: const Duration(minutes: 40, seconds: 30),
            place: 'Files',
          ),
        ],
      );
      await tester.pump();

      expect(
        find.text('Continue playing', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Continue watching', skipOffstage: false), findsNothing);
      expect(
        find.text('Less than a minute left · Files', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets(
      'with nothing to continue, or no way to know, Home has no group',
      (tester) async {
        final summary = Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.document, 3, 3000)]),
        );
        await pumpHome(tester, summary);
        await tester.pump();
        expect(
          find.textContaining('Continue', skipOffstage: false),
          findsNothing,
        );

        await pumpHome(tester, summary, continuing: null);
        await tester.pump();
        expect(
          find.textContaining('Continue', skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets('with nothing starred Home has no Starred group', (
      tester,
    ) async {
      await pumpHome(
        tester,
        Stream.value(
          const StorageSummary(totals: [KindTotal(FileKind.document, 3, 3000)]),
        ),
      );
      await tester.pump();
      expect(find.text('Starred', skipOffstage: false), findsNothing);
    });

    testWidgets('says nothing about an empty drive until it has been counted', (
      tester,
    ) async {
      final summary = StreamController<StorageSummary>();
      addTearDown(summary.close);
      await pumpHome(tester, summary.stream);
      expect(
        find.text('Your drive is empty', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text('Nothing opened yet', skipOffstage: false),
        findsNothing,
      );

      // Only backup photos, which Photos shows rather than Recent.
      summary.add(
        const StorageSummary(totals: [KindTotal(FileKind.image, 40, 40000)]),
      );
      await tester.pump();
      expect(
        find.text('Your drive is empty', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text('Nothing opened yet', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('an empty drive says so once counted', (tester) async {
      await pumpHome(tester, Stream.value(const StorageSummary(totals: [])));
      await tester.pump();
      expect(
        find.text('Your drive is empty', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  testWidgets('each half of Recent opens at the top of its own list', (
    tester,
  ) async {
    final shared = await prefs();
    final files = [for (var i = 0; i < 40; i++) document(i)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          offlineCopiesProvider.overrideWith((ref) => Stream.value(const {})),
          pendingItemIdsProvider.overrideWith((ref) => Stream.value(const {})),
          recentOpenedProvider.overrideWith(
            (ref) => Stream.value([
              for (final file in files)
                RecentEntry(
                  file,
                  at: file.createdAt.add(const Duration(minutes: 30)),
                  opened: true,
                ),
            ]),
          ),
          recentAddedProvider.overrideWith(
            (ref) => Stream.value(files.reversed.toList()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FileListScreen.recent(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0));

    await tester.tap(find.text('Added'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(find.text('Report 39.pdf'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opened'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(find.text('Report 0.pdf'), findsOneWidget);
  });
}
