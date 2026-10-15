import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/zip_reader.dart';
import 'package:telegrive/features/takeout/domain/takeout_catalog.dart';

const _year = 'Takeout/Google Photos/Photos from 2019';
const _trip = 'Takeout/Google Photos/Trip to Lalibela';

var _offset = 0;

/// A photo or video in part [part], whose bytes are told apart by [crc].
TakeoutMedia _media(String path, {int size = 1000, int? crc, String part = 'p1'}) => TakeoutMedia(
  part,
  ZipEntry(
    path: path,
    method: ZipEntry.stored,
    crc: crc ?? path.hashCode & 0xFFFFFFFF,
    compressedSize: size,
    size: size,
    headerOffset: _offset += 100,
  ),
);

/// The JSON name Takeout gives the details of [name]: the name, then
/// `.supplemental-metadata`, cut to 46 characters, then the counter.
String _jsonName(String name, {int counter = 0, bool supplemental = true}) {
  final full = supplemental ? '$name.supplemental-metadata' : name;
  final stem = full.length > 46 ? full.substring(0, 46) : full;
  return '$stem${counter > 0 ? '($counter)' : ''}.json';
}

TakeoutSidecar _sidecar(
  String folder,
  String name, {
  String? title,
  DateTime? taken,
  bool favorited = false,
  int counter = 0,
  bool supplemental = true,
}) => TakeoutSidecar(
  folder: folder,
  fileName: _jsonName(name, counter: counter, supplemental: supplemental),
  title: title ?? name,
  takenAt: taken ?? DateTime(2019, 6, 15, 14, 25),
  favorited: favorited,
);

TakeoutCatalog _catalog(
  List<TakeoutMedia> media,
  List<TakeoutSidecar> sidecars, {
  List<TakeoutAlbum> albums = const [],
  List<String> parts = const ['p1', 'p2'],
}) => buildTakeoutCatalog(media: media, sidecars: sidecars, albums: albums, partOrder: parts);

TakeoutItem _only(TakeoutCatalog catalog, String name) => catalog.items.singleWhere((i) => i.name == name);

