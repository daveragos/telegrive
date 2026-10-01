import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/files/presentation/folder_picker.dart';
import 'package:telegrive/features/share/data/recent_destinations.dart';
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

/// A sync that never runs.
class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();
}

/// Keeps what it is asked to upload, and uploads nothing. Each upload
/// stands in the list as [status] says, as the drive file [fileId].
class _Queue extends TransferQueue {
  _Queue({this.status = TransferStatus.queued, this.fileId = 'new'});

  final TransferStatus status;
  final String fileId;
  final uploads = <(UploadRequest, String?)>[];
  final removed = <String>[];
  var _next = 0;

  @override
  TransfersState build() => TransfersState.empty;

  @override
  Future<List<String>> enqueueUploads(
    List<UploadRequest> requests, {
    String? folderId,
  }) async {
    final rows = [
      for (final request in requests)
        TransferRow(
          id: 't${_next++}',
          kind: TransferKind.upload,
          status: status,
          name: request.name,
          mimeType: 'image/png',
          fileId: fileId,
          folderId: folderId,
          sourcePath: request.path,
          ownsSource: request.ownsSource,
          wifiOnly: false,
          totalBytes: 5,
          doneBytes: 0,
          partCount: 1,
          completedParts: 0,
          createdAt: DateTime(2026, 9, 26),
          origin: TransferOrigin.manual,
        ),
    ];
    uploads.addAll([for (final request in requests) (request, folderId)]);
    state = TransfersState([...state.items, for (final row in rows) TransferItem(row)]);
    return [for (final row in rows) row.id];
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    state = TransfersState([
      for (final item in state.items)
        if (item.id != id) item,
    ]);
  }
}

