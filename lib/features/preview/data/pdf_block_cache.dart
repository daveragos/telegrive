import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Where pdfrx keeps the blocks it has read of PDFs opened by range, one
/// file per URL. They are pieces of the drive's own documents.
///
/// pdfrx's cache directory is set here to the app's temporary directory,
/// the one pdfrx picks for itself, so the place is known without starting
/// the PDF engine, which measuring or clearing the blocks has no use for.
Future<Directory> pdfBlockCache() async {
  Pdfrx.cacheDirectoryPath ??= (await getTemporaryDirectory()).path;
  return Directory(p.join(Pdfrx.cacheDirectoryPath!, 'pdfrx.cache'));
}

/// Deletes [pdfBlockCache]. Blocks that can't be deleted now stay behind
/// rather than stopping whatever is clearing them.
Future<void> deletePdfBlockCache() async {
  try {
    final blocks = await pdfBlockCache();
    if (await blocks.exists()) await blocks.delete(recursive: true);
  } catch (e) {
    debugPrint('[PDF] Could not delete the block cache: $e');
  }
}

/// How many bytes of PDFs [pdfBlockCache] holds.
///
/// Each of its files is as long as the whole PDF, with only the blocks that
/// were read written into it, so its length would count pages never
/// fetched. The map of blocks at the head of the file says which arrived.
Future<int> pdfBlockCacheBytes() async {
  final blocks = await pdfBlockCache();
  if (!await blocks.exists()) return 0;
  var total = 0;
  await for (final entry in blocks.list(recursive: true, followLinks: false)) {
    if (entry is! File) continue;
    try {
      total += await _heldBytes(entry);
    } on FileSystemException {
      // Deleted by the reader while being measured: nothing held.
    }
  }
  return total;
}

/// pdfrx's layout: four 32-bit numbers (a marker, the PDF's size, the block
/// size, and the length of the HTTP headers kept), room for those headers,
/// then one bit per block, set once it has arrived. A file laid out any
/// other way counts at its length.
Future<int> _heldBytes(File file) async {
  const marker = 34567;
  const head = 16;
  const keptHeaders = 128;
  final raf = await file.open();
  try {
    final length = await raf.length();
    final numbers = ByteData.sublistView(await raf.read(head));
    if (numbers.lengthInBytes < head || numbers.getInt32(0, Endian.host) != marker) {
      return length;
    }
    final size = numbers.getInt32(4, Endian.host);
    final block = numbers.getInt32(8, Endian.host);
    if (size <= 0 || block <= 0) return length;
    final count = (size + block - 1) ~/ block;
    await raf.setPosition(head + keptHeaders);
    var arrived = 0;
    for (final byte in await raf.read((count + 7) >> 3)) {
      for (var bits = byte; bits != 0; bits &= bits - 1) {
        arrived++;
      }
    }
    return math.min(arrived * block, size);
  } finally {
    await raf.close();
  }
}
