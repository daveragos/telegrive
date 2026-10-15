import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/zip_reader.dart';
import 'package:telegrive/features/takeout/data/takeout_import.dart';
import 'package:telegrive/features/takeout/domain/takeout_catalog.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';

const _year = 'Takeout/Google Photos/Photos from 2019';
final _now = DateTime(2026, 10, 8, 12);

var _crc = 0;

TakeoutMedia _media(String name, {String part = 'p1', int size = 1000, int? crc}) => TakeoutMedia(
  part,
  ZipEntry(
    path: '$_year/$name',
    method: ZipEntry.stored,
    crc: crc ?? ++_crc,
    compressedSize: size,
    size: size,
    headerOffset: _crc * 100,
  ),
);

TakeoutCatalog _catalog(List<TakeoutMedia> media) => buildTakeoutCatalog(
  media: media,
  sidecars: [
    for (final m in media)
      TakeoutSidecar(folder: _year, fileName: '${m.entry.name}.json', title: m.entry.name, takenAt: _now),
  ],
  albums: const [],
  partOrder: const ['p1', 'p2'],
);

TakeoutItemRow _row(
  TakeoutItem item,
  TakeoutItemState state, {
  int failures = 0,
  String? transferId,
}) => TakeoutItemRow(
  key: item.key,
  state: state,
  failures: failures,
  transferId: transferId,
  updatedAt: _now,
);