void main() {
  group('parseTakeoutJson', () {
    List<int> bytes(Object json) => utf8.encode(jsonEncode(json));

    test('reads a photo\'s details', () {
      final parsed = parseTakeoutJson(
        '$_year/IMG_1.jpg.supplemental-metadata.json',
        bytes({
          'title': 'IMG_1.jpg',
          'creationTime': {'timestamp': '1600000000'},
          'photoTakenTime': {'timestamp': '1560601530', 'formatted': 'Jun 15, 2019'},
          'geoData': {'latitude': 9.03, 'longitude': 38.74},
          'favorited': true,
        }),
      );
      expect(parsed, isA<TakeoutSidecar>());
      final sidecar = parsed! as TakeoutSidecar;
      expect(sidecar.folder, _year);
      expect(sidecar.fileName, 'IMG_1.jpg.supplemental-metadata.json');
      expect(sidecar.title, 'IMG_1.jpg');
      expect(sidecar.takenAt, DateTime.fromMillisecondsSinceEpoch(1560601530 * 1000));
      expect(sidecar.favorited, isTrue);
    });

    test('falls back to when it was uploaded, and leaves out a zero time', () {
      final uploaded = parseTakeoutJson(
        '$_year/a.jpg.json',
        bytes({
          'title': 'a.jpg',
          'creationTime': {'timestamp': '1600000000'},
          'photoTakenTime': {'timestamp': '0'},
        }),
      )! as TakeoutSidecar;
      expect(uploaded.takenAt, DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000));
      final none = parseTakeoutJson(
        '$_year/b.jpg.json',
        bytes({
          'title': 'b.jpg',
          'photoTakenTime': {'timestamp': '0'},
        }),
      )! as TakeoutSidecar;
      expect(none.takenAt, isNull);
    });

    test('reads an album\'s title from its metadata, in either layout', () {
      final album = parseTakeoutJson(
        '$_trip/metadata.json',
        bytes({
          'title': 'Trip to Lalibela',
          'description': '',
          'access': 'protected',
          'date': {'timestamp': '1560601530'},
        }),
      );
      expect(album, isA<TakeoutAlbum>().having((a) => a.title, 'title', 'Trip to Lalibela'));
      expect((album! as TakeoutAlbum).folder, _trip);
      final older = parseTakeoutJson(
        '$_trip/metadaten.json',
        bytes({
          'albumData': {'title': 'Ausflug', 'date': {'timestamp': '1'}},
        }),
      );
      expect(older, isA<TakeoutAlbum>().having((a) => a.title, 'title', 'Ausflug'));
    });

    test('anything else is passed over', () {
      expect(parseTakeoutJson('Takeout/Google Photos/print-subscriptions.json', bytes([])), isNull);
      expect(parseTakeoutJson('Takeout/Google Photos/shared_album_comments.json', bytes({'comments': []})), isNull);
      expect(parseTakeoutJson('x.json', utf8.encode('not json')), isNull);
    });
  });

  group('matching each file with its details', () {
    test('by the plain and the supplemental names', () {
      final catalog = _catalog(
        [_media('$_year/IMG_1.jpg'), _media('$_year/IMG_2.jpg')],
        [
          _sidecar(_year, 'IMG_1.jpg', supplemental: false, taken: DateTime(2019, 1, 1)),
          _sidecar(_year, 'IMG_2.jpg', taken: DateTime(2019, 2, 2), favorited: true),
        ],
      );
      expect(_only(catalog, 'IMG_1.jpg').takenAt, DateTime(2019, 1, 1));
      expect(_only(catalog, 'IMG_1.jpg').starred, isFalse);
      expect(_only(catalog, 'IMG_2.jpg').takenAt, DateTime(2019, 2, 2));
      expect(_only(catalog, 'IMG_2.jpg').starred, isTrue);
      expect(catalog.items.every((i) => i.described), isTrue);
    });

    test('whatever length Takeout cut the JSON\'s name to', () {
      for (var length = 30; length <= 70; length++) {
        final name = '${'x' * (length - 4)}.jpg';
        for (final supplemental in [true, false]) {
          final catalog = _catalog(
            [_media('$_year/$name')],
            [_sidecar(_year, name, supplemental: supplemental, taken: DateTime(2020, 3, 3))],
          );
          expect(catalog.items.single.described, isTrue, reason: '$length characters, supplemental $supplemental');
          expect(catalog.items.single.takenAt, DateTime(2020, 3, 3));
        }
      }
    });

    test('two files that shared a name keep their own details', () {
      final catalog = _catalog(
        [_media('$_year/IMG_0001.jpg'), _media('$_year/IMG_0001(1).jpg')],
        [
          _sidecar(_year, 'IMG_0001.jpg', taken: DateTime(2019, 1, 1)),
          _sidecar(_year, 'IMG_0001.jpg', counter: 1, taken: DateTime(2019, 5, 5)),
        ],
      );
      expect(_only(catalog, 'IMG_0001.jpg').takenAt, DateTime(2019, 1, 1));
      expect(_only(catalog, 'IMG_0001(1).jpg').takenAt, DateTime(2019, 5, 5));
    });

    test('a name that really has a number in brackets matches as it is', () {
      final catalog = _catalog(
        [_media('$_year/Party (1).jpg')],
        [_sidecar(_year, 'Party (1).jpg', taken: DateTime(2018, 8, 8))],
      );
      expect(catalog.items.single.takenAt, DateTime(2018, 8, 8));
    });

    test('an edited copy goes by its original\'s details', () {
      final catalog = _catalog(
        [_media('$_year/IMG_2.jpg'), _media('$_year/IMG_2-edited.jpg'), _media('$_year/IMG_3-bearbeitet.jpg')],
        [
          _sidecar(_year, 'IMG_2.jpg', taken: DateTime(2019, 2, 2), favorited: true),
          _sidecar(_year, 'IMG_3.jpg', taken: DateTime(2019, 3, 3)),
        ],
      );
      expect(_only(catalog, 'IMG_2-edited.jpg').takenAt, DateTime(2019, 2, 2));
      expect(_only(catalog, 'IMG_2-edited.jpg').starred, isTrue);
      expect(_only(catalog, 'IMG_3-bearbeitet.jpg').takenAt, DateTime(2019, 3, 3));
      expect(catalog.items, hasLength(3));
    });

    test('the video of a Live Photo goes by the photo\'s details', () {
      final catalog = _catalog(
        [_media('$_year/IMG_4.HEIC'), _media('$_year/IMG_4.MP4')],
        [_sidecar(_year, 'IMG_4.HEIC', taken: DateTime(2019, 4, 4), favorited: true)],
      );
      expect(_only(catalog, 'IMG_4.MP4').takenAt, DateTime(2019, 4, 4));
      expect(_only(catalog, 'IMG_4.MP4').described, isTrue);
      // The star is the photo's.
      expect(_only(catalog, 'IMG_4.MP4').starred, isFalse);
      expect(_only(catalog, 'IMG_4.HEIC').starred, isTrue);
    });

    test('a name Takeout shortened goes back to the name it had', () {
      const title = 'Family dinner at grandmother house on new year eve.jpg';
      const cut = 'Family dinner at grandmother house on new.jpg';
      final catalog = _catalog(
        [_media('$_year/$cut')],
        [
          TakeoutSidecar(
            folder: _year,
            fileName: _jsonName(title),
            title: title,
            takenAt: DateTime(2017, 1, 1),
          ),
        ],
      );
      expect(catalog.items.single.name, title);
      expect(catalog.items.single.takenAt, DateTime(2017, 1, 1));
    });

    test('without details, the date comes from the name, and the file goes last', () {
      final catalog = _catalog(
        [_media('$_year/IMG_20190615_142530.jpg'), _media('$_year/IMG_1.jpg')],
        [_sidecar(_year, 'IMG_1.jpg')],
      );
      expect(catalog.items.map((i) => i.name), ['IMG_1.jpg', 'IMG_20190615_142530.jpg']);
      expect(catalog.items.last.described, isFalse);
      expect(catalog.items.last.takenAt, DateTime(2019, 6, 15, 14, 25, 30));
    });

    test('details only look in their own folder', () {
      final catalog = _catalog(
        [_media('$_trip/IMG_1.jpg')],
        [_sidecar(_year, 'IMG_1.jpg')],
      );
      expect(catalog.items.single.described, isFalse);
    });
  });

  group('copies of one file', () {
    test('are one item, in every album whose folder holds it', () {
      final catalog = _catalog(
        [
          _media('$_year/IMG_5.jpg', crc: 5, size: 500),
          _media('$_trip/IMG_5.jpg', crc: 5, size: 500, part: 'p2'),
          _media('Takeout/Google Photos/Family/IMG_5.jpg', crc: 5, size: 500, part: 'p2'),
        ],
        [_sidecar(_year, 'IMG_5.jpg'), _sidecar(_trip, 'IMG_5.jpg')],
        albums: [
          const TakeoutAlbum(folder: _trip, title: 'Trip to Lalibela'),
          const TakeoutAlbum(folder: 'Takeout/Google Photos/Family', title: 'Family'),
        ],
      );
      final item = catalog.items.single;
      expect(item.albums, ['Family', 'Trip to Lalibela']);
      expect(item.sources, hasLength(3));
      expect(item.sources.first.part, 'p1');
      expect(catalog.albums, {'Family', 'Trip to Lalibela'});
    });

    test('go by the name the year\'s folder gives, not an album\'s counter', () {
      final catalog = _catalog(
        [
          _media('$_trip/IMG_6(1).jpg', crc: 6),
          _media('$_year/IMG_6.jpg', crc: 6, part: 'p2'),
        ],
        [_sidecar(_year, 'IMG_6.jpg')],
        albums: [const TakeoutAlbum(folder: _trip, title: 'Trip')],
      );
      expect(catalog.items.single.name, 'IMG_6.jpg');
      expect(catalog.items.single.albums, ['Trip']);
      // Read from the earliest part all the same.
      expect(catalog.items.single.sources.first.part, 'p1');
    });
  });

  group('Live Photos', () {
    test('a video beside a photo of the same name is its moving part', () {
      final catalog = _catalog(
        [
          _media('$_year/20230612_183344.jpg'),
          _media('$_year/20230612_183344.mp4'),
          _media('$_year/IMG_8.HEIC'),
          _media('$_year/IMG_8.MOV'),
          _media('$_year/IMG_9(1).jpg'),
          _media('$_year/IMG_9(1).MP4'),
          _media('$_year/VID_1.mp4'),
          _media('$_trip/20230612_183344.mp4', crc: 77),
        ],
        [],
      );
      TakeoutItem item(String name) => catalog.items.firstWhere((i) => i.name == name);
      expect(item('20230612_183344.mp4').motionOf, item('20230612_183344.jpg').key);
      expect(item('IMG_8.MOV').motionOf, item('IMG_8.HEIC').key);
      expect(item('IMG_9(1).MP4').motionOf, item('IMG_9(1).jpg').key);
      // A video alone, or beside no photo in its own folder, is a video.
      expect(item('VID_1.mp4').motionOf, isNull);
      expect(catalog.items.where((i) => i.name == '20230612_183344.mp4' && i.motionOf == null), hasLength(1));
      expect(item('20230612_183344.jpg').motionOf, isNull);
    });
  });

  test('other products in the same export are left out', () {
    final catalog = _catalog(
      [_media('$_year/IMG_1.jpg'), _media('Takeout/Drive/scan.jpg')],
      [_sidecar(_year, 'IMG_1.jpg')],
    );
    expect(catalog.items.map((i) => i.name), ['IMG_1.jpg']);
  });

  test('a zip without any details is taken whole', () {
    final catalog = _catalog([_media('Photos/2016/a.jpg'), _media('b.mp4')], []);
    expect(catalog.items, hasLength(2));
    expect(catalog.photos, 1);
    expect(catalog.videos, 1);
    expect(catalog.bytes, 2000);
  });

  test('items go part by part, as each part lays them out', () {
    final catalog = _catalog(
      [
        _media('$_year/c.jpg', part: 'p2'),
        _media('$_year/a.jpg', part: 'p1'),
        _media('$_year/b.jpg', part: 'p1'),
      ],
      [_sidecar(_year, 'a.jpg'), _sidecar(_year, 'b.jpg'), _sidecar(_year, 'c.jpg')],
    );
    expect(catalog.items.map((i) => i.name), ['a.jpg', 'b.jpg', 'c.jpg']);
  });

  group('takeoutKeeps', () {
    ZipEntry entry(String path, {int size = 10, int method = ZipEntry.deflated}) =>
        ZipEntry(path: path, method: method, crc: 0, compressedSize: size, size: size, headerOffset: 0);

    test('keeps photos, videos and small JSON', () {
      expect(takeoutKeeps(entry('$_year/IMG_1.jpg')), isTrue);
      expect(takeoutKeeps(entry('$_year/IMG_1.HEIC')), isTrue);
      expect(takeoutKeeps(entry('$_year/VID_1.mp4')), isTrue);
      expect(takeoutKeeps(entry('$_year/IMG_1.jpg.json')), isTrue);
    });

    test('leaves out everything else', () {
      expect(takeoutKeeps(entry('Takeout/archive_browser.html')), isFalse);
      expect(takeoutKeeps(entry('$_year/.nomedia')), isFalse);
      expect(takeoutKeeps(entry('$_year/empty.jpg', size: 0)), isFalse);
      expect(takeoutKeeps(entry('$_year/big.json', size: 1 << 20)), isFalse);
      expect(takeoutKeeps(entry('$_year/odd.jpg', method: 12)), isFalse);
    });
  });

  group('takenFromName', () {
    test('reads the names cameras and apps give', () {
      expect(takenFromName('IMG_20190615_142530.jpg'), DateTime(2019, 6, 15, 14, 25, 30));
      expect(takenFromName('PXL_20230101_123456789.jpg'), DateTime(2023, 1, 1, 12, 34, 56));
      expect(takenFromName('VID_20200229_235959.mp4'), DateTime(2020, 2, 29, 23, 59, 59));
      expect(takenFromName('Screenshot_2019-06-15-14-25-30-123_com.app.jpg'), DateTime(2019, 6, 15, 14, 25, 30));
      expect(takenFromName('2018-12-31 23.59.58.jpg'), DateTime(2018, 12, 31, 23, 59, 58));
      expect(takenFromName('IMG-20190615-WA0001.jpg'), DateTime(2019, 6, 15));
    });

    test('a name without a real date has none', () {
      expect(takenFromName('IMG_0001.jpg'), isNull);
      expect(takenFromName('IMG_20190631_120000.jpg'), isNull);
      expect(takenFromName('IMG_20191315_120000.jpg'), isNull);
      expect(takenFromName('1234567890123456.jpg'), isNull);
    });
  });

  group('parts', () {
    test('are numbered from the names Takeout gives them', () {
      expect(takeoutPartNumber('takeout-20261005T101010Z-001.zip'), (export: '20261005T101010Z', number: 1));
      expect(takeoutPartNumber('takeout-20261005T101010Z-012 (1).zip'), (export: '20261005T101010Z', number: 12));
      expect(takeoutPartNumber('takeout-20261005T101010Z-3-002.zip'), (export: '20261005T101010Z-3', number: 2));
      expect(takeoutPartNumber('photos.zip'), isNull);
    });

    test('say when their export was made', () {
      expect(takeoutExportTime('20261005T101010Z'), DateTime.utc(2026, 10, 5, 10, 10, 10));
      expect(takeoutExportTime('20261005T101010Z-3'), DateTime.utc(2026, 10, 5, 10, 10, 10));
      expect(takeoutExportTime('nonsense'), isNull);
    });

    test('gaps up to the highest part are missing', () {
      expect(
        missingTakeoutParts([
          'takeout-20261005T101010Z-001.zip',
          'takeout-20261005T101010Z-004.zip',
          'takeout-20261005T101010Z-002.zip',
          'photos.zip',
        ]),
        [3],
      );
      expect(missingTakeoutParts(['takeout-20261005T101010Z-001.zip']), isEmpty);
    });

    test('go in order of their numbers, with other names after', () {
      final names = [
        'photos.zip',
        'takeout-20261005T101010Z-010.zip',
        'takeout-20261005T101010Z-002.zip',
      ]..sort(compareTakeoutParts);
      expect(names, ['takeout-20261005T101010Z-002.zip', 'takeout-20261005T101010Z-010.zip', 'photos.zip']);
    });
  });
}
