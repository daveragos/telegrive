import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/widgets/common.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/photos/presentation/album_actions.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A channel that turns caption edits down when [refusing], as one the
/// account may no longer post in does, and doesn't answer an edit to an
/// album's own message when [albumsStuck] is on.
class _Channel extends FakeTelegram {
  bool refusing = false;
  bool albumsStuck = false;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (refusing && function is td.EditMessageCaption) {
      throw const TelegramException(403, 'CHAT_WRITE_FORBIDDEN');
    }
    if (albumsStuck && function is td.EditMessageText) {
      throw const TelegramException(408, 'Request timeout');
    }
    return null;
  }
}

/// An Undo applies the opposite change to the file as the index holds it
/// now. The repository tests check why: the repository passes over a file
/// whose folder, star or name already matches the one asked for, and the
/// file the screen held before the change still shows the old values. The
/// screen tests check what the person sees.
void main() {
  late AppDatabase db;
  late _Channel telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Future<DriveFile> file() async => (await repository.fileById('a'))!;
  Future<DriveFolder> folder() async => (await repository.folderById('sub'))!;
  String caption() => (telegram.messages[10]!.content as td.MessageDocument).caption.text;

  Future<void> open() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _Channel();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    // The screen tests leave the in-memory database open, as the screenshot
    // harness does: it closes only once its watchers have let go, on a timer
    // that a widget test's clock no longer runs by then.
    addTearDown(container.dispose);
    repository = container.read(driveRepositoryProvider);
    await receive(textMessage(1, 'tgfolder2;id=work;name=Work;added=1700000000000'));
    await receive(textMessage(2, 'tgfolder2;id=home;name=Home;added=1700000000000'));
    await receive(
      textMessage(3, 'tgfolder2;id=sub;name=Sub;parent=work;added=1700000000000'),
    );
    await receive(textMessage(4, 'tgalbum2;id=trip;name=Trip;added=1700000000000'));
    await receive(
      documentMessage(
        10,
        'tgfile2;id=a;name=Thesis final.docx;folder=work;type=application/msword;size=9;'
        'added=1700000000000',
        fileName: 'Thesis final.docx',
        mimeType: 'application/msword',
      ),
    );
  }

  group('the repository', () {
    setUp(open);
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a move is undone from the file as it is now, not as it was', () async {
      final before = await file();
      await repository.moveFiles([before], 'home');
      expect((await file()).folderId, 'home');

      // The file in hand still says Work, so moving it to Work looks like no
      // change at all.
      await repository.moveFiles([before], before.folderId);
      expect((await file()).folderId, 'home');

      await repository.moveFiles([await file()], before.folderId);
      expect((await file()).folderId, 'work');
      expect(caption(), contains(';folder=work;'));
    });

    test('a star is undone the same way', () async {
      final before = await file();
      await repository.setStarred([before], starred: true);
      expect((await file()).starred, isTrue);

      await repository.setStarred([before], starred: before.starred);
      expect((await file()).starred, isTrue);

      await repository.setStarred([await file()], starred: before.starred);
      expect((await file()).starred, isFalse);
      expect(caption(), isNot(contains(';star=')));
    });

    test('a rename is undone the same way', () async {
      final before = await file();
      await repository.renameFile(before, 'Thesis finall.docx');
      expect((await file()).name, 'Thesis finall.docx');

      await repository.renameFile(before, before.name);
      expect((await file()).name, 'Thesis finall.docx');

      await repository.renameFile(await file(), before.name);
      expect((await file()).name, 'Thesis final.docx');
    });

    test('a folder move is undone from the folder as it is now', () async {
      final before = await folder();
      await repository.moveFolder(before, 'home');
      expect((await folder()).parentId, 'home');

      await repository.moveFolder(before, before.parentId);
      expect((await folder()).parentId, 'home');

      await repository.moveFolder(await folder(), before.parentId);
      expect((await folder()).parentId, 'work');
    });

    test('moving to Trash is undone by restoring', () async {
      await repository.trash(files: [await file()]);
      expect((await file()).trashedAt, isNotNull);

      await repository.restore(files: [await file()]);
      expect((await file()).trashedAt, isNull);
      expect((await file()).folderId, 'work');
    });
  });

  group('on screen', () {
    // Each test opens a database of its own and leaves it open.
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

    /// An empty screen, and the context and ref an action is started with.
    Future<(BuildContext, WidgetRef)> pumpScreen(WidgetTester tester) async {
      late BuildContext context;
      late WidgetRef ref;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Consumer(
                builder: (screen, screenRef, _) {
                  context = screen;
                  ref = screenRef;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      return (context, ref);
    }

    /// Moves the file from Work into Sub through the folder picker.
    Future<void> moveIntoSub(WidgetTester tester) async {
      final (context, ref) = await pumpScreen(tester);
      unawaited(FileActions.move(context, ref, files: [await file()]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sub'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Sub'));
      await tester.pumpAndSettle();
    }

    testWidgets('a move offers Undo, which puts the file back', (tester) async {
      await open();
      await moveIntoSub(tester);

      expect(find.text('Moved to Sub'), findsOneWidget);
      expect((await file()).folderId, 'sub');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Undone'), findsOneWidget);
      expect((await file()).folderId, 'work');
    });

    testWidgets('an Undo that can\'t go through says why', (tester) async {
      await open();
      await moveIntoSub(tester);
      telegram.refusing = true;

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn\'t undo: Chat write forbidden'), findsOneWidget);
      expect((await file()).folderId, 'sub');
    });

    testWidgets('an album that can\'t move to the top keeps the Undo', (tester) async {
      await open();
      telegram.albumsStuck = true;
      final (context, ref) = await pumpScreen(tester);
      const stuck =
          'Couldn\'t move "Trip" to the top of Albums: Telegram took too long to answer.';

      // The album's members are read from a database stream first, which
      // answers outside the test's clock.
      final photo = await file();
      await tester.runAsync(
        () => AlbumActions.add(context, ref, [photo], albumId: 'trip', name: 'Trip'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added 1 item to "Trip"'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text(stuck), findsNothing);

      // Said once the Undo has had its time.
      await tester.pump(undoWindow);
      await tester.pumpAndSettle();
      expect(find.text('Added 1 item to "Trip"'), findsNothing);
      expect(find.text(stuck), findsOneWidget);
    });

    testWidgets('the Undo on a delete for good is gone before the delete runs', (tester) async {
      await open();
      final (context, ref) = await pumpScreen(tester);
      // A sentence already on screen, which has to leave before the Undo
      // comes in.
      showSnack(context, 'Moved to Work');
      await tester.pump(const Duration(seconds: 1));

      var deleted = false;
      FileActions.deleteLater(
        context,
        ref,
        fileIds: {'a'},
        label: '"Thesis final.docx"',
        message: 'Deleting "Thesis final.docx" for good',
        run: () async => deleted = true,
      );
      var offered = Duration.zero;
      var waited = Duration.zero;
      while (!deleted) {
        expect(waited, lessThan(const Duration(seconds: 12)));
        await tester.pump(const Duration(milliseconds: 50));
        waited += const Duration(milliseconds: 50);
        if (!deleted && find.text('Undo').evaluate().isNotEmpty) offered = waited;
      }

      expect(find.text('Undo'), findsNothing);
      // Undo had nearly all of its window.
      expect(offered, greaterThan(const Duration(seconds: 9)));
    });
  });
}
