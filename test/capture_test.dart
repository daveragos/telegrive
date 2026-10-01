import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/capture/data/device_capture.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/files/presentation/file_actions.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

/// A scanner and camera that hand back [shot], or refuse with [error].
class _Capture extends DeviceCapture {
  _Capture({this.shot, this.error});

  final CapturedFile? shot;
  final PlatformException? error;

  @override
  Future<CapturedFile?> capture(CaptureKind kind) async {
    if (error case final error?) throw error;
    return shot;
  }
}

/// Keeps what it is asked to upload, and uploads nothing. Its uploads
/// finish when [finished] completes. It starts out holding [queued].
class _Queue extends TransferQueue {
  _Queue({this.queued = const []});

  final List<TransferRow> queued;
  final uploads = <(UploadRequest, String?)>[];
  final finished = Completer<TransferRow>();

  @override
  TransfersState build() =>
      TransfersState([for (final row in queued) TransferItem(row)]);

  @override
  Future<List<String>> enqueueUploads(
    List<UploadRequest> requests, {
    String? folderId,
  }) async {
    uploads.addAll([for (final request in requests) (request, folderId)]);
    return [for (final _ in requests) 'id'];
  }

  @override
  Future<TransferRow> whenFinished(String id) => finished.future;
}

/// The row of an upload of [name] into [folderId], as [status] says.
TransferRow _uploadRow(
  String name,
  TransferStatus status, {
  String? folderId,
}) => TransferRow(
  id: 'id',
  kind: TransferKind.upload,
  status: status,
  name: name,
  mimeType: 'image/jpeg',
  fileId: 'file',
  folderId: folderId,
  ownsSource: true,
  wifiOnly: false,
  totalBytes: 5,
  doneBytes: 5,
  partCount: 1,
  completedParts: 1,
  createdAt: DateTime(2026, 9, 26),
  origin: TransferOrigin.manual,
);