void main() {
  test('everything goes when nothing is settled yet', () {
    final catalog = _catalog([_media('a.jpg'), _media('b.mp4', size: 3000)]);
    final plan = planTakeout(catalog: catalog, ledger: const {}, fingerprints: const {});
    expect(plan.toSend.map((i) => i.name), ['a.jpg', 'b.mp4']);
    expect(plan.progress.total, 2);
    expect(plan.progress.photos, 1);
    expect(plan.progress.videos, 1);
    expect(plan.progress.left, 2);
    expect(plan.progress.leftBytes, 4000);
    expect(plan.progress.finished, isFalse);
  });

  test('what is settled is passed over and counted', () {
    final catalog = _catalog([
      _media('done.jpg'),
      _media('there.jpg'),
      _media('skipped.jpg'),
      _media('gave-up.jpg'),
      _media('try-again.jpg'),
    ]);
    final [done, there, skipped, gaveUp, tryAgain] = catalog.items;
    final plan = planTakeout(
      catalog: catalog,
      ledger: {
        done.key: _row(done, TakeoutItemState.done),
        there.key: _row(there, TakeoutItemState.inDrive),
        skipped.key: _row(skipped, TakeoutItemState.skipped),
        gaveUp.key: _row(gaveUp, TakeoutItemState.failed, failures: takeoutMaxFailures),
        tryAgain.key: _row(tryAgain, TakeoutItemState.failed, failures: 1),
      },
      fingerprints: const {},
    );
    expect(plan.toSend.map((i) => i.name), ['try-again.jpg']);
    final progress = plan.progress;
    expect((progress.sent, progress.inDrive, progress.skipped, progress.failed), (1, 1, 1, 1));
    expect(progress.left, 1);
  });

  test('a file the drive holds under its name and size is counted as already there', () {
    final catalog = _catalog([_media('a.jpg'), _media('b.jpg', size: 2000)]);
    final plan = planTakeout(catalog: catalog, ledger: const {}, fingerprints: const {'a.jpg|1000': 'file-a'});
    // Still listed, so it can be put in its albums and starred.
    expect(plan.toSend, hasLength(2));
    expect(plan.progress.alreadyThere, 1);
    expect(plan.progress.leftBytes, 2000);
  });

  test('a photo is known in the drive by name and size, name and time, or size and time', () {
    final catalog = _catalog([
      _media('smaller.jpg', size: 1000),
      _media('renamed.jpg', size: 2000),
      _media('same.jpg', size: 3000),
      _media('other.jpg', size: 4000),
    ]);
    Map<String, String> drive(List<(String, int, DateTime?)> files) => {
      for (final (name, size, taken) in files)
        for (final key in takeoutMatchKeys(name, size, taken)) key: 'file-$name',
    };
    final fingerprints = drive([
      // Kept smaller by Storage saver: same name and moment, fewer bytes.
      ('smaller.jpg', 400, _now),
      // Renamed since: same bytes and moment.
      ('IMG_0042.jpg', 2000, _now.add(const Duration(milliseconds: 300))),
      ('same.jpg', 3000, null),
      // Same name, but another moment and size: another photo.
      ('other.jpg', 3999, _now.add(const Duration(minutes: 1))),
    ]);
    final [smaller, renamed, same, other] = catalog.items;
    expect(takeoutMatch(smaller, fingerprints), 'file-smaller.jpg');
    expect(takeoutMatch(renamed, fingerprints), 'file-IMG_0042.jpg');
    expect(takeoutMatch(same, fingerprints), 'file-same.jpg');
    expect(takeoutMatch(other, fingerprints), isNull);
    final plan = planTakeout(catalog: catalog, ledger: const {}, fingerprints: fingerprints);
    expect(plan.progress.alreadyThere, 3);
    expect(plan.progress.leftBytes, 4000);
  });

  test('a name matches whatever its case, and a time to the second', () {
    final keys = takeoutMatchKeys('IMG_1.JPG', 10, DateTime.fromMillisecondsSinceEpoch(1560601530999));
    expect(keys, contains('name:img_1.jpg|taken:1560601530'));
    expect(keys, contains('size:10|taken:1560601530'));
    expect(takeoutMatchKeys('a.jpg', 10, null), ['a.jpg|10']);
  });

  group('the video of a Live Photo', () {
    final catalog = _catalog([_media('20230612_183344.jpg', size: 500), _media('20230612_183344.mp4', size: 4000)]);
    final [still, video] = catalog.items;
    final items = {for (final item in catalog.items) item.key: item};

    test('is already there when the drive had its photo before the import', () {
      final fingerprints = {for (final key in takeoutMatchKeys(still.name, still.size, still.takenAt)) key: 'phone-copy'};
      expect(video.motionOf, still.key);
      expect(takeoutMotionHome(video, items: items, ledger: const {}, fingerprints: fingerprints), 'phone-copy');
      final plan = planTakeout(catalog: catalog, ledger: const {}, fingerprints: fingerprints);
      expect(plan.progress.alreadyThere, 2);
      expect(plan.progress.leftBytes, 0);
      final settled = {still.key: _row(still, TakeoutItemState.inDrive).copyWith(fileId: const Value('phone-copy'))};
      expect(takeoutMotionHome(video, items: items, ledger: settled, fingerprints: const {}), 'phone-copy');
    });

    test('goes up when the import sends the photo itself, which holds no movement', () {
      final ledger = {still.key: _row(still, TakeoutItemState.done).copyWith(fileId: const Value('from-google'))};
      expect(takeoutMotionHome(video, items: items, ledger: ledger, fingerprints: const {}), isNull);
      final plan = planTakeout(catalog: catalog, ledger: ledger, fingerprints: const {});
      expect(plan.toSend, [video]);
      expect(plan.progress.alreadyThere, 0);
    });

    test('sent beside a photo the drive already had is offered for the trash', () {
      final ledger = {
        still.key: _row(still, TakeoutItemState.inDrive).copyWith(fileId: const Value('phone-copy')),
        video.key: _row(video, TakeoutItemState.done).copyWith(fileId: const Value('extra-video')),
      };
      final plan = planTakeout(catalog: catalog, ledger: ledger, fingerprints: const {});
      expect(plan.extraMotion.single.fileId, 'extra-video');
      expect(plan.extraMotion.single.stillId, 'phone-copy');
      expect(plan.progress.extraMotion, 1);
    });
  });

  test('an item settled whose file left the drive is missing', () {
    final catalog = _catalog([_media('a.jpg'), _media('b.jpg')]);
    final [a, b] = catalog.items;
    final ledger = {
      a.key: _row(a, TakeoutItemState.done).copyWith(fileId: const Value('file-a')),
      b.key: _row(b, TakeoutItemState.inDrive).copyWith(fileId: const Value('file-b')),
    };
    final plan = planTakeout(catalog: catalog, ledger: ledger, fingerprints: const {}, driveFiles: {'file-b'});
    expect(plan.missing, [a.key]);
    expect(plan.progress.missing, 1);
    // Without the whole drive read, nothing is judged missing.
    expect(planTakeout(catalog: catalog, ledger: ledger, fingerprints: const {}).missing, isEmpty);
  });

  test('photos of parts deleted from the phone still count toward how it went', () {
    final catalog = _catalog([_media('still-here.jpg')]);
    final now = DateTime(2026, 10, 9);
    TakeoutItemRow gone(String key, TakeoutItemState state, {int failures = 0}) =>
        TakeoutItemRow(key: key, state: state, failures: failures, fileId: 'f-$key', updatedAt: now);
    final ledger = {
      'gone-1': gone('gone-1', TakeoutItemState.done),
      'gone-2': gone('gone-2', TakeoutItemState.done),
      'gone-3': gone('gone-3', TakeoutItemState.inDrive),
      'gone-4': gone('gone-4', TakeoutItemState.failed, failures: 1),
      'gone-5': gone('gone-5', TakeoutItemState.pending),
    };
    final plan = planTakeout(catalog: catalog, ledger: ledger, fingerprints: const {});
    expect(plan.progress.total, 4);
    expect(plan.progress.sent, 2);
    expect(plan.progress.inDrive, 1);
    // Only the photo still in a part is left to go.
    expect(plan.progress.left, 1);
    expect(plan.toSend.single.name, 'still-here.jpg');

    final allGone = planTakeout(catalog: const TakeoutCatalog([]), ledger: ledger, fingerprints: const {});
    expect(allGone.progress.total, 3);
    expect(allGone.progress.finished, isTrue);
  });

  test('an upload still in the queue is followed, not judged afresh', () {
    final catalog = _catalog([_media('a.jpg')]);
    final item = catalog.items.single;
    final plan = planTakeout(
      catalog: catalog,
      ledger: {item.key: _row(item, TakeoutItemState.pending, transferId: 't1')},
      fingerprints: const {'a.jpg|1000': 'file-a'},
      unreadable: const {'p1'},
    );
    expect(plan.toSend, [item]);
    expect(plan.progress.alreadyThere, 0);
    expect(plan.progress.blocked, 0);
  });

  test('an item only in parts that can\'t be read waits, and one with another copy goes', () {
    final catalog = _catalog([
      _media('a.jpg', part: 'p2', crc: 1),
      _media('b.jpg', part: 'p2', crc: 2),
      _media('b.jpg', part: 'p1', crc: 2),
    ]);
    final plan = planTakeout(
      catalog: catalog,
      ledger: const {},
      fingerprints: const {},
      unreadable: const {'p2'},
    );
    expect(plan.toSend.map((i) => i.name), ['b.jpg']);
    expect(plan.progress.blocked, 1);
    expect(plan.progress.left, 2);
  });

  test('each part counts the items it holds that are still to go', () {
    final catalog = _catalog([
      _media('a.jpg', part: 'p1', crc: 1),
      _media('b.jpg', part: 'p1', crc: 2),
      _media('b.jpg', part: 'p2', crc: 2),
      _media('c.jpg', part: 'p2', crc: 3),
    ]);
    final [a, _, c] = catalog.items;
    final plan = planTakeout(
      catalog: catalog,
      ledger: {
        a.key: _row(a, TakeoutItemState.done),
        c.key: _row(c, TakeoutItemState.inDrive),
      },
      fingerprints: const {},
    );
    expect(plan.progress.partsLeft, {'p1': 1, 'p2': 1});
  });

  test('an import with everything settled is finished', () {
    final catalog = _catalog([_media('a.jpg')]);
    final item = catalog.items.single;
    final plan = planTakeout(
      catalog: catalog,
      ledger: {item.key: _row(item, TakeoutItemState.done)},
      fingerprints: const {},
    );
    expect(plan.progress.finished, isTrue);
    expect(plan.progress.partsLeft, isEmpty);
    expect(const TakeoutProgress().finished, isFalse);
  });

  test('photos go into a folder for their year', () {
    expect(takeoutFolderPath(DateTime(2019, 6, 15)), ['Google Photos', '2019']);
    expect(takeoutFolderPath(null), ['Google Photos']);
  });

  test('the catalog is built from what was read and kept', () {
    final parts = [
      TakeoutPartRow(id: 'p2', uri: 'content://2', name: 'takeout-20261005T101010Z-002.zip', size: 1, addedAt: _now),
      TakeoutPartRow(id: 'p1', uri: 'content://1', name: 'takeout-20261005T101010Z-001.zip', size: 1, addedAt: _now),
    ];
    final catalog = takeoutCatalogOf(
      parts: parts,
      entries: [
        const TakeoutEntryRow(
          partId: 'p2',
          path: '$_year/IMG_2.jpg',
          method: 0,
          crc: 2,
          compressedSize: 10,
          size: 10,
          headerOffset: 0,
        ),
        const TakeoutEntryRow(
          partId: 'p1',
          path: 'Takeout/Google Photos/Trip/IMG_1.jpg',
          method: 0,
          crc: 1,
          compressedSize: 10,
          size: 10,
          headerOffset: 0,
        ),
      ],
      details: [
        TakeoutDetailRow(
          partId: 'p1',
          path: '$_year/IMG_2.jpg.supplemental-metadata.json',
          album: false,
          title: 'IMG_2.jpg',
          takenAt: DateTime(2019, 2, 2),
          favorited: true,
        ),
        TakeoutDetailRow(
          partId: 'p1',
          path: 'Takeout/Google Photos/Trip/IMG_1.jpg.json',
          album: false,
          title: 'IMG_1.jpg',
          takenAt: DateTime(2018, 1, 1),
          favorited: false,
        ),
        const TakeoutDetailRow(
          partId: 'p1',
          path: 'Takeout/Google Photos/Trip/metadata.json',
          album: true,
          title: 'Trip',
          favorited: false,
        ),
      ],
    );
    // Part 001 goes first, though it was added second.
    expect(catalog.items.map((i) => i.name), ['IMG_1.jpg', 'IMG_2.jpg']);
    expect(catalog.items.first.albums, ['Trip']);
    expect(catalog.items.last.takenAt, DateTime(2019, 2, 2));
    expect(catalog.items.last.starred, isTrue);
  });
}
