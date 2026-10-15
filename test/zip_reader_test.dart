import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/zip_file_source.dart';
import 'package:telegrive/core/files/zip_reader.dart';

import 'support/zip_builder.dart';

Uint8List _noise(int length, {int seed = 1}) {
  final random = Random(seed);
  return Uint8List.fromList([for (var i = 0; i < length; i++) random.nextInt(256)]);
}

ZipBuilder _sample() => ZipBuilder()
  ..add('Takeout/Google Photos/Photos from 2019/IMG_0001.jpg', _noise(70000), deflate: false)
  ..addText('Takeout/Google Photos/Photos from 2019/IMG_0001.jpg.supplemental-metadata.json', '{"title":"IMG_0001.jpg"}')
  ..add('Takeout/Google Photos/Trip/ፎቶ.jpg', _noise(5000, seed: 2));

void main() {
  test('Crc32 matches the standard check value', () {
    expect(Crc32.of(ascii.encode('123456789')), 0xCBF43926);
    final split = Crc32()
      ..add(ascii.encode('1234'))
      ..add(ascii.encode('56789'));
    expect(split.value, 0xCBF43926);
  });

  for (final zip64 in [false, true]) {
    group(zip64 ? 'a Zip64 archive' : 'an archive', () {
      late MemoryZipSource source;
      setUp(() => source = MemoryZipSource(_sample().build(zip64: zip64)));

      test('lists its files with their folders, names and sizes', () async {
        final entries = await ZipReader.entries(source);
        expect([for (final e in entries) e.path], [
          'Takeout/Google Photos/Photos from 2019/IMG_0001.jpg',
          'Takeout/Google Photos/Photos from 2019/IMG_0001.jpg.supplemental-metadata.json',
          'Takeout/Google Photos/Trip/ፎቶ.jpg',
        ]);
        expect(entries.first.name, 'IMG_0001.jpg');
        expect(entries.first.folder, 'Takeout/Google Photos/Photos from 2019');
        expect(entries.first.size, 70000);
        expect(entries.first.method, ZipEntry.stored);
        expect(entries[1].method, ZipEntry.deflated);
        expect(entries.every((e) => e.readable), isTrue);
      });

      test('reads small files straight from where they sit', () async {
        final entries = await ZipReader.entries(source);
        final [json] = await ZipReader.contents(source, [entries[1]]);
        expect(utf8.decode(json), '{"title":"IMG_0001.jpg"}');
      });

      test('extracts a file whole', () async {
        final dir = await Directory.systemTemp.createTemp('zip');
        addTearDown(() => dir.delete(recursive: true));
        final entries = await ZipReader.entries(source);
        final offsets = await ZipReader.dataOffsets(source, entries);
        final target = '${dir.path}/out.jpg';
        await source.extract(entries[2], offsets[2], target);
        expect(await File(target).readAsBytes(), _noise(5000, seed: 2));
      });
    });
  }

  test('an end record followed by a comment is still found', () async {
    final source = MemoryZipSource(_sample().build(comment: 'Exported by Google'));
    expect(await ZipReader.entries(source), hasLength(3));
  });

  test('many small files are read in a few calls', () async {
    final builder = ZipBuilder();
    for (var i = 0; i < 600; i++) {
      builder.addJson('Takeout/Google Photos/Photos from 2020/IMG_$i.jpg.json', {'title': 'IMG_$i.jpg'});
    }
    final source = MemoryZipSource(builder.build());
    final entries = await ZipReader.entries(source);
    source.calls = 0;
    final contents = await ZipReader.contents(source, entries);
    expect(contents, hasLength(600));
    expect(jsonDecode(utf8.decode(contents[599])), {'title': 'IMG_599.jpg'});
    // Local headers and then data, 256 at a time.
    expect(source.calls, 6);
  });

  group('problems', () {
    test('a download cut short is told apart from a file that isn\'t a zip', () async {
      final whole = _sample().build();
      final cut = MemoryZipSource(whole.sublist(0, whole.length ~/ 2));
      await expectLater(
        ZipReader.entries(cut),
        throwsA(isA<ZipFormatException>().having((e) => e.problem, 'problem', ZipProblem.incomplete)),
      );
      final text = MemoryZipSource(Uint8List.fromList(utf8.encode('Not an archive, just some text here.')));
      await expectLater(
        ZipReader.entries(text),
        throwsA(isA<ZipFormatException>().having((e) => e.problem, 'problem', ZipProblem.notZip)),
      );
      await expectLater(
        ZipReader.entries(MemoryZipSource(Uint8List(0))),
        throwsA(isA<ZipFormatException>().having((e) => e.problem, 'problem', ZipProblem.notZip)),
      );
    });

    test('a damaged file fails its checksum', () async {
      final bytes = (ZipBuilder()..add('a.txt', utf8.encode('hello world'), deflate: false)).build();
      // The data starts after the 30-byte header and the 5-byte name.
      bytes[35] ^= 0xFF;
      final source = MemoryZipSource(bytes);
      final entries = await ZipReader.entries(source);
      await expectLater(
        ZipReader.contents(source, entries),
        throwsA(isA<ZipFormatException>().having((e) => e.problem, 'problem', ZipProblem.damaged)),
      );
    });
  });

  group('ZipFileSource', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('zip'));
    tearDown(() => dir.delete(recursive: true));

    test('reads and extracts from a file on disk', () async {
      final big = _noise(3 << 20, seed: 7);
      final archive = await (ZipBuilder()
            ..add('Takeout/Google Photos/Photos from 2021/VID_0001.mp4', big)
            ..add('Takeout/Google Photos/Photos from 2021/IMG_0002.jpg', _noise(100), deflate: false))
          .write('${dir.path}/takeout-001.zip', zip64: true);
      final source = await ZipFileSource.open(archive.path);
      final entries = await ZipReader.entries(source);
      final offsets = await ZipReader.dataOffsets(source, entries);
      final target = '${dir.path}/VID_0001.mp4';
      await source.extract(entries.first, offsets.first, target);
      expect(await File(target).readAsBytes(), big);
      expect(File('$target.part').existsSync(), isFalse);
    });

    test('leaves nothing behind when a file is damaged', () async {
      final bytes = (ZipBuilder()..add('a.bin', _noise(4000), deflate: false)).build();
      bytes[100] ^= 0xFF;
      final archive = await File('${dir.path}/broken.zip').writeAsBytes(bytes);
      final source = await ZipFileSource.open(archive.path);
      final entries = await ZipReader.entries(source);
      final offsets = await ZipReader.dataOffsets(source, entries);
      final target = '${dir.path}/a.bin';
      await expectLater(
        source.extract(entries.single, offsets.single, target),
        throwsA(isA<ZipFormatException>().having((e) => e.problem, 'problem', ZipProblem.damaged)),
      );
      expect(File(target).existsSync(), isFalse);
      expect(File('$target.part').existsSync(), isFalse);
    });
  });
}
