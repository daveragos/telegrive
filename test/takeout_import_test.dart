import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/zip_file_source.dart';
import 'package:telegrive/core/files/zip_reader.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/files/data/bulk_edits.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/features/drive/domain/manifest.dart';
import 'package:telegrive/features/takeout/data/takeout_files.dart';
import 'package:telegrive/features/takeout/data/takeout_import.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/storage/device_profile.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';
import 'support/zip_builder.dart';

/// Delivers every document sent to it, the way TDLib does, and keeps each
/// caption under the file's name.
class _UploadTelegram extends FakeTelegram {
  final _updates = StreamController<td.TdObject>.broadcast();
  final Map<String, String> captions = {};

  @override
  Stream<td.TdObject> get updates => _updates.stream;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.SendMessage(
        inputMessageContent: td.InputMessageDocument(document: td.InputFileLocal(:final path), :final caption?),
      ):
        final name = p.basename(path);
        captions[name] = caption.text;
        final pendingId = nextId++;
        final delivered = documentMessage(nextId++, caption.text, fileName: name);
        messages[delivered.id] = delivered;
        Timer.run(() => _updates.add(td.UpdateMessageSendSucceeded(message: delivered, oldMessageId: pendingId)));
        return documentMessage(
          pendingId,
          caption.text,
          fileName: name,
        ).copyWith(sendingState: const td.MessageSendingStatePending(sendingId: 0));
      case td.SendMessage(inputMessageContent: td.InputMessageText()):
        // A folder or album takes a moment to reach Telegram, as it does
        // over a real network; the message itself comes from FakeTelegram.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return null;
      default:
        return null;
    }
  }
}

class _Sync extends DriveSync {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> whenIdle() async {}
}

class _Network extends NetworkStatus {
  @override
  NetworkState build() => const NetworkState(online: true, metered: false);
}

/// The parts the picker hands over: zip files in a folder, by their paths.
class _Files extends TakeoutFiles {
  List<File> picks = [];
  final Set<String> released = {};
  final Set<String> deleted = {};

  @override
  Future<List<PickedArchive>> pick() async => [
    for (final file in picks) PickedArchive(uri: file.path, name: p.basename(file.path), size: file.lengthSync()),
  ];

  @override
  ZipSource open(String uri, int length) => ZipFileSource(uri, length);

  @override
  Future<bool> canRead(String uri) async => File(uri).existsSync();

  @override
  Future<void> release(String uri) async => released.add(uri);

  @override
  Future<bool> delete(String uri) async {
    File(uri).deleteSync();
    deleted.add(uri);
    return true;
  }

  @override
  Future<void> closeAll() async {}
}

const _photos = 'Takeout/Google Photos';

Map<String, Object> _details(String title, DateTime taken, {bool favorited = false}) => {
  'title': title,
  'creationTime': {'timestamp': '1700000000'},
  'photoTakenTime': {'timestamp': '${taken.millisecondsSinceEpoch ~/ 1000}'},
  'favorited': favorited,
};

