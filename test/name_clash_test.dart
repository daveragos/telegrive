import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/drive/data/channel_messenger.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// A queue with nothing in it, which never uploads.
class _IdleQueue extends TransferQueue {
  @override
  TransfersState build() => TransfersState.empty;
}

/// Holds the clash check until [gate] is completed, so a screen can go
/// away while the question is still being prepared.
class _GatedRepository extends DriveRepository {
  _GatedRepository(super.ref);

  final gate = Completer<void>();

  @override
  Future<Map<String, DriveFile>> nameClashes(
    Iterable<String> names,
    String? folderId,
  ) async {
    await gate.future;
    return super.nameClashes(names, folderId);
  }
}

/// Sends the way TDLib does: a pending message at once, and the delivered
/// message as an update a moment later.
class _UploadTelegram extends FakeTelegram {
  final _updates = StreamController<td.TdObject>.broadcast();

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(
          document: td.InputFileLocal(:final path),
          :final caption?,
        ),
      ):
        final pendingId = nextId++;
        final delivered = documentMessage(
          nextId++,
          caption.text,
          fileName: p.basename(path),
          mimeType: 'text/plain',
        );
        messages[delivered.id] = delivered;
        Timer.run(
          () => _updates.add(
            td.UpdateMessageSendSucceeded(
              message: delivered,
              oldMessageId: pendingId,
            ),
          ),
        );
        return documentMessage(
          pendingId,
          caption.text,
          fileName: p.basename(path),
          mimeType: 'text/plain',
        ).copyWith(
          sendingState: const td.MessageSendingStatePending(sendingId: 0),
        );
      default:
        return null;
    }
  }
}

