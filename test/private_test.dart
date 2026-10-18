import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/edit_outbox.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/presentation/waiting_changes_screen.dart';
import 'package:telegrive/features/lock/data/app_lock.dart';
import 'package:telegrive/features/offline/data/offline_sync.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/private/data/private_space.dart';
import 'package:telegrive/features/private/presentation/private_screen.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

/// A queue with nothing in it.
class _Queue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

/// No waiting changes are being sent.
class _Outbox extends EditOutbox {
  @override
  OutboxState build() => const OutboxState();
}

/// An app lock that answers the way the test says, with no prompt.
class _Lock extends AppLock {
  bool passes = true;
  int asked = 0;

  @override
  AppLockState build() => const AppLockState();

  @override
  Future<bool> canConfirm() async => true;

  @override
  Future<bool> confirm(String reason) async {
    asked++;
    return passes;
  }
}

void main() {
  final modified = DateTime(2026, 10, 18, 9);

  group('markedSubtrees', () {
    FolderRow folder(String id, {String? parentId, bool marked = false}) => FolderRow(
      id: id,
      parentId: parentId,
      name: id,
      messageId: id.hashCode,
      createdAt: modified,
      modifiedAt: modified,
      hidden: false,
      starred: false,
      hiddenFromPhotos: marked,
      private: false,
      inPrivate: false,
    );

    test('a marked folder takes the folders inside it along', () {
      final rows = [
        folder('trips', marked: true),
        folder('lalibela', parentId: 'trips'),
        folder('day1', parentId: 'lalibela'),
        folder('work'),
      ];
      expect(markedSubtrees(rows, (f) => f.hiddenFromPhotos), {
        'trips': 'trips',
        'lalibela': 'trips',
        'day1': 'trips',
      });
    });

    test('a folder marked inside a marked one goes by the outermost', () {
      final rows = [
        folder('trips', marked: true),
        folder('lalibela', parentId: 'trips', marked: true),
      ];
      expect(markedSubtrees(rows, (f) => f.hiddenFromPhotos), {
        'trips': 'trips',
        'lalibela': 'trips',
      });
    });

    test('a folder tree that loops ends anyway', () {
      final rows = [
        folder('a', parentId: 'b', marked: true),
        folder('b', parentId: 'a'),
      ];
      expect(markedSubtrees(rows, (f) => f.hiddenFromPhotos).keys, {'a', 'b'});
    });
  });

  group('the index keeps Private', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> folder(
      String id, {
      String? parentId,
      bool private = false,
      bool starred = false,
      DateTime? trashedAt,
    }) => db.upsertFolder(
      FoldersCompanion.insert(
        id: id,
        parentId: Value(parentId),
        name: id,
        messageId: id.hashCode & 0xffffff,
        createdAt: modified,
        modifiedAt: modified,
        private: Value(private),
        starred: Value(starred),
        trashedAt: Value(trashedAt),
      ),
    );

    var messageId = 100;
    Future<void> photo(
      String id, {
      String? folderId,
      bool starred = false,
      DateTime? trashedAt,
    }) => db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: id,
            folderId: Value(folderId),
            name: 'IMG_$id.jpg',
            mimeType: 'image/jpeg',
            kind: FileKind.image,
            size: 1000,
            createdAt: modified,
            modifiedAt: modified,
            starred: Value(starred),
            trashedAt: Value(trashedAt),
          ),
          FilePartsCompanion.insert(
            fileId: id,
            partIndex: 0,
            messageId: messageId++,
            tdFileId: messageId,
            size: 1000,
          ),
        );

    /// A private folder with a folder inside, a folder that isn't, and a
    /// photo in each and at the root; the private folder and two photos
    /// starred.
    Future<void> seed() async {
      await folder('vault', private: true, starred: true);
      await folder('deep', parentId: 'vault');
      await folder('open');
      await photo('a', folderId: 'vault');
      await photo('b', folderId: 'deep', starred: true);
      await photo('c', folderId: 'open', starred: true);
      await photo('r');
    }

    test('a private folder, what is inside it and their files are in Private', () async {
      await seed();
      expect((await db.folderById('vault'))!.inPrivate, isTrue);
      expect((await db.folderById('deep'))!.inPrivate, isTrue);
      expect((await db.folderById('open'))!.inPrivate, isFalse);
      expect((await db.fileById('a'))!.inPrivate, isTrue);
      expect((await db.fileById('b'))!.inPrivate, isTrue);
      expect((await db.fileById('c'))!.inPrivate, isFalse);
      expect((await db.fileById('r'))!.inPrivate, isFalse);
    });

    test('views across the drive leave Private out', () async {
      await seed();
      Set<String> ids(Iterable<dynamic> rows) => {for (final row in rows) row.id as String};

      expect(ids([for (final lite in await db.watchMediaLite().first) lite.row]), {'c', 'r'});
      expect(ids(await db.watchStarred().first), {'c'});
      expect(ids(await db.watchStarredFolders().first), isEmpty);
      expect(ids(await db.watchRecent().first), {'c', 'r'});
      expect(ids(await db.watchSearch('IMG').first), {'c', 'r'});
      expect(ids(await db.watchFolderSearch('e').first), {'open'});
      expect(
        (await db.watchTotals().first).fold<int>(0, (sum, t) => sum + t.count),
        2,
      );
      expect(
        {for (final size in await db.watchFolderSizes().first) size.folderId},
        {'open', null},
      );
    });

    test('a folder\'s own contents still hold its private files, for name checks', () async {
      await seed();
      expect({for (final row in await db.filesIn('vault')) row.id}, {'a'});
    });

    /// What [seed] makes, and in the trash: a photo from the private folder,
    /// a folder from inside it with a photo in it, and a photo from the
    /// folder that isn't private.
    Future<void> seedTrash() async {
      await seed();
      await photo('ta', folderId: 'vault', trashedAt: modified);
      await folder('tdeep', parentId: 'vault', trashedAt: modified);
      await photo('tin', folderId: 'tdeep');
      await photo('tc', folderId: 'open', trashedAt: modified);
    }

    test('Trash leaves what is in Private out unless asked, totals too', () async {
      await seedTrash();
      Set<String> ids(List<dynamic> rows) => {for (final row in rows) row.id as String};

      expect(ids(await db.watchTrashedFiles(includePrivate: false).first), {'tc'});
      expect(ids(await db.watchTrashedFolders(includePrivate: false).first), isEmpty);
      expect((await db.watchTrashTotals(includePrivate: false).first).$1, 1);

      expect(ids(await db.watchTrashedFiles().first), {'ta', 'tc'});
      expect(ids(await db.watchTrashedFolders().first), {'tdeep'});
      expect((await db.watchTrashTotals().first).$1, 3);
    });

    test('Trash shows what is in Private only while Private is open', () async {
      await seedTrash();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appLockProvider.overrideWith(_Lock.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(trashProvider, (_, _) {});
      container.listen(trashTotalsProvider, (_, _) {});
      Future<TrashContents> listed() => container.read(trashProvider.future);

      expect({for (final file in (await listed()).files) file.id}, {'tc'});
      expect((await container.read(trashTotalsProvider.future)).$1, 1);

      container.read(privateSpaceProvider.notifier).open();
      await pumpEventQueue();
      expect({for (final file in (await listed()).files) file.id}, {'ta', 'tc'});
      expect({for (final folder in (await listed()).folders) folder.id}, {'tdeep'});
      expect((await container.read(trashTotalsProvider.future)).$1, 3);
    });

    test('Offline lists what is in Private only while Private is open', () async {
      await seed();
      await db.pinOffline('vault', isFolder: true);
      await db.pinOffline('c', isFolder: false);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appLockProvider.overrideWith(_Lock.new),
          transferQueueProvider.overrideWith(_Queue.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(offlineOverviewProvider, (_, _) {});
      Future<Set<String>> pinned() async {
        for (var i = 0; i < 100; i++) {
          final overview = container.read(offlineOverviewProvider);
          if (overview.hasValue) {
            return {
              for (final pin in overview.requireValue.pins) pin.folder?.id ?? pin.file!.id,
            };
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        throw StateError('Offline never read');
      }

      expect(await pinned(), {'c'});
      container.read(privateSpaceProvider.notifier).open();
      expect(await pinned(), {'vault', 'c'});
    });

    test('a folder moved out of Private, or Private let go, comes back', () async {
      await seed();
      await folder('deep', parentId: 'open');
      expect((await db.folderById('deep'))!.inPrivate, isFalse);
      expect((await db.fileById('b'))!.inPrivate, isFalse);

      await folder('vault', starred: true);
      expect((await db.fileById('a'))!.inPrivate, isFalse);
      expect({for (final lite in await db.watchMediaLite().first) lite.row.id}, {'a', 'b', 'c', 'r'});
    });
  });

  group('OutOfSight', () {
    test('hides what is in Private\'s folders, never the root', () {
      const sight = OutOfSight.of({'vault'});
      expect(sight.hides('vault'), isTrue);
      expect(sight.hides('docs'), isFalse);
      expect(sight.hides(null), isFalse);
      expect(sight.isNone, isFalse);
    });

    test('hides anything in a folder while Private\'s folders are unknown', () {
      expect(OutOfSight.unknown.hides('docs'), isTrue);
      expect(OutOfSight.unknown.hides(null), isFalse);
    });

    test('hides nothing while Private is open', () {
      expect(OutOfSight.none.hides('vault'), isFalse);
      expect(OutOfSight.none.isNone, isTrue);
    });
  });

  group('Waiting changes', () {
    PendingEditView change(String name, {bool inPrivate = false}) => PendingEditView(
      target: EditTarget.album,
      id: name,
      name: name,
      description: 'Renamed from "Old"',
      inPrivate: inPrivate,
    );

    Future<void> pump(WidgetTester tester, List<PendingEditView> changes) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appLockProvider.overrideWith(_Lock.new),
            editOutboxProvider.overrideWith(_Outbox.new),
            pendingEditsProvider.overrideWith((ref) => Stream.value(changes)),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const WaitingChangesScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('counts what is in Private beside the list, without naming it', (tester) async {
      await pump(tester, [
        change('Trips'),
        change('Diary', inPrivate: true),
        change('Passport', inPrivate: true),
      ]);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Diary'), findsNothing);
      expect(find.text('2 changes to things in Private are waiting too.'), findsOneWidget);
    });

    testWidgets('says so when everything waiting is in Private', (tester) async {
      await pump(tester, [change('Diary', inPrivate: true)]);
      expect(find.text('Diary'), findsNothing);
      expect(find.text('1 change to something in Private is waiting'), findsOneWidget);
    });
  });

  group('Private\'s lock', () {
    late _Lock lock;

    Future<ProviderContainer> pump(WidgetTester tester) async {
      lock = _Lock();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockProvider.overrideWith(() => lock)],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.light(),
            home: const Scaffold(body: Text('Settings')),
          ),
        ),
      );
      return ProviderScope.containerOf(tester.element(find.text('Settings')));
    }

    NavigatorState navigator(WidgetTester tester) =>
        tester.state<NavigatorState>(find.byType(Navigator).first);

    void push(WidgetTester tester, Widget page) => unawaitedPush(navigator(tester), page);

    testWidgets('asks on arrival, and shows nothing until the lock passes', (tester) async {
      await pump(tester);
      lock.passes = false;
      push(tester, const PrivateGate(child: Text('Diary')));
      await tester.pumpAndSettle();

      expect(lock.asked, 1);
      expect(find.text('Private is locked'), findsOneWidget);
      expect(find.text('Diary'), findsNothing);

      lock.passes = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Diary'), findsOneWidget);
    });

    testWidgets('closes once its last page is left', (tester) async {
      final container = await pump(tester);
      push(tester, const PrivateGate(child: Text('Diary')));
      await tester.pumpAndSettle();
      expect(container.read(privateSpaceProvider), isTrue);

      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(container.read(privateSpaceProvider), isFalse);
    });

    testWidgets('leaving the app takes away what was opened over Private', (tester) async {
      final container = await pump(tester);
      push(tester, const PrivateGate(child: Text('Diary')));
      await tester.pumpAndSettle();
      push(tester, const PrivateGate(child: Text('Lalibela')));
      await tester.pumpAndSettle();
      push(tester, const Scaffold(body: Text('IMG_1.jpg')));
      await tester.pumpAndSettle();
      // The prompt's own trip to the background is long over.
      await tester.pump(const Duration(seconds: 3));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(container.read(privateSpaceProvider), isFalse);
      expect(find.text('IMG_1.jpg'), findsNothing);
      expect(find.text('Lalibela'), findsNothing);
      expect(find.text('Private is locked'), findsOneWidget);
      navigator(tester).pop();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}

/// Pushes [page] without waiting for it to be popped.
void unawaitedPush(NavigatorState navigator, Widget page) {
  navigator.push(MaterialPageRoute<void>(builder: (_) => page));
}
