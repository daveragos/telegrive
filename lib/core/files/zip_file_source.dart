import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'zip_reader.dart';

/// A zip archive that is a file Telegrive can open itself.
class ZipFileSource implements ZipSource {
  /// The archive at [path], [length] bytes long.
  ZipFileSource(this.path, this.length);

  static Future<ZipFileSource> open(String path) async => ZipFileSource(path, await File(path).length());

  final String path;

  @override
  final int length;

  /// How much is read and unpacked at a time.
  static const int _chunk = 1 << 20;

  @override
  Future<List<Uint8List>> read(List<ByteRange> ranges) async {
    final file = await File(path).open();
    try {
      final out = <Uint8List>[];
      for (final range in ranges) {
        await file.setPosition(range.offset);
        out.add(await file.read(math.max(0, math.min(range.length, length - range.offset))));
      }
      return out;
    } finally {
      await file.close();
    }
  }

  @override
  Future<void> extract(ZipEntry entry, int dataOffset, String path) async {
    if (!entry.readable) {
      throw ZipFormatException(ZipProblem.unsupported, '${entry.path} is packed in a way Telegrive can\'t read');
    }
    final partial = File('$path.part');
    final out = partial.openWrite();
    final crc = Crc32();
    var written = 0;
    final unpacked = _Collect((chunk) {
      crc.add(chunk);
      written += chunk.length;
      out.add(chunk);
    });
    final Sink<List<int>> input = entry.method == ZipEntry.deflated
        ? ZLibDecoder(raw: true).startChunkedConversion(unpacked)
        : unpacked;
    final file = await File(this.path).open();
    var closed = false;
    try {
      var at = dataOffset;
      final end = dataOffset + entry.compressedSize;
      while (at < end) {
        await file.setPosition(at);
        final chunk = await file.read(math.min(_chunk, end - at));
        if (chunk.isEmpty) {
          throw ZipFormatException(ZipProblem.incomplete, '${entry.path} is cut short');
        }
        try {
          input.add(chunk);
        } on FormatException {
          throw ZipFormatException(ZipProblem.damaged, '${entry.path} is damaged');
        }
        at += chunk.length;
        await out.flush();
      }
      try {
        input.close();
      } on FormatException {
        throw ZipFormatException(ZipProblem.damaged, '${entry.path} is damaged');
      }
      closed = true;
      await out.close();
      if (written != entry.size || crc.value != entry.crc) {
        throw ZipFormatException(ZipProblem.damaged, '${entry.path} is damaged');
      }
      await partial.rename(path);
    } catch (_) {
      if (!closed) await out.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      await file.close();
    }
  }
}

/// Hands each unpacked chunk to a callback.
class _Collect implements Sink<List<int>> {
  _Collect(this._onChunk);

  final void Function(List<int> chunk) _onChunk;

  @override
  void add(List<int> data) => _onChunk(data);

  @override
  void close() {}
}