List<int> _bytes(int seed, int length) => [for (var i = 0; i < length; i++) (i * 31 + seed) & 0xFF];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late _UploadTelegram telegram;
  late _Files files;
  late ProviderContainer container;
  late TakeoutImport import;

  final june = DateTime(2019, 6, 15, 14, 25);
  final july = DateTime(2019, 7, 1, 9);
  final may = DateTime(2020, 5, 5, 18);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('telegrive_takeout');
    db = AppDatabase(NativeDatabase.memory());
    telegram = _UploadTelegram();
    files = _Files();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch});
    final shared = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        networkStatusProvider.overrideWith(_Network.new),
        saveMemoryProvider.overrideWithBuild((ref, notifier) => false),
        takeoutFilesProvider.overrideWithValue(files),
      ],
    );
    container.read(transferQueueProvider);
    await container.read(transferQueueProvider.notifier).loaded;
    import = container.read(takeoutImportProvider.notifier);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    container.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Waits until the import has nothing left to do, or [test] says so.
  Future<TakeoutState> settle([bool Function(TakeoutState s)? test]) async {
    bool done(TakeoutState s) =>
        test?.call(s) ??
        (s.progress?.finished == true && s.phase == TakeoutPhase.idle && !s.working);
    for (var i = 0; i < 500 && !done(container.read(takeoutImportProvider)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return container.read(takeoutImportProvider);
  }

  /// A two-part export: a photo in a year and an album, split across the
  /// parts, and a video whose details are in the other part.
  Future<void> export() async {
    final one = ZipBuilder()
      ..add('$_photos/Photos from 2019/IMG_1.jpg', _bytes(1, 4000), deflate: false)
      ..addJson('$_photos/Photos from 2019/IMG_1.jpg.supplemental-metadata.json', _details('IMG_1.jpg', june, favorited: true))
      ..add('$_photos/Photos from 2019/IMG_2.jpg', _bytes(2, 5000))
      ..addJson('$_photos/Photos from 2019/IMG_2.jpg.supplemental-metadata.json', _details('IMG_2.jpg', july))
      ..addJson('$_photos/Trip to Lalibela/metadata.json', {
        'title': 'Trip to Lalibela',
        'access': 'protected',
        'date': {'timestamp': '1562000000'},
      })
      ..addJson('$_photos/Photos from 2020/VID_3.mp4.supplemental-metadata.json', _details('VID_3.mp4', may))
      ..addText('Takeout/archive_browser.html', '<html></html>');
    final two = ZipBuilder()
      ..add('$_photos/Trip to Lalibela/IMG_1.jpg', _bytes(1, 4000), deflate: false)
      ..add('$_photos/Trip to Lalibela/IMG_2.jpg', _bytes(2, 5000))
      ..addJson('$_photos/Trip to Lalibela/IMG_2.jpg.supplemental-metadata.json', _details('IMG_2.jpg', july))
      ..add('$_photos/Photos from 2020/VID_3.mp4', _bytes(3, 9000));
    files.picks = [
      await two.write(p.join(dir.path, 'takeout-20261005T101010Z-002.zip')),
      await one.write(p.join(dir.path, 'takeout-20261005T101010Z-001.zip'), zip64: true),
    ];
  }

  FileManifest manifest(String name) => ManifestCodec.decodeFile(telegram.captions[name]!)!;

  Future<List<String>> pathOf(String folderId) async => [
    for (final folder in await container.read(driveRepositoryProvider).pathTo(folderId)) folder.name,
  ];

  test('reads every part and shows what it holds before anything goes up', () async {
    await export();
    expect(await import.addParts(), 2);
    final state = await settle((s) => s.progress != null && s.phase == TakeoutPhase.idle);
    final progress = state.progress!;
    expect(progress.total, 3);
    expect(progress.photos, 2);
    expect(progress.videos, 1);
    expect(progress.albums, 1);
    expect(progress.bytes, 4000 + 5000 + 9000);
    expect(progress.left, 3);
    expect(state.running, isFalse);
    expect(telegram.captions, isEmpty);
    final parts = await db.takeoutPartList();
    expect(parts.every((part) => part.readAt != null && part.problem == null), isTrue);
  });

  test('sends each photo once, into its year, with its time, star and albums', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    final steps = <(String, TakeoutStep)>{};
    container.listen<TakeoutState>(takeoutImportProvider, (_, next) {
      for (final flight in next.flights) {
        steps.add((flight.name, flight.step));
      }
    });
    await import.start();
    final state = await settle();

    expect(state.progress!.sent, 3);
    expect(telegram.captions.keys.toSet(), {'IMG_1.jpg', 'IMG_2.jpg', 'VID_3.mp4'});
    // The fake Telegram makes no previews, so the three wait for theirs.
    final counted = await settle((s) => s.withoutPreview.count == 3);
    expect(counted.withoutPreview.bytes, 4000 + 5000 + 9000);
    // Each file showed what was being done with it, and none is left in hand.
    for (final name in ['IMG_1.jpg', 'IMG_2.jpg', 'VID_3.mp4']) {
      expect(steps, containsAll([(name, TakeoutStep.extracting), (name, TakeoutStep.uploading)]));
    }
    expect(state.flights, isEmpty);
    // Done, it stops, and says so after a restart too.
    expect(state.running, isFalse);
    expect(container.read(preferencesProvider).takeoutRunning, isFalse);

    final first = manifest('IMG_1.jpg');
    expect(first.takenAt, june);
    expect(first.starred, isTrue);
    expect(await pathOf(first.folderId!), ['Google Photos', '2019']);

    final second = manifest('IMG_2.jpg');
    expect(second.starred, isFalse);
    final album = await db.albumNamed('Trip to Lalibela');
    expect(album, isNotNull);
    expect(second.albums, [album!.id]);
    expect(await db.albumIdsOf(second.id), [album.id]);
    // Both went into the one album, though they went up at once.
    expect(first.albums, [album.id]);
    expect((await db.watchAlbums().first).where((a) => a.album.name == 'Trip to Lalibela'), hasLength(1));

    final video = manifest('VID_3.mp4');
    expect(video.takenAt, may);
    expect(await pathOf(video.folderId!), ['Google Photos', '2020']);

    // Two uploads going at once share one folder for their year, and one
    // Google Photos above them all.
    expect(second.folderId, first.folderId);
    final roots = await db.watchChildFolders(null).first;
    expect(roots.where((f) => f.name == 'Google Photos'), hasLength(1));
    final years = await db.watchChildFolders(roots.single.id).first;
    expect(years.map((f) => f.name).toList()..sort(), ['2019', '2020']);

    final ledger = await db.takeoutLedger();
    expect(ledger.values.map((row) => row.state).toSet(), {TakeoutItemState.done});
    // Finished uploads leave Transfers, and the copies taken out go once
    // each upload has tidied up after itself.
    expect(await db.allTransfers(), isEmpty);
    List<File> copies() => Directory(p.join(dir.path, 'takeout')).listSync(recursive: true).whereType<File>().toList();
    for (var i = 0; i < 200 && copies().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(copies(), isEmpty);
  });

  test('a second look sends nothing again, and a done part can be deleted', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.start();
    await settle();
    final sent = telegram.captions.length;

    import.schedule(immediate: true);
    final again = await settle();
    expect(telegram.captions, hasLength(sent));
    expect(again.progress!.partsLeft, isEmpty);

    final parts0 = await db.takeoutPartList();
    final part = parts0.first;
    expect(await import.deletePart(part.id), isTrue);
    expect(await import.deletePart(parts0.last.id), isTrue);
    // With every part gone, it still says how the import went.
    final after = await settle((s) => s.progress?.total == 3 && s.phase == TakeoutPhase.idle && !s.working);
    expect(after.progress!.finished, isTrue);
    expect(after.progress!.sent, 3);
    expect(files.deleted, {part.uri, parts0.last.uri});
    // They stay on the list as done, so their numbers still count.
    final parts = await db.takeoutPartList();
    expect(parts, hasLength(2));
    expect(parts.every((p) => p.deletedAt != null), isTrue);
  });

  test('a photo the drive already holds is put in its album and starred, not sent again', () async {
    await export();
    // IMG_2 went up before, from this phone's camera say.
    final source = File(p.join(dir.path, 'IMG_2.jpg'))..writeAsBytesSync(_bytes(2, 5000));
    final queue = container.read(transferQueueProvider.notifier);
    final [id] = await queue.enqueueUploads([UploadRequest(name: 'IMG_2.jpg', path: source.path)]);
    final existing = (await queue.whenFinished(id)).fileId;
    telegram.captions.clear();

    await import.addParts();
    await settle((s) => s.progress != null);
    expect(container.read(takeoutImportProvider).progress!.alreadyThere, 1);
    await import.start();
    final state = await settle();

    expect(state.progress!.sent, 2);
    expect(state.progress!.inDrive, 1);
    expect(telegram.captions.keys.toSet(), {'IMG_1.jpg', 'VID_3.mp4'});
    final album = await db.albumNamed('Trip to Lalibela');
    expect(await db.albumIdsOf(existing), [album!.id]);
    expect((await db.takeoutLedger()).values.where((r) => r.state == TakeoutItemState.inDrive).single.fileId, existing);
  });

  test('a copy Google kept smaller, or one renamed since, counts as already in the drive', () async {
    await export();
    final queue = container.read(transferQueueProvider.notifier);
    // The phone backed up IMG_1 in full: same name and moment, more bytes
    // than the copy Google kept. VID_3 went up under another name.
    final original = File(p.join(dir.path, 'IMG_1.jpg'))..writeAsBytesSync(_bytes(11, 9999));
    final renamed = File(p.join(dir.path, 'clip.mp4'))..writeAsBytesSync(_bytes(3, 9000));
    final ids = await queue.enqueueUploads([
      UploadRequest(name: 'IMG_1.jpg', path: original.path, takenAt: june),
      UploadRequest(name: 'clip.mp4', path: renamed.path, takenAt: may),
    ]);
    final existing = [for (final id in ids) (await queue.whenFinished(id)).fileId];
    telegram.captions.clear();

    await import.addParts();
    final read = await settle((s) => s.progress != null && s.phase == TakeoutPhase.idle);
    expect(read.progress!.alreadyThere, 2);
    await import.start();
    final state = await settle();

    expect(state.progress!.sent, 1);
    expect(state.progress!.inDrive, 2);
    expect(telegram.captions.keys.toSet(), {'IMG_2.jpg'});
    // The full-size original keeps its place, starred as Google had it.
    expect((await db.fileById(existing.first))!.starred, isTrue);
    final ledger = (await db.takeoutLedger()).values.where((r) => r.state == TakeoutItemState.inDrive);
    expect({for (final row in ledger) row.fileId}, existing.toSet());
  });

  group('Live Photos', () {
    /// An export holding a Samsung motion photo as Google keeps it: the
    /// photo, and its movement as a video under the same name.
    Future<void> livePhoto() async {
      files.picks = [
        await (ZipBuilder()
              ..add('$_photos/Photos from 2023/20230612_183344.jpg', _bytes(7, 3000), deflate: false)
              ..addJson(
                '$_photos/Photos from 2023/20230612_183344.jpg.supplemental-metadata.json',
                _details('20230612_183344.jpg', DateTime(2023, 6, 12, 18, 33, 44)),
              )
              ..add('$_photos/Photos from 2023/20230612_183344.mp4', _bytes(8, 6000)))
            .write(p.join(dir.path, 'takeout-20261009T101010Z-001.zip')),
      ];
    }

    Future<String> phoneUpload(String name, List<int> bytes) async {
      final source = File(p.join(dir.path, 'phone-$name'))..writeAsBytesSync(bytes);
      final queue = container.read(transferQueueProvider.notifier);
      final [id] = await queue.enqueueUploads([UploadRequest(name: name, path: source.path)]);
      return (await queue.whenFinished(id)).fileId;
    }

    test('the video of a photo the phone backed up isn\'t sent', () async {
      await livePhoto();
      final still = await phoneUpload('20230612_183344.jpg', _bytes(7, 3000));
      telegram.captions.clear();
      await import.addParts();
      await settle((s) => s.progress != null && s.phase == TakeoutPhase.idle);
      await import.start();
      final state = await settle();
      expect(telegram.captions, isEmpty);
      expect(state.progress!.inDrive, 2);
      final ledger = await db.takeoutLedger();
      expect({for (final row in ledger.values) row.fileId}, {still});
    });

    test('the video of a photo that holds its own movement isn\'t sent', () async {
      // A Samsung motion photo only Google had: the photo carries the video.
      files.picks = [
        await (ZipBuilder()
              ..add('$_photos/Photos from 2025/20251008_175705.jpg', [0xFF, 0xD8, ...utf8.encode('MotionPhoto_Data'), 0xFF, 0xD9], deflate: false)
              ..addJson(
                '$_photos/Photos from 2025/20251008_175705.jpg.supplemental-metadata.json',
                _details('20251008_175705.jpg', DateTime(2025, 10, 8, 17, 57, 5)),
              )
              ..add('$_photos/Photos from 2025/20251008_175705.MP4', _bytes(9, 4000))
              // An iPhone Live Photo: the photo holds no movement.
              ..add('$_photos/Photos from 2025/IMG_0094.HEIC', _bytes(10, 2000), deflate: false)
              ..addJson(
                '$_photos/Photos from 2025/IMG_0094.HEIC.supplemental-metadata.json',
                _details('IMG_0094.HEIC', DateTime(2025, 10, 8, 18, 49, 34)),
              )
              ..add('$_photos/Photos from 2025/IMG_0094.MP4', _bytes(11, 3000)))
            .write(p.join(dir.path, 'takeout-20261009T111111Z-001.zip')),
      ];
      await import.addParts();
      await settle((s) => s.progress != null && s.phase == TakeoutPhase.idle);
      await import.start();
      final state = await settle();
      expect(telegram.captions.keys.toSet(), {'20251008_175705.jpg', 'IMG_0094.HEIC', 'IMG_0094.MP4'});
      expect(state.progress!.sent, 3);
      expect(state.progress!.inDrive, 1);
    });

    test('videos sent before the import knew are offered for the trash, and go', () async {
      await livePhoto();
      final still = await phoneUpload('20230612_183344.jpg', _bytes(7, 3000));
      final video = await phoneUpload('20230612_183344.mp4', _bytes(8, 6000));
      // As an earlier version left it: the photo found in the drive, the
      // video sent beside it.
      await import.addParts();
      await settle((s) => s.progress != null && s.phase == TakeoutPhase.idle);
      final catalog = takeoutCatalogOf(
        parts: await db.takeoutPartList(),
        entries: await db.takeoutEntryList(),
        details: await db.takeoutDetailList(),
      );
      final now = DateTime.now();
      await db.saveTakeoutItems([
        for (final item in catalog.items)
          TakeoutItemsCompanion.insert(
            key: item.key,
            state: item.motionOf == null ? TakeoutItemState.inDrive : TakeoutItemState.done,
            fileId: Value(item.motionOf == null ? still : video),
            updatedAt: now,
          ),
      ]);
      import.schedule(immediate: true);
      await settle((s) => (s.progress?.extraMotion ?? 0) == 1);

      final outcome = await import.trashExtraMotion();
      expect(outcome.complete, isTrue);
      expect(outcome.done, 1);
      // The bulk change is over, so the screen's progress line goes.
      expect(container.read(bulkEditsProvider), isNull);
      expect((await db.fileById(video))!.trashedAt, isNotNull);
      expect((await db.fileById(still))!.trashedAt, isNull);
      final ledger = await db.takeoutLedger();
      expect(ledger.values.every((row) => row.state == TakeoutItemState.inDrive && row.fileId == still), isTrue);
      final after = await settle((s) => s.progress?.extraMotion == 0 && s.phase == TakeoutPhase.idle);
      expect(after.progress!.extraMotion, 0);
    });
  });

  test('a photo deleted from the drive after it was imported is found missing, and goes again', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.start();
    await settle();
    final first = manifest('IMG_1.jpg');
    await db.removeMessages([for (final part in await db.partsOf(first.id)) part.messageId]);
    telegram.captions.clear();

    import.schedule(immediate: true);
    final found = await settle((s) => s.progress?.missing == 1 && s.phase == TakeoutPhase.idle);
    expect(found.progress!.missing, 1);
    await import.importMissingAgain();
    await import.start();
    await settle((s) => s.progress?.missing == 0 && s.progress!.finished && !s.working);
    expect(telegram.captions.keys, ['IMG_1.jpg']);
  });

  test('a part added later is read, and its photos go up too', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.start();
    await settle();

    files.picks = [
      await (ZipBuilder()
            ..add('$_photos/Photos from 2021/IMG_4.jpg', _bytes(4, 3000))
            ..addJson('$_photos/Photos from 2021/IMG_4.jpg.supplemental-metadata.json', _details('IMG_4.jpg', may)))
          .write(p.join(dir.path, 'takeout-20261005T101010Z-004.zip')),
    ];
    expect(await import.addParts(), 1);
    // The first import is done, so the new part waits to be started.
    final read = await settle((s) => s.progress?.total == 4 && s.phase == TakeoutPhase.idle);
    expect(read.running, isFalse);
    expect(read.progress!.left, 1);
    expect(telegram.captions.keys, isNot(contains('IMG_4.jpg')));
    await import.start();
    final state = await settle((s) => s.progress?.total == 4 && s.progress!.finished && !s.working);
    expect(state.progress!.sent, 4);
    expect(telegram.captions.keys, contains('IMG_4.jpg'));
    expect(await db.takeoutPartList(), hasLength(3));
  });

  test('a part whose download didn\'t finish is marked, and the rest still goes', () async {
    await export();
    final cut = File(p.join(dir.path, 'takeout-20261005T101010Z-003.zip'));
    final whole = (ZipBuilder()..add('$_photos/Photos from 2021/IMG_9.jpg', _bytes(9, 3000))).build();
    cut.writeAsBytesSync(whole.sublist(0, whole.length - 40));
    files.picks = [...files.picks, cut];
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.start();
    await settle();

    final parts = {for (final part in await db.takeoutPartList()) part.name: part};
    expect(parts['takeout-20261005T101010Z-003.zip']!.problem, TakeoutPartProblem.incomplete);
    expect(telegram.captions, hasLength(3));
  });

  test('pausing stops the import, and it remembers so after a restart', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.start();
    expect(container.read(preferencesProvider).takeoutRunning, isTrue);
    await import.pause();
    expect(container.read(takeoutImportProvider).running, isFalse);
    expect(container.read(preferencesProvider).takeoutRunning, isFalse);
  });

  test('starting over forgets the parts and gives back access to them', () async {
    await export();
    await import.addParts();
    await settle((s) => s.progress != null);
    await import.startOver();
    expect(await db.takeoutPartList(), isEmpty);
    expect(await db.takeoutEntryList(), isEmpty);
    expect(files.released, hasLength(2));
  });
}