void main() {
  late Directory root;
  late AppDatabase db;
  late _Queue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('capture_test');
    db = AppDatabase(NativeDatabase.memory());
    queue = _Queue();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// A file called [name] in the drive's Receipts folder.
  Future<void> inReceipts(WidgetTester tester, String name) =>
      tester.runAsync(
        () => db.upsertFilePart(
          DriveFilesCompanion.insert(
            id: name,
            folderId: const Value('receipts'),
            name: name,
            mimeType: 'application/pdf',
            kind: FileKind.document,
            size: 5,
            createdAt: DateTime(2026, 9, 25),
            modifiedAt: DateTime(2026, 9, 25),
          ),
          FilePartsCompanion.insert(
            fileId: name,
            partIndex: 0,
            messageId: 2,
            tdFileId: 2,
            size: 5,
          ),
        ),
      );

  /// A capture as the channel leaves it: alone in a folder of its own.
  File captured(String name) => File(p.join(root.path, 'captured', '1', name))
    ..createSync(recursive: true)
    ..writeAsStringSync('pages');

  /// Lets the files on disk and the index catch up, frame by frame, until
  /// [condition], then runs the timers the index leaves behind once a
  /// query is read.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(condition(), isTrue);
    await tester.pump(Duration.zero);
  }

  /// A screen in the Receipts folder with a button that starts [kind], on a
  /// phone that can make what [support] says.
  Future<void> pumpFolder(
    WidgetTester tester,
    DeviceCapture capture, {
    CaptureKind kind = CaptureKind.scan,
    CaptureSupport support = const CaptureSupport(scan: true, photo: true),
  }) async {
    await tester.runAsync(
      () => db.upsertFolder(
        FoldersCompanion.insert(
          id: 'receipts',
          name: 'Receipts',
          messageId: 1,
          createdAt: DateTime(2026, 9, 26),
          modifiedAt: DateTime(2026, 9, 26),
        ),
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => FileActions.capture(
                  context,
                  ref,
                  kind,
                  folderId: 'receipts',
                ),
                child: const Text('Capture'),
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
          appDatabaseProvider.overrideWithValue(db),
          deviceCaptureProvider.overrideWithValue(capture),
          captureSupportProvider.overrideWithValue(AsyncData(support)),
          transferQueueProvider.overrideWith(() => queue),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a renamed scan uploads into the folder from a file of that name',
    (tester) async {
      final scan = captured('Scan 2026-09-26 14.03.pdf');
      await pumpFolder(
        tester,
        _Capture(
          shot: CapturedFile(
            path: scan.path,
            name: 'Scan 2026-09-26 14.03.pdf',
            size: 5,
          ),
        ),
      );
      expect(find.text('Name this scan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Lunch receipt');
      await tester.tap(find.text('Upload'));
      await until(
        tester,
        () => find
            .text('Uploading Lunch receipt.pdf to Receipts')
            .evaluate()
            .isNotEmpty,
      );

      final (request, folderId) = queue.uploads.single;
      expect(request.name, 'Lunch receipt.pdf');
      expect(p.basename(request.path!), 'Lunch receipt.pdf');
      expect(File(request.path!).existsSync(), isTrue);
      expect(scan.existsSync(), isFalse);
      expect(request.ownsSource, isTrue);
      expect(request.takenAt, isNull);
      expect(folderId, 'receipts');
      expect(find.text('View'), findsOneWidget);
    },
  );

  testWidgets('a photo kept under its own name carries when it was taken', (
    tester,
  ) async {
    final photo = captured('Photo 2026-09-26 14.03.jpg');
    final takenAt = DateTime(2026, 9, 26, 14, 3, 12);
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(
          path: photo.path,
          name: 'Photo 2026-09-26 14.03.jpg',
          size: 5,
          takenAt: takenAt,
        ),
      ),
      kind: CaptureKind.photo,
    );
    expect(find.text('Name this photo'), findsOneWidget);

    await tester.tap(find.text('Upload'));
    await until(tester, () => queue.uploads.isNotEmpty);

    final (request, _) = queue.uploads.single;
    expect(request.name, 'Photo 2026-09-26 14.03.jpg');
    expect(request.path, photo.path);
    expect(request.takenAt, takenAt);
  });

  testWidgets('an uploaded capture takes its folder with it', (tester) async {
    final photo = captured('Photo 2026-09-26 14.03.jpg');
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(
          path: photo.path,
          name: 'Photo 2026-09-26 14.03.jpg',
          size: 5,
        ),
      ),
      kind: CaptureKind.photo,
    );
    await tester.tap(find.text('Upload'));
    await until(tester, () => queue.uploads.isNotEmpty);

    // The queue reports the upload done before it deletes the file it owns.
    queue.finished.complete(
      _uploadRow(p.basename(photo.path), TransferStatus.completed),
    );
    await until(tester, () => !photo.parent.existsSync());
  });

  for (final status in [TransferStatus.failed, TransferStatus.cancelled]) {
    testWidgets('a ${status.name} upload keeps the capture for Retry', (
      tester,
    ) async {
      final photo = captured('Photo 2026-09-26 14.03.jpg');
      await pumpFolder(
        tester,
        _Capture(
          shot: CapturedFile(
            path: photo.path,
            name: 'Photo 2026-09-26 14.03.jpg',
            size: 5,
          ),
        ),
        kind: CaptureKind.photo,
      );
      await tester.tap(find.text('Upload'));
      await until(tester, () => queue.uploads.isNotEmpty);

      queue.finished.complete(_uploadRow(p.basename(photo.path), status));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(photo.existsSync(), isTrue);
    });
  }

  testWidgets('a name the folder already has gets a number', (tester) async {
    await inReceipts(tester, 'Lunch receipt.pdf');
    final scan = captured('Scan 2026-09-26 14.03.pdf');
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(
          path: scan.path,
          name: 'Scan 2026-09-26 14.03.pdf',
          size: 5,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Lunch receipt');
    await tester.tap(find.text('Upload'));
    await until(
      tester,
      () => find
          .text('Uploading Lunch receipt (2).pdf to Receipts')
          .evaluate()
          .isNotEmpty,
    );

    final (request, _) = queue.uploads.single;
    expect(request.name, 'Lunch receipt (2).pdf');
    expect(p.basename(request.path!), 'Lunch receipt (2).pdf');
    expect(File(request.path!).existsSync(), isTrue);
  });

  testWidgets('a name an upload into the folder is still taking gets a '
      'number', (tester) async {
    queue = _Queue(
      queued: [
        _uploadRow(
          'Scan 2026-09-26 14.03.pdf',
          TransferStatus.queued,
          folderId: 'receipts',
        ),
      ],
    );
    final scan = captured('Scan 2026-09-26 14.03.pdf');
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(
          path: scan.path,
          name: 'Scan 2026-09-26 14.03.pdf',
          size: 5,
        ),
      ),
    );

    await tester.tap(find.text('Upload'));
    await until(
      tester,
      () => find
          .text('Uploading Scan 2026-09-26 14.03 (2).pdf to Receipts')
          .evaluate()
          .isNotEmpty,
    );

    expect(queue.uploads.single.$1.name, 'Scan 2026-09-26 14.03 (2).pdf');
  });

  testWidgets('Discard deletes the capture and its folder', (tester) async {
    final scan = captured('Scan 2026-09-26 14.03.pdf');
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(
          path: scan.path,
          name: 'Scan 2026-09-26 14.03.pdf',
          size: 5,
        ),
      ),
    );

    await tester.tap(find.text('Discard'));
    await until(
      tester,
      () => find.text('Scan discarded').evaluate().isNotEmpty,
    );

    expect(scan.parent.existsSync(), isFalse);
    expect(queue.uploads, isEmpty);
  });

  testWidgets('a scanner that can\'t start offers a photo instead', (
    tester,
  ) async {
    await pumpFolder(
      tester,
      _Capture(error: PlatformException(code: 'unavailable')),
    );

    expect(
      find.text('This phone can\'t scan documents right now.'),
      findsOneWidget,
    );
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Name this scan'), findsNothing);
  });

  testWidgets('a scanner that can\'t start, on a phone without a camera app, '
      'offers nothing else', (tester) async {
    await pumpFolder(
      tester,
      _Capture(error: PlatformException(code: 'unavailable')),
      support: const CaptureSupport(scan: true, photo: false),
    );

    expect(
      find.text('This phone can\'t scan documents right now.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets('a capture without an extension keeps the name as typed', (
    tester,
  ) async {
    final scan = captured('Scan');
    await pumpFolder(
      tester,
      _Capture(
        shot: CapturedFile(path: scan.path, name: 'Scan', size: 5),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Lunch receipt');
    await tester.tap(find.text('Upload'));
    await until(tester, () => queue.uploads.isNotEmpty);

    expect(queue.uploads.single.$1.name, 'Lunch receipt');
  });

  testWidgets('backing out of the camera says nothing', (tester) async {
    await pumpFolder(tester, _Capture(), kind: CaptureKind.photo);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('freeName', () {
    late ProviderContainer container;
    late DriveRepository repository;

    setUp(() {
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      repository = container.read(driveRepositoryProvider);
    });

    tearDown(() => container.dispose());

    test('leaves a free name alone', () {
      expect(
        repository.freeName('Budget 2026.xlsx', {'notes.txt'}),
        'Budget 2026.xlsx',
      );
    });

    test('numbers a taken name, whatever its case', () {
      expect(
        repository.freeName('Budget 2026.xlsx', {'budget 2026.xlsx'}),
        'Budget 2026 (2).xlsx',
      );
    });

    test('skips numbers that are taken too', () {
      expect(
        repository.freeName('Budget 2026.xlsx', {
          'budget 2026.xlsx',
          'budget 2026 (2).xlsx',
        }),
        'Budget 2026 (3).xlsx',
      );
    });
  });
}