/// A drive with Work and, inside it, Home and an empty Archive. Work holds
/// Budget 2026.xlsx, Budget 2026 (2).xlsx, Notes.txt and, in the trash,
/// Old.pdf; Home holds its own Budget 2026.xlsx; the root holds a third
/// Budget 2026.xlsx and a file whose folder is gone.
void main() {
  late AppDatabase db;
  late FakeTelegram telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  Future<DriveFile> file(String id) async => (await repository.fileById(id))!;

  String caption(int messageId) =>
      (telegram.messages[messageId]!.content as td.MessageDocument)
          .caption
          .text;

  td.Message document(
    int id,
    String fileId,
    String name, {
    String? folderId,
    bool trashed = false,
  }) => documentMessage(
    id,
    '$name\ntgr1:{"id":"$fileId","n":"$name"'
    '${folderId == null ? '' : ',"f":"$folderId"'}'
    ',"m":"application/octet-stream","s":9,"ct":1700000000000'
    '${trashed ? ',"tr":1700000000000' : ''}}',
    fileName: name,
    mimeType: 'application/octet-stream',
  );

  Future<void> open({FakeTelegram? client, bool gateClashes = false}) async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = client ?? FakeTelegram();
    container = ProviderContainer(
      overrides: [
        if (gateClashes)
          driveRepositoryProvider.overrideWith((ref) {
            final repository = _GatedRepository(ref);
            ref.onDispose(repository.dispose);
            return repository;
          }),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        if (client == null) transferQueueProvider.overrideWith(_IdleQueue.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
      ],
    );
    addTearDown(container.dispose);
    repository = container.read(driveRepositoryProvider);
    await receive(
      textMessage(
        1,
        '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}',
      ),
    );
    await receive(
      textMessage(
        2,
        '📁 Home\ntgrf1:{"id":"home","n":"Home","p":"work","ct":1700000000000}',
      ),
    );
    await receive(
      textMessage(
        3,
        '📁 Archive\ntgrf1:{"id":"archive","n":"Archive","p":"work","ct":1700000000000}',
      ),
    );
    await receive(document(10, 'a', 'Budget 2026.xlsx', folderId: 'work'));
    await receive(document(11, 'b', 'Notes.txt', folderId: 'work'));
    await receive(document(12, 'd', 'Budget 2026 (2).xlsx', folderId: 'work'));
    await receive(
      document(13, 't', 'Old.pdf', folderId: 'work', trashed: true),
    );
    await receive(document(14, 'h', 'Budget 2026.xlsx', folderId: 'home'));
    await receive(document(15, 'c', 'Budget 2026.xlsx'));
    await receive(document(16, 'o', 'Orphan.pdf', folderId: 'gone'));
  }

  group('the repository', () {
    setUp(open);
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('name clashes ignore case, the trash and other folders, and treat '
        'orphans as root', () async {
      final inWork = await repository.nameClashes([
        'BUDGET 2026.XLSX',
        'notes.txt',
        'old.pdf',
        'Fresh.txt',
      ], 'work');
      expect(inWork.keys, unorderedEquals(['budget 2026.xlsx', 'notes.txt']));
      expect(inWork['budget 2026.xlsx']!.id, 'a');
      expect(inWork['notes.txt']!.id, 'b');

      final atRoot = await repository.nameClashes([
        'orphan.pdf',
        'Budget 2026.xlsx',
        'Notes.txt',
      ], null);
      expect(atRoot.keys, unorderedEquals(['orphan.pdf', 'budget 2026.xlsx']));
      expect(atRoot['budget 2026.xlsx']!.id, 'c');
      expect(await repository.nameClashes([], 'work'), isEmpty);
      expect(await repository.takenNamesIn('work'), {
        'budget 2026.xlsx',
        'notes.txt',
        'budget 2026 (2).xlsx',
      });
    });

    test('a free name is left alone, and a taken one is numbered past the '
        'numbers taken', () {
      expect(repository.freeName('Budget 2026.xlsx', {}), 'Budget 2026.xlsx');
      expect(
        repository.freeName('Budget 2026.xlsx', {'budget 2026.xlsx'}),
        'Budget 2026 (2).xlsx',
      );
      expect(
        repository.freeName('Budget 2026.xlsx', {
          'budget 2026.xlsx',
          'budget 2026 (2).xlsx',
        }),
        'Budget 2026 (3).xlsx',
      );
      expect(repository.freeName('NOTES', {'notes'}), 'NOTES (2)');
    });

    test('renaming to a sibling\'s name is refused, in any case', () async {
      await expectLater(
        repository.renameFile(await file('b'), 'budget 2026.XLSX'),
        throwsA(
          isA<DriveException>().having(
            (e) => e.message,
            'message',
            '"budget 2026.XLSX" already exists here.',
          ),
        ),
      );
      expect((await file('b')).name, 'Notes.txt');
      expect(ManifestCodec.decodeFile(caption(11))!.name, 'Notes.txt');

      // Its own name in another case is no clash, and nor is a trashed one.
      await repository.renameFile(await file('a'), 'BUDGET 2026.xlsx');
      expect((await file('a')).name, 'BUDGET 2026.xlsx');
      await repository.renameFile(await file('b'), 'Old.pdf');
      expect((await file('b')).name, 'Old.pdf');

      // A file whose folder is gone shows at the root, so the root's files
      // are its siblings.
      await expectLater(
        repository.renameFile(await file('o'), 'Budget 2026.xlsx'),
        throwsA(isA<DriveException>()),
      );
      expect((await file('o')).name, 'Orphan.pdf');
      await repository.renameFile(await file('o'), 'Notes.txt');
      expect((await file('o')).name, 'Notes.txt');
    });

    test('a move can rename as it goes, in place too', () async {
      await repository.moveFiles(
        [await file('a')],
        'home',
        renames: {'a': 'Budget 2026 (2).xlsx'},
      );
      var moved = await file('a');
      expect(moved.folderId, 'home');
      expect(moved.name, 'Budget 2026 (2).xlsx');
      expect(caption(10), contains(';folder=home;'));

      await repository.moveFiles(
        [moved],
        'home',
        renames: {'a': 'Budget 2026 (3).xlsx'},
      );
      moved = await file('a');
      expect(moved.folderId, 'home');
      expect(moved.name, 'Budget 2026 (3).xlsx');

      // Already there under the name it has: nothing to do.
      final before = caption(10);
      await repository.moveFiles([moved], 'home');
      expect(caption(10), before);
    });

    test('replacing trashes the old file marked with its replacement, which '
        'restore clears', () async {
      await repository.replaceWith(oldFileId: 'h', newFileId: 'a');
      final old = await file('h');
      expect(old.trashedAt, isNotNull);
      expect(old.replacedBy, 'a');
      expect(caption(14), contains(';replacedby=a;'));
      expect((await repository.previousVersionOf('a'))?.id, 'h');
      expect(await repository.previousVersionOf('h'), isNull);

      // A second replace leaves a trashed file as it is, and one that is
      // gone needs nothing.
      await repository.replaceWith(oldFileId: 'h', newFileId: 'b');
      expect((await file('h')).replacedBy, 'a');
      await repository.replaceWith(oldFileId: 'missing', newFileId: 'a');

      await repository.restore(files: [await file('h')]);
      final back = await file('h');
      expect(back.trashedAt, isNull);
      expect(back.replacedBy, isNull);
      expect(caption(14), isNot(contains('replacedby=')));
      expect(await repository.previousVersionOf('a'), isNull);
    });
  });

  group('on screen', () {
    // Each test opens a database of its own and leaves it open.
    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    tearDownAll(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
    );

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

    /// Starts moving Work's Budget 2026.xlsx into Home, which has one too,
    /// and waits for the question.
    Future<Future<bool>> moveOntoHome(WidgetTester tester) async {
      final (context, ref) = await pumpScreen(tester);
      final moved = FileActions.move(context, ref, files: [await file('a')]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Home'));
      await tester.pumpAndSettle();
      expect(
        find.text('"Budget 2026.xlsx" is already in Home'),
        findsOneWidget,
      );
      expect(find.text('Moved as Budget 2026 (2).xlsx'), findsOneWidget);
      expect(find.text('Leave it where it is'), findsOneWidget);
      expect(find.textContaining('Do this for all'), findsNothing);
      return moved;
    }

    testWidgets('Skip on a move leaves the file where it was', (tester) async {
      await open();
      final moved = await moveOntoHome(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(await moved, isFalse);
      expect(find.text('Nothing moved'), findsOneWidget);
      expect((await file('a')).folderId, 'work');
      expect((await file('h')).trashedAt, isNull);
    });

    testWidgets('Replace on a move trashes the sibling as replaced, and Undo '
        'brings both back', (tester) async {
      await open();
      final moved = await moveOntoHome(tester);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(await moved, isTrue);
      expect(find.text('Moved to Home'), findsOneWidget);
      expect((await file('a')).folderId, 'home');
      final old = await file('h');
      expect(old.trashedAt, isNotNull);
      expect(old.replacedBy, 'a');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Undone'), findsOneWidget);
      expect((await file('a')).folderId, 'work');
      expect((await file('h')).trashedAt, isNull);
      expect((await file('h')).replacedBy, isNull);
    });

    testWidgets('Keep both on a move numbers the file, and Undo gives its '
        'name back', (tester) async {
      await open();
      final moved = await moveOntoHome(tester);
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(await moved, isTrue);
      var file = await repository.fileById('a');
      expect(file!.folderId, 'home');
      expect(file.name, 'Budget 2026 (2).xlsx');
      expect((await repository.fileById('h'))!.trashedAt, isNull);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      file = await repository.fileById('a');
      expect(file!.folderId, 'work');
      expect(file.name, 'Budget 2026.xlsx');
    });

    testWidgets('after Replace, a second file of that name in the batch is '
        'numbered without a question', (tester) async {
      await open();
      final (context, ref) = await pumpScreen(tester);
      final moved = FileActions.move(
        context,
        ref,
        files: [await file('a'), await file('c')],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Home'));
      await tester.pumpAndSettle();
      expect(find.text('Do this for all 2 name clashes'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is already in'), findsNothing);
      expect(await moved, isTrue);
      expect((await file('h')).replacedBy, 'a');
      final first = await file('a');
      expect(first.folderId, 'home');
      expect(first.name, 'Budget 2026.xlsx');
      final second = await file('c');
      expect(second.folderId, 'home');
      expect(second.name, 'Budget 2026 (2).xlsx');
    });

    testWidgets('two files of one name moved together are numbered apart, '
        'and Undo gives the name back', (tester) async {
      await open();
      final (context, ref) = await pumpScreen(tester);
      final moved = FileActions.move(
        context,
        ref,
        files: [await file('a'), await file('c')],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Archive'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is already in'), findsNothing);
      expect(await moved, isTrue);
      expect((await file('a')).name, 'Budget 2026.xlsx');
      expect((await file('a')).folderId, 'archive');
      expect((await file('c')).name, 'Budget 2026 (2).xlsx');
      expect((await file('c')).folderId, 'archive');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await file('c')).name, 'Budget 2026.xlsx');
      expect((await file('c')).folderId, isNull);
      expect((await file('a')).folderId, 'work');
    });

    testWidgets('a file already in the destination is no clash', (
      tester,
    ) async {
      await open();
      final (context, ref) = await pumpScreen(tester);
      final moved = FileActions.move(context, ref, files: [await file('h')]);
      await tester.pumpAndSettle();
      // The picker starts in the file's own folder.
      await tester.tap(find.text('Move to Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is already in'), findsNothing);
      expect(await moved, isTrue);
      expect((await file('h')).trashedAt, isNull);
    });

    /// Resolves uploads of [names] into Work and returns what is left.
    Future<Future<List<UploadRequest>>> resolve(
      WidgetTester tester,
      List<String> names,
    ) async {
      final (context, ref) = await pumpScreen(tester);
      final resolved = FileActions.resolveUploadClashes(context, ref, [
        for (final name in names)
          UploadRequest(name: name, path: '/no/$name', size: 91000),
      ], folderId: 'work');
      await tester.pumpAndSettle();
      return resolved;
    }

    testWidgets('one answer can stand for every clash in the batch', (
      tester,
    ) async {
      await open();
      final resolved = await resolve(tester, [
        'budget 2026.xlsx',
        'Fresh.txt',
        'Notes.txt',
        'Fresh.txt',
      ]);
      expect(
        find.text('"budget 2026.xlsx" is already in Work'),
        findsOneWidget,
      );
      expect(find.text('New · 88.9 KB'), findsOneWidget);
      expect(find.text('Saved as budget 2026 (3).xlsx'), findsOneWidget);
      expect(find.text('Don\'t upload this one'), findsOneWidget);
      expect(find.text('Do this for all 2 name clashes'), findsOneWidget);

      await tester.tap(find.text('Do this for all 2 name clashes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is already in'), findsNothing);
      // A name repeated in the batch is numbered without a question.
      expect(
        [for (final request in await resolved) request.name],
        ['budget 2026 (3).xlsx', 'Fresh.txt', 'Notes (2).txt', 'Fresh (2).txt'],
      );
    });

    testWidgets('Replace marks the upload, and the next clash asks again', (
      tester,
    ) async {
      await open();
      final resolved = await resolve(tester, ['Budget 2026.xlsx', 'Notes.txt']);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('"Notes.txt" is already in Work'), findsOneWidget);
      expect(find.textContaining('Do this for all'), findsNothing);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      final left = await resolved;
      expect(left, hasLength(1));
      expect(left.single.name, 'Budget 2026.xlsx');
      expect(left.single.replacesFileId, 'a');
    });

    testWidgets('after Replace, the next question counts only the clashes '
        'left', (tester) async {
      await open();
      final resolved = await resolve(tester, [
        'Budget 2026.xlsx',
        'budget 2026.xlsx',
        'Notes.txt',
      ]);
      expect(find.text('Do this for all 3 name clashes'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      // The second Budget is numbered, so only Notes is left to ask about.
      expect(find.text('"Notes.txt" is already in Work'), findsOneWidget);
      expect(find.textContaining('Do this for all'), findsNothing);
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(
        [for (final request in await resolved) request.name],
        ['Budget 2026.xlsx', 'budget 2026 (3).xlsx', 'Notes (2).txt'],
      );
    });

    testWidgets('a screen that goes away before the question drops the '
        'batch and its copies', (tester) async {
      await open(gateClashes: true);
      // Made and removed in sync calls, which the test's clock doesn't hold.
      final dir = Directory.systemTemp.createTempSync('telegrive_clash');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copies = [
        for (final name in ['Fresh.txt', 'Notes.txt'])
          File(p.join(dir.path, name))..writeAsStringSync(name),
      ];
      final (context, ref) = await pumpScreen(tester);
      final resolved = FileActions.resolveUploadClashes(context, ref, [
        for (final copy in copies)
          UploadRequest(
            name: p.basename(copy.path),
            path: copy.path,
            ownsSource: true,
          ),
      ], folderId: 'work');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      (repository as _GatedRepository).gate.complete();

      // The copies go through real file deletes, which need real time.
      List<UploadRequest>? left;
      unawaited(resolved.then((requests) => left = requests));
      for (var i = 0; i < 200 && left == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(left, isEmpty);
      expect(copies.map((c) => c.existsSync()), everyElement(isFalse));
    });

    testWidgets('swiping the question away skips that file', (tester) async {
      await open();
      final resolved = await resolve(tester, ['Notes.txt', 'Fresh.txt']);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(
        [for (final request in await resolved) request.name],
        ['Fresh.txt'],
      );
    });
  });

  group('an upload that replaces', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('telegrive_clash');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      container.dispose();
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    test(
      'trashes the old file as replaced once the new one has landed',
      () async {
        await open(client: _UploadTelegram());
        final source = File(p.join(dir.path, 'Budget 2026.xlsx'))
          ..writeAsStringSync('new figures');
        container.read(channelMessengerProvider);
        final queue = container.read(transferQueueProvider.notifier);
        TransfersState state() => container.read(transferQueueProvider);

        final [id] = await queue.enqueueUploads([
          UploadRequest(
            name: 'Budget 2026.xlsx',
            path: source.path,
            replacesFileId: 'a',
          ),
        ], folderId: 'work');
        await until(() => state().byId(id)?.status == TransferStatus.completed);
        final newFileId = state().byId(id)!.row.fileId;
        // The replace follows the upload's completion by a moment.
        for (var i = 0; i < 200 && (await file('a')).trashedAt == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        final landed = await file(newFileId);
        expect(landed.name, 'Budget 2026.xlsx');
        expect(landed.folderId, 'work');
        final old = await file('a');
        expect(old.trashedAt, isNotNull);
        expect(old.replacedBy, newFileId);
        expect(caption(10), contains(';replacedby=$newFileId;'));
        expect((await repository.previousVersionOf(newFileId))!.id, 'a');
        expect(
          (await repository.nameClashes([
            'Budget 2026.xlsx',
          ], 'work'))['budget 2026.xlsx']!.id,
          newFileId,
        );
      },
    );
  });
}
