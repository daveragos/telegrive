import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telegrive/features/preview/data/pdf_block_cache.dart';

const _mib = 1 << 20;

/// A file laid out the way pdfrx keeps a PDF read by range: its size and
/// block size up front, then a bit for each block that arrived, then the
/// blocks at their places, as long as the whole PDF.
void _writeBlocks(File file, {required int size, required List<int> arrived}) {
  const block = _mib;
  final count = (size + block - 1) ~/ block;
  final map = Uint8List((count + 7) >> 3);
  for (final index in arrived) {
    map[index >> 3] |= 1 << (index & 7);
  }
  final head = Int32List.fromList([34567, size, block, 0]).buffer.asUint8List();
  final raf = file.openSync(mode: FileMode.write)
    ..writeFromSync(head)
    ..setPositionSync(16 + 128)
    ..writeFromSync(map);
  final start = 16 + 128 + map.length;
  raf
    ..truncateSync(start + size)
    ..closeSync();
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pdf_block_cache_test');
    Pdfrx.cacheDirectoryPath = temp.path;
  });

  tearDown(() {
    Pdfrx.cacheDirectoryPath = null;
    temp.deleteSync(recursive: true);
  });

  test('counts the pages that arrived, not the length of the whole PDF', () async {
    final blocks = await pdfBlockCache();
    expect(blocks.path, '${temp.path}/pdfrx.cache');
    expect(await pdfBlockCacheBytes(), 0);

    final scan = File('${blocks.path}/ab/cd/scan.pdf')..createSync(recursive: true);
    _writeBlocks(scan, size: 80 * _mib, arrived: [0, 79]);
    final contract = File('${blocks.path}/ef/01/contract.pdf')..createSync(recursive: true);
    _writeBlocks(contract, size: 3 * _mib, arrived: [0, 1, 2]);
    // Anything else there counts at its length.
    File('${blocks.path}/stray')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(100, 1));

    expect(scan.lengthSync(), greaterThan(80 * _mib));
    expect(await pdfBlockCacheBytes(), 2 * _mib + 3 * _mib + 100);
  });

  test('deleting takes every block', () async {
    final blocks = await pdfBlockCache();
    final scan = File('${blocks.path}/ab/cd/scan.pdf')..createSync(recursive: true);
    _writeBlocks(scan, size: 2 * _mib, arrived: [0]);

    await deletePdfBlockCache();
    expect(blocks.existsSync(), isFalse);
    expect(await pdfBlockCacheBytes(), 0);
    // Nothing there is nothing to delete.
    await deletePdfBlockCache();
  });
}
