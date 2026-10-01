import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/share/data/share_intake.dart';
import 'package:telegrive/features/share/presentation/share_sheet.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Starts with files already taken from the activity.
class _Intake extends ShareIntake {
  _Intake(this.files);

  final List<SharedFile> files;

  @override
  List<SharedFile> build() => files;
}

/// A channel where every document arrives as soon as it is sent.
class _Telegram extends FakeTelegram {
  var _nextId = 1;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function
        case td.SendMessage(
          inputMessageContent: td.InputMessageDocument(
            document: td.InputFileLocal(:final path),
            :final caption?,
          ),
        )) {
      final message = documentMessage(
        _nextId++,
        caption.text,
        fileName: p.basename(path),
        mimeType: 'text/plain',
      );
      return messages[message.id] = message;
    }
    return null;
  }
}

void main() {
  test('a copy is owned, a gallery original is not, and a file with no room is left out', () {
    final files = SharedFile.listFrom([
      {'path': '/cache/shared/1/note.txt', 'name': 'note.txt', 'size': 12},
      {'path': '/storage/DCIM/Camera/clip.mp4', 'name': 'clip.mp4', 'size': 900, 'owned': false},
      {'path': '/cache/shared/2/scan.pdf', 'name': 'scan.pdf', 'size': 40, 'owned': true},
      {'name': 'movie.mkv', 'size': 1200, 'free': 180, 'tooBig': true},
    ]);

    expect([for (final f in files) f.name], ['note.txt', 'clip.mp4', 'scan.pdf']);
    expect([for (final f in files) f.owned], [true, false, true]);
    expect(files[1].size, 900);
  });

  test('a file shared to a folder\'s own target carries the folder', () {
    final [plain, toFolder] = SharedFile.listFrom([
      {'path': '/cache/shared/1/receipt.png', 'name': 'receipt.png', 'size': 12},
      {
        'path': '/cache/shared/2/receipt.png',
        'name': 'receipt.png',
        'size': 12,
        'folderId': 'receipts',
      },
    ]);

    expect(plain.folderId, isNull);
    expect(toFolder.folderId, 'receipts');
  });

  test('discarding a share deletes its copies and never an original', () async {
    final root = Directory.systemTemp.createTempSync('share_intake_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final copy = File(p.join(root.path, 'shared', '1', 'note.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('hello');
    final original = File(p.join(root.path, 'DCIM', 'Camera', 'clip.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('video');
    final neighbour = File(p.join(original.parent.path, 'photo.jpg'))..writeAsStringSync('photo');

    final container = ProviderContainer(
      overrides: [
        shareIntakeProvider.overrideWith(
          () => _Intake([
            SharedFile(path: copy.path, name: 'note.txt', size: 5),
            SharedFile(path: original.path, name: 'clip.mp4', size: 5, owned: false),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(shareIntakeProvider.notifier).clear(discard: true);

    expect(container.read(shareIntakeProvider), isEmpty);
    expect(copy.parent.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
    expect(neighbour.existsSync(), isTrue);
  });

  testWidgets('the sheet uploads a gallery original from where it is and keeps it', (
    tester,
  ) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final root = Directory.systemTemp.createTempSync('share_sheet_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final copy = File(p.join(root.path, 'shared', '1', 'note.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('hello');
    final original = File(p.join(root.path, 'DCIM', 'Camera', 'clip.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('video');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => root.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null),
    );

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showShareSheet(context, ref),
                child: const Text('Share'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          appDatabaseProvider.overrideWithValue(db),
          telegramClientProvider.overrideWithValue(_Telegram()),
          driveSessionProvider.overrideWith(TestSession.new),
          shareIntakeProvider.overrideWith(
            () => _Intake([
              SharedFile(path: copy.path, name: 'note.txt', size: 5),
              SharedFile(path: original.path, name: 'clip.mp4', size: 5, owned: false),
            ]),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.text('Share')));

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Save 2 files to Telegrive'), findsOneWidget);

    List<TransferItem> items() => container.read(transferQueueProvider).items;
    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(condition(), isTrue);
    }

    await tester.runAsync(() async {
      // The queue reads its saved rows first, as it does when the drive opens.
      var loaded = false;
      container.listen<TransfersState>(transferQueueProvider, (_, _) => loaded = true);
      await until(() => loaded);

      await tester.tap(find.text('Upload'));
      // Done once both are in the drive and the queue has let go of its copy.
      await until(
        () =>
            items().length == 2 &&
            items().every((item) => item.status == TransferStatus.completed) &&
            !copy.existsSync(),
      );
    });
    await tester.pumpAndSettle();

    final rows = {for (final row in await db.allTransfers()) row.name: row};
    expect(rows['note.txt']!.ownsSource, isTrue);
    expect(rows['clip.mp4']!.ownsSource, isFalse);
    expect(rows['clip.mp4']!.sourcePath, original.path);
    expect(original.existsSync(), isTrue);
    // The root, which the sheet starts on with nothing used yet, is where
    // the next share starts too.
    expect(shared.getStringList('recent_destinations'), ['']);
  });
}
