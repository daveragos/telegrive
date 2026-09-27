import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/backup/data/free_up_space.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/files/presentation/trash_sheet.dart';
import 'package:telegrive/features/trash/data/pending_deletes.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A channel that can't be reached once the drive is open.
class _Offline extends FakeTelegram {
  bool online = true;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (!online && function is td.EditMessageCaption) {
      throw const TelegramException(408, 'Request timeout');
    }
    return null;
  }
}

/// Moving photos to the trash from a phone that still has them, with and
/// without taking the phone's copies along.
void main() {
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  late AppDatabase db;
  late FakeTelegram telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  /// The photos the phone's library holds, how many were looked up one by
  /// one, and every delete asked of it.
  late Set<String> library;
  late int lookups;
  late List<List<String>> phoneDeletes;

  /// The library can't be read, as when photo access is taken back.
  late bool libraryLocked;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Future<void> open(WidgetTester tester, {FakeTelegram? channel}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    telegram = channel ?? FakeTelegram();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    repository = container.read(driveRepositoryProvider);

    await receive(textMessage(1, '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}'));
    for (final (index, name) in ['a', 'b', 'c', 'gone'].indexed) {
      await receive(
        documentMessage(
          10 + index,
          '$name.jpg\ntgr1:{"id":"$name","n":"$name.jpg","m":"image/jpeg","s":9,'
          '"ct":1700000000000}',
          fileName: '$name.jpg',
          mimeType: 'image/jpeg',
        ),
      );
    }
    await receive(
      documentMessage(
        20,
        'notes.pdf\ntgr1:{"id":"notes","n":"notes.pdf","m":"application/pdf","s":9,'
        '"ct":1700000000000}',
        fileName: 'notes.pdf',
        mimeType: 'application/pdf',
      ),
    );
    // a and b were backed up from this phone and are still on it; gone was
    // too, but the phone has let it go since. c only lives in the drive.
    await db.markAssetBackedUp('asset-a', 'a');
    await db.markAssetBackedUp('asset-b', 'b');
    await db.markAssetBackedUp('asset-gone', 'gone');
    library = {'asset-a', 'asset-b'};

    lookups = 0;
    phoneDeletes = [];
    libraryLocked = false;
    Map<String, Object> asset(String id) => {'id': id, 'type': 1, 'width': 4000, 'height': 3000};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(photoManager, (
      call,
    ) async {
      final arguments = call.arguments as Map;
      if (libraryLocked && call.method != 'deleteWithIds') {
        throw PlatformException(code: 'denied', message: 'Permission is not granted');
      }
      switch (call.method) {
        case 'fetchEntityProperties':
          lookups++;
          final id = arguments['id'] as String;
          return library.contains(id) ? asset(id) : null;
        case 'getAssetPathList':
          return {
            'data': [
              {'id': 'all', 'name': 'Recent', 'isAll': true, 'assetCount': library.length},
            ],
          };
        case 'getAssetCountFromPath':
          return library.length;
        case 'getAssetListPaged':
          final size = arguments['size'] as int;
          return {
            'data': [
              for (final id in library.skip((arguments['page'] as int) * size).take(size))
                asset(id),
            ],
          };
        case 'deleteWithIds':
          final ids = (arguments['ids'] as List).cast<String>();
          phoneDeletes.add(ids);
          library.removeAll(ids);
          return ids;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(photoManager, null),
    );
  }

  Future<List<DriveFile>> filesOf(List<String> ids) async => [
    for (final id in ids) (await repository.fileById(id))!,
  ];

  Future<bool> trashed(String id) async => (await repository.fileById(id))!.trashedAt != null;

  /// What the screen's Restore button takes out of the Trash.
  var restoring = <DriveFile>[];

  /// A screen whose Trash button moves [files] and [folders] to the trash,
  /// and whose Restore button takes [restoring] out again.
  Future<void> tapTrash(
    WidgetTester tester,
    List<DriveFile> files, {
    List<DriveFolder> folders = const [],
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        FileActions.delete(context, ref, files: files, folders: folders),
                    child: const Text('Trash'),
                  ),
                  TextButton(
                    onPressed: () => FileActions.restore(context, ref, files: restoring),
                    child: const Text('Restore'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
  }

  /// Sends the app to the background or brings it back, and tells
  /// [PendingDeletes] as the app does.
  void lifecycle(WidgetTester tester, AppLifecycleState state) {
    tester.binding.handleAppLifecycleStateChanged(state);
    final pending = container.read(pendingDeletesProvider.notifier);
    unawaited(state == AppLifecycleState.paused ? pending.appPaused() : pending.appResumed());
  }

  /// Ticks the box, moves to the trash and leaves the app before the snack
  /// offering Undo is on screen, staying away long past the backstop.
  Future<void> trashAndLeave(WidgetTester tester) async {
    await tester.tap(find.text('Also delete from this phone'));
    await tester.pump();
    await tester.tap(find.text('Move to Trash'));
    lifecycle(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
  }

  Future<void> moveToTrash(WidgetTester tester, {bool tick = false}) async {
    if (tick) await tester.tap(find.text('Also delete from this phone'));
    await tester.pump();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
  }

  testWidgets('the phone copies go once Undo has had its time', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b', 'c']));

    expect(find.text('Move 3 items to Trash?'), findsOneWidget);
    expect(find.text('2 of these are on this phone'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await moveToTrash(tester, tick: true);
    expect(find.text('Moved 3 items to Trash'), findsOneWidget);
    expect(await trashed('a'), isTrue);
    expect(await trashed('c'), isTrue);
    expect(container.read(preferencesProvider).deletePhoneCopyToo, isTrue);
    expect(phoneDeletes, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    expect(phoneDeletes, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(phoneDeletes, hasLength(1));
    expect(phoneDeletes.single, unorderedEquals(['asset-a', 'asset-b']));
    // The drive copies stay in the Trash, to restore for 30 days.
    expect(await trashed('a'), isTrue);
  });

  testWidgets('Undo brings the photos back and leaves the phone alone', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));

    expect(find.text('Move 2 items to Trash?'), findsOneWidget);
    expect(find.textContaining('of these'), findsNothing);

    await moveToTrash(tester, tick: true);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(await trashed('a'), isFalse);
    expect(await trashed('b'), isFalse);
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('restoring a photo before Undo has had its time keeps it on the phone', (
    tester,
  ) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await moveToTrash(tester, tick: true);

    // Restored from the Trash screen: its sentence takes the place of the
    // one offering Undo.
    restoring = await filesOf(['a']);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restored "a.jpg"'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(await trashed('a'), isFalse);
    expect(phoneDeletes, [
      ['asset-b'],
    ]);
  });

  testWidgets('restoring them all leaves the phone alone', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await moveToTrash(tester, tick: true);

    restoring = await filesOf(['a', 'b']);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(await trashed('a'), isFalse);
    expect(await trashed('b'), isFalse);
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('a library that can\'t be read means no sheet, and the trash goes ahead', (
    tester,
  ) async {
    await open(tester);
    libraryLocked = true;
    await tapTrash(tester, await filesOf(['a', 'b']));

    expect(find.byType(TrashSheet), findsNothing);
    expect(find.text('Moved 2 items to Trash'), findsOneWidget);
    expect(await trashed('a'), isTrue);
    await tester.pump(const Duration(seconds: 30));
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('many photos in a library that can\'t be read don\'t hold up the trash', (
    tester,
  ) async {
    await open(tester);
    // Backup matched a.jpg to more photos than one lookup each would take.
    for (var i = 0; i < 600; i++) {
      await db.markAssetBackedUp('asset-a$i', 'a');
    }
    libraryLocked = true;
    await tapTrash(tester, await filesOf(['a']));

    expect(find.byType(TrashSheet), findsNothing);
    expect(find.text('Moved "a.jpg" to Trash'), findsOneWidget);
    expect(await trashed('a'), isTrue);
  });

  testWidgets('with the box left clear only the drive copies move', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a']));

    expect(find.text('Move "a.jpg" to Trash?'), findsOneWidget);
    await moveToTrash(tester);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(await trashed('a'), isTrue);
    expect(phoneDeletes, isEmpty);
    expect(container.read(preferencesProvider).deletePhoneCopyToo, isFalse);
  });

  testWidgets('a trash that fails says why and leaves the phone alone', (tester) async {
    final channel = _Offline();
    await open(tester, channel: channel);
    channel.online = false;
    await tapTrash(tester, await filesOf(['a', 'b']));
    await moveToTrash(tester, tick: true);

    expect(find.textContaining('Moved'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(await trashed('a'), isFalse);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('leaving the app before Undo is seen gives it its full time on return', (
    tester,
  ) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await trashAndLeave(tester);
    expect(await trashed('a'), isTrue);
    expect(phoneDeletes, isEmpty);

    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Moved 2 items to Trash'), findsOneWidget);
    expect(phoneDeletes, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    expect(phoneDeletes, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(phoneDeletes.single, unorderedEquals(['asset-a', 'asset-b']));
  });

  testWidgets('Undo after coming back leaves the phone alone', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await trashAndLeave(tester);

    lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(phoneDeletes, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(await trashed('a'), isFalse);
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('a photo the gallery lets go meanwhile is left out of the delete', (
    tester,
  ) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await moveToTrash(tester, tick: true);
    library.remove('asset-b');
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(phoneDeletes, [
      ['asset-a'],
    ]);
    expect(container.read(pendingDeletesProvider).lastFailure, isNull);
  });

  testWidgets('nothing is asked of the phone once the gallery has let them all go', (
    tester,
  ) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a', 'b']));
    await moveToTrash(tester, tick: true);
    library.clear();
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(phoneDeletes, isEmpty);
    expect(container.read(pendingDeletesProvider).lastFailure, isNull);
  });

  testWidgets('a photo backup matched more than once leaves the phone in every copy', (
    tester,
  ) async {
    await open(tester);
    // Backup found a second photo like a.jpg, and a later one like
    // gone.jpg, already in the drive.
    await db.markAssetBackedUp('asset-a2', 'a');
    await db.markAssetBackedUp('asset-gone2', 'gone');
    library.addAll({'asset-a2', 'asset-gone2'});
    await tapTrash(tester, await filesOf(['a', 'gone']));

    expect(find.text('Move 2 items to Trash?'), findsOneWidget);
    expect(find.textContaining('of these'), findsNothing);
    await moveToTrash(tester, tick: true);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(phoneDeletes.single, unorderedEquals(['asset-a', 'asset-a2', 'asset-gone2']));
  });

  testWidgets('many photos are checked against the library a page at a time', (tester) async {
    await open(tester);
    library = {for (var i = 0; i < 1300; i++) 'asset-$i'};

    final asked = [for (var i = 700; i < 1400; i++) 'asset-$i'];
    expect(await stillOnPhone(asked), {for (var i = 700; i < 1300; i++) 'asset-$i'});
    expect(lookups, 0);

    expect(await stillOnPhone(['asset-1', 'asset-2000']), {'asset-1'});
    expect(lookups, 2);
  });

  testWidgets('the box remembers the last answer', (tester) async {
    await open(tester);
    await container.read(preferencesProvider).setDeletePhoneCopyToo(true);
    await tapTrash(tester, await filesOf(['a']));

    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Cancel moves nothing', (tester) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['a']));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TrashSheet), findsNothing);
    expect(await trashed('a'), isFalse);
    expect(find.textContaining('Moved'), findsNothing);
  });

  testWidgets('what the phone doesn\'t have goes to the Trash without asking', (
    tester,
  ) async {
    await open(tester);
    await tapTrash(tester, await filesOf(['c', 'notes', 'gone']));

    expect(find.byType(TrashSheet), findsNothing);
    expect(find.text('Moved 3 items to Trash'), findsOneWidget);
    expect(await trashed('gone'), isTrue);
    await tester.pump(const Duration(seconds: 30));
    expect(phoneDeletes, isEmpty);
  });

  testWidgets('a folder in the selection means no sheet', (tester) async {
    await open(tester);
    final work = (await repository.folderById('work'))!;
    await tapTrash(tester, await filesOf(['a']), folders: [work]);

    expect(find.byType(TrashSheet), findsNothing);
    expect(find.text('Moved 2 items to Trash'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(phoneDeletes, isEmpty);
  });
}