void main() {
  // Each screen test leaves its in-memory database open: it closes on a
  // timer that would fire after the test's clock has stopped.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late Directory root;
  late AppDatabase db;
  late FakeTelegram telegram;
  late SharedPreferences shared;
  late DriveRepository repository;
  late _Queue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('share_sheet_test');
    db = AppDatabase(NativeDatabase.memory());
    telegram = FakeTelegram();
    queue = _Queue();
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// A copy of a shared file, alone in a folder of its own as the activity
  /// leaves it.
  File copied(String name, {int n = 1}) =>
      File(p.join(root.path, 'shared', '$n', name))
        ..createSync(recursive: true)
        ..writeAsStringSync('photo');

  /// Lets the index, the files on disk and the screen catch up, a frame
  /// at a time, until [condition].
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue);
  }

  /// Closes the app and lets the timers it leaves behind run out: the
  /// snack's, and the database's stream clean-up.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  /// Taps Undo once the snack has come all the way in.
  Future<void> tapUndo(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Undo'));
  }

  /// A drive with Receipts and Invoices, Old in the trash, and Receipt.png
  /// in Receipts; a screen with a Share button that brings up what was
  /// shared, [files]; and [recent] as the folders last used. The button is
  /// tapped unless [share] is off.
  Future<void> pumpShare(
    WidgetTester tester,
    List<SharedFile> files, {
    List<String> recent = const [],
    bool share = true,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'recent_destinations': recent});
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(container.dispose);
    repository = container.read(driveRepositoryProvider);
    await tester.runAsync(() async {
      shared = await SharedPreferences.getInstance();
      for (final message in [
        textMessage(1, '📁 Receipts\ntgrf1:{"id":"receipts","n":"Receipts","ct":1700000000000}'),
        textMessage(2, '📁 Invoices\ntgrf1:{"id":"invoices","n":"Invoices","ct":1700000000000}'),
        textMessage(
          3,
          '📁 Old\ntgrf1:{"id":"old","n":"Old","ct":1700000000000,"tr":1700000000000}',
        ),
        documentMessage(
          10,
          'Receipt.png\ntgr1:{"id":"a","n":"Receipt.png","f":"receipts",'
          '"m":"image/png","s":9,"ct":1700000000000}',
          fileName: 'Receipt.png',
          mimeType: 'image/png',
        ),
      ]) {
        telegram.messages[message.id] = message;
        await repository.ingest(message);
      }
    });

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
          telegramClientProvider.overrideWithValue(telegram),
          driveSessionProvider.overrideWith(TestSession.new),
          driveSyncProvider.overrideWith(_Sync.new),
          transferQueueProvider.overrideWith(() => queue),
          shareIntakeProvider.overrideWith(() => _Intake(files)),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    // The recent folders are looked up as the drive opens.
    await until(tester, () => true);
    if (share) await tester.tap(find.text('Share'));
  }

  Future<DriveFile> receiptInDrive(WidgetTester tester) async =>
      (await tester.runAsync(() => repository.fileById('a')))!;

  testWidgets('a share to a folder\'s own target goes straight in, under a '
      'name of its own, and Undo cancels it', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(tester, [
      SharedFile(path: copy.path, name: 'Receipt.png', size: 5, folderId: 'receipts'),
    ]);
    await until(tester, () => shows('Uploading Receipt (2).png to Receipts'));

    expect(find.text('Save to Telegrive'), findsNothing);
    final (request, folderId) = queue.uploads.single;
    expect(folderId, 'receipts');
    expect(request.name, 'Receipt (2).png');
    // Telegram names the document after the file, so the copy takes the
    // name first.
    expect(p.basename(request.path!), 'Receipt (2).png');
    expect(shared.getStringList('recent_destinations'), ['receipts']);

    await tapUndo(tester);
    await until(tester, () => shows('Cancelled the upload'));

    expect(queue.removed, ['t0']);
    expect(queue.state.items, isEmpty);
    expect(File(request.path!).existsSync(), isFalse);
    expect((await receiptInDrive(tester)).trashedAt, isNull);

    await close(tester);
  });

  testWidgets('Undo once the file has arrived puts it in Trash', (tester) async {
    queue = _Queue(status: TransferStatus.completed, fileId: 'a');
    final copy = copied('Lunch.png');
    await pumpShare(tester, [
      SharedFile(path: copy.path, name: 'Lunch.png', size: 5, folderId: 'receipts'),
    ]);
    await until(tester, () => shows('Uploading Lunch.png to Receipts'));

    await tapUndo(tester);
    await until(
      tester,
      () => shows('Cancelled. What had already arrived is in Trash.'),
    );

    expect(queue.removed, ['t0']);
    expect((await receiptInDrive(tester)).trashedAt, isNotNull);

    await close(tester);
  });

  testWidgets('several files shared to a folder say how many', (tester) async {
    await pumpShare(tester, [
      for (final (n, name) in ['One.png', 'Two.png', 'Note.txt'].indexed)
        SharedFile(
          path: copied(name, n: n).path,
          name: name,
          size: 5,
          folderId: 'invoices',
        ),
    ]);
    await until(tester, () => shows('Uploading 3 files to Invoices'));

    expect(
      [for (final (request, folderId) in queue.uploads) '${request.name} $folderId'],
      ['One.png invoices', 'Two.png invoices', 'Note.txt invoices'],
    );

    await close(tester);
  });

  testWidgets('a target whose folder is in the trash asks instead', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(tester, [
      SharedFile(path: copy.path, name: 'Receipt.png', size: 5, folderId: 'old'),
    ]);
    await until(tester, () => shows('Save to Telegrive'));

    expect(queue.uploads, isEmpty);
    expect(find.text('Old'), findsNothing);

    await close(tester);
  });

  testWidgets('a target whose folder was trashed since the folders were '
      'looked up asks, starting on Files', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(
      tester,
      [SharedFile(path: copy.path, name: 'Receipt.png', size: 5, folderId: 'receipts')],
      recent: ['receipts'],
      share: false,
    );
    final container = ProviderScope.containerOf(tester.element(find.text('Share')));
    container.listen(recentDestinationsProvider, (_, _) {});
    await until(tester, () => container.read(recentDestinationsProvider).isNotEmpty);
    // Trashed on another device: the index hears of it, and no sync runs.
    await tester.runAsync(
      () => repository.ingest(
        textMessage(
          1,
          '📁 Receipts\ntgrf1:{"id":"receipts","n":"Receipts",'
          '"ct":1700000000000,"tr":1700000000000}',
        ),
      ),
    );

    await tester.tap(find.text('Share'));
    await until(tester, () => shows('Save to Telegrive'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Files')), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Receipts'), findsNothing);

    await tester.tap(find.text('Upload'));
    await until(tester, () => queue.uploads.isNotEmpty);
    expect(queue.uploads.single.$2, isNull);

    await close(tester);
  });

  testWidgets('the sheet starts on the last folder used and offers the '
      'others', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(
      tester,
      [SharedFile(path: copy.path, name: 'Receipt.png', size: 5)],
      recent: ['invoices', 'receipts', ''],
    );
    await until(tester, () => shows('Save to Telegrive') && shows('Invoices'));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    final chips = find.byType(ChoiceChip);
    expect(
      [for (final chip in tester.widgetList<ChoiceChip>(chips)) (chip.label as Text).data],
      ['Receipts', 'Files'],
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Files'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Files')).selected, isTrue);
    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Files')), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Receipts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await until(tester, () => queue.uploads.isNotEmpty);

    expect(queue.uploads.single.$2, 'receipts');
    await until(
      tester,
      () => shared.getStringList('recent_destinations')?.first == 'receipts',
    );

    await close(tester);
  });

  testWidgets('with no folder used yet the sheet starts on Files, with no '
      'chips', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(tester, [SharedFile(path: copy.path, name: 'Receipt.png', size: 5)]);
    await until(tester, () => shows('Save to Telegrive'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(ListTile), matching: find.text('Files')), findsOneWidget);
    expect(find.text('Recent'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    await close(tester);
  });

  testWidgets('Change asks where to save, and Move still says Move to', (tester) async {
    final copy = copied('Receipt.png');
    await pumpShare(
      tester,
      [SharedFile(path: copy.path, name: 'Receipt.png', size: 5)],
      recent: ['invoices'],
    );
    await until(tester, () => shows('Save to Telegrive') && shows('Invoices'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await until(tester, () => shows('Save to Invoices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Invoices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Share'));
    unawaited(showFolderPicker(context, title: 'Move 1 item'));
    await until(tester, () => shows('Move to Files'));

    await close(tester);
  });
}
