import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// A stretch of bytes in an archive.
typedef ByteRange = ({int offset, int length});

/// Random access to the bytes of a zip archive, wherever it lives: a file
/// Telegrive can open itself, or a document another app holds that Android
/// lends it.
abstract interface class ZipSource {
  /// How many bytes the archive has.
  int get length;

  /// The bytes of each of [ranges], in order. A range that runs past the
  /// end comes back short.
  Future<List<Uint8List>> read(List<ByteRange> ranges);

  /// Writes what [entry] holds, which starts at [dataOffset], to the file at
  /// [path], and throws [ZipFormatException] when it doesn't match the
  /// entry's size and checksum. Nothing is left at [path] when it fails.
  Future<void> extract(ZipEntry entry, int dataOffset, String path);
}

/// Why an archive, or a file in it, can't be read.
enum ZipProblem {
  /// Not a zip archive at all.
  notZip,

  /// The start of a zip archive without its end, as a download cut short
  /// leaves it.
  incomplete,

  /// A file in it doesn't match its checksum, or its list of files doesn't
  /// add up.
  damaged,

  /// Packed or encrypted in a way Telegrive doesn't read.
  unsupported,
}

class ZipFormatException implements Exception {
  const ZipFormatException(this.problem, this.message);

  final ZipProblem problem;
  final String message;

  @override
  String toString() => 'ZipFormatException(${problem.name}): $message';
}

/// One file in a zip archive, as its central directory describes it.
@immutable
class ZipEntry {
  const ZipEntry({
    required this.path,
    required this.method,
    required this.crc,
    required this.compressedSize,
    required this.size,
    required this.headerOffset,
    this.encrypted = false,
  });

  /// Where it sits in the archive, with `/` between folders.
  final String path;

  /// How it is packed: [stored] or [deflated] are the ones read.
  final int method;
  final int crc;
  final int compressedSize;

  /// Its size once unpacked.
  final int size;

  /// Where its local header starts; its data follows that header.
  final int headerOffset;
  final bool encrypted;

  static const int stored = 0;
  static const int deflated = 8;

  /// Its name, without the folders it is in.
  String get name => path.substring(path.lastIndexOf('/') + 1);

  /// The folders it is in, `/`-separated, or empty at the top.
  String get folder {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  bool get readable => !encrypted && (method == stored || method == deflated);

  @override
  bool operator ==(Object other) =>
      other is ZipEntry &&
      other.path == path &&
      other.method == method &&
      other.crc == crc &&
      other.compressedSize == compressedSize &&
      other.size == size &&
      other.headerOffset == headerOffset &&
      other.encrypted == encrypted;

  @override
  int get hashCode => Object.hash(path, method, crc, compressedSize, size, headerOffset, encrypted);

  @override
  String toString() => 'ZipEntry($path, $size bytes)';
}

/// Reads zip archives through a [ZipSource], without unpacking them: the
/// list of files from the central directory at the end, and the contents
/// of small files straight from where they sit. Zip64 archives, which any
/// archive over 4 GB or 65,535 files is, read the same way.
abstract final class ZipReader {
  static const int _localSignature = 0x04034b50;
  static const int _centralSignature = 0x02014b50;
  static const int _endSignature = 0x06054b50;
  static const int _zip64EndSignature = 0x06064b50;
  static const int _zip64LocatorSignature = 0x07064b50;

  /// The end record, 22 bytes, is followed by a comment of up to 65,535.
  static const int _endSearch = 22 + 0xFFFF;

  /// The most read in one range, and in one call to [ZipSource.read], so
  /// a big central directory or a batch of small files never goes across
  /// in one piece.
  static const int _chunk = 4 << 20;

  /// The most ranges asked for in one call.
  static const int _batch = 256;

  /// Every file in the archive, folders left out, in the order the central
  /// directory lists them.
  static Future<List<ZipEntry>> entries(ZipSource source) async {
    final length = source.length;
    if (length < 22) throw await _notWhole(source);
    final tailStart = math.max(0, length - _endSearch);
    final [tail] = await source.read([(offset: tailStart, length: length - tailStart)]);
    final endAt = _findEnd(tail);
    if (endAt == null) throw await _notWhole(source);
    final end = ByteData.sublistView(tail, endAt);

    var count = end.getUint16(10, Endian.little);
    var directorySize = end.getUint32(12, Endian.little);
    var directoryOffset = end.getUint32(16, Endian.little);
    if (count == 0xFFFF || directorySize == 0xFFFFFFFF || directoryOffset == 0xFFFFFFFF) {
      final zip64 = await _zip64End(source, tailStart + endAt);
      count = zip64.count;
      directorySize = zip64.size;
      directoryOffset = zip64.offset;
    }
    if (directoryOffset + directorySize > length) {
      throw const ZipFormatException(ZipProblem.damaged, 'The list of files runs past the end');
    }
    final directory = await _readSpan(source, directoryOffset, directorySize);
    return _parseDirectory(directory, count);
  }

  /// Where the data of each of [entries] starts, read from their local
  /// headers, whose extra fields can differ from the central directory's.
  static Future<List<int>> dataOffsets(ZipSource source, List<ZipEntry> entries) async {
    final offsets = <int>[];
    for (var start = 0; start < entries.length; start += _batch) {
      final batch = entries.sublist(start, math.min(entries.length, start + _batch));
      final headers = await source.read([
        for (final entry in batch) (offset: entry.headerOffset, length: 30),
      ]);
      for (final (index, header) in headers.indexed) {
        final entry = batch[index];
        if (header.length < 30) {
          throw ZipFormatException(ZipProblem.incomplete, '${entry.path} is cut short');
        }
        final view = ByteData.sublistView(header);
        if (view.getUint32(0, Endian.little) != _localSignature) {
          throw ZipFormatException(ZipProblem.damaged, '${entry.path} has no header');
        }
        final nameLength = view.getUint16(26, Endian.little);
        final extraLength = view.getUint16(28, Endian.little);
        offsets.add(entry.headerOffset + 30 + nameLength + extraLength);
      }
    }
    return offsets;
  }

  /// What each of [entries] holds, unpacked and checked against its
  /// checksum. Meant for small files, such as the JSON beside each photo
  /// in a Takeout archive: everything asked for is held in memory.
  static Future<List<Uint8List>> contents(ZipSource source, List<ZipEntry> entries) async {
    for (final entry in entries) {
      if (!entry.readable) {
        throw ZipFormatException(ZipProblem.unsupported, '${entry.path} is packed in a way Telegrive can\'t read');
      }
    }
    final offsets = await dataOffsets(source, entries);
    final out = <Uint8List>[];
    var start = 0;
    while (start < entries.length) {
      // As many as fit in one call, and always at least one.
      var end = start;
      var bytes = 0;
      while (end < entries.length &&
          end - start < _batch &&
          (end == start || bytes + entries[end].compressedSize <= _chunk)) {
        bytes += entries[end].compressedSize;
        end++;
      }
      final raw = await source.read([
        for (var i = start; i < end; i++) (offset: offsets[i], length: entries[i].compressedSize),
      ]);
      for (var i = start; i < end; i++) {
        out.add(unpack(entries[i], raw[i - start]));
      }
      start = end;
    }
    return out;
  }

  /// [raw], the packed bytes of [entry], unpacked and checked.
  static Uint8List unpack(ZipEntry entry, Uint8List raw) {
    if (raw.length < entry.compressedSize) {
      throw ZipFormatException(ZipProblem.incomplete, '${entry.path} is cut short');
    }
    final Uint8List data;
    try {
      data = switch (entry.method) {
        ZipEntry.stored => raw,
        ZipEntry.deflated => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
        _ => throw ZipFormatException(ZipProblem.unsupported, '${entry.path} is packed in a way Telegrive can\'t read'),
      };
    } on FormatException {
      throw ZipFormatException(ZipProblem.damaged, '${entry.path} is damaged');
    }
    if (data.length != entry.size || Crc32.of(data) != entry.crc) {
      throw ZipFormatException(ZipProblem.damaged, '${entry.path} is damaged');
    }
    return data;
  }

  /// Where the end record starts in [tail], searching back from the end,
  /// since a comment may follow it.
  static int? _findEnd(Uint8List tail) {
    final view = ByteData.sublistView(tail);
    for (var at = tail.length - 22; at >= 0; at--) {
      if (view.getUint32(at, Endian.little) != _endSignature) continue;
      final commentLength = view.getUint16(at + 20, Endian.little);
      // A signature inside the comment, or in data, doesn't line up with
      // the end of the archive.
      if (at + 22 + commentLength <= tail.length) return at;
    }
    return null;
  }

  /// Reads the Zip64 end record that the locator just before [endAt]
  /// points to.
  static Future<({int count, int size, int offset})> _zip64End(ZipSource source, int endAt) async {
    if (endAt < 20) throw const ZipFormatException(ZipProblem.damaged, 'The Zip64 locator is missing');
    final [locator] = await source.read([(offset: endAt - 20, length: 20)]);
    final view = ByteData.sublistView(locator);
    if (locator.length < 20 || view.getUint32(0, Endian.little) != _zip64LocatorSignature) {
      throw const ZipFormatException(ZipProblem.damaged, 'The Zip64 locator is missing');
    }
    final recordAt = view.getUint64(8, Endian.little);
    final [record] = await source.read([(offset: recordAt, length: 56)]);
    final fields = ByteData.sublistView(record);
    if (record.length < 56 || fields.getUint32(0, Endian.little) != _zip64EndSignature) {
      throw const ZipFormatException(ZipProblem.damaged, 'The Zip64 end record is missing');
    }
    return (
      count: fields.getUint64(32, Endian.little),
      size: fields.getUint64(40, Endian.little),
      offset: fields.getUint64(48, Endian.little),
    );
  }

  static Future<Uint8List> _readSpan(ZipSource source, int offset, int length) async {
    final out = BytesBuilder(copy: false);
    var at = offset;
    final end = offset + length;
    while (at < end) {
      final ranges = <ByteRange>[];
      var asked = 0;
      while (at < end && asked < _chunk * 2) {
        final size = math.min(_chunk, end - at);
        ranges.add((offset: at, length: size));
        at += size;
        asked += size;
      }
      for (final piece in await source.read(ranges)) {
        out.add(piece);
      }
    }
    final bytes = out.takeBytes();
    if (bytes.length < length) {
      throw const ZipFormatException(ZipProblem.incomplete, 'The list of files is cut short');
    }
    return bytes;
  }

  static List<ZipEntry> _parseDirectory(Uint8List directory, int count) {
    final view = ByteData.sublistView(directory);
    final entries = <ZipEntry>[];
    var at = 0;
    for (var index = 0; index < count; index++) {
      if (at + 46 > directory.length || view.getUint32(at, Endian.little) != _centralSignature) {
        throw const ZipFormatException(ZipProblem.damaged, 'The list of files doesn\'t add up');
      }
      final flags = view.getUint16(at + 8, Endian.little);
      final method = view.getUint16(at + 10, Endian.little);
      final crc = view.getUint32(at + 16, Endian.little);
      var compressedSize = view.getUint32(at + 20, Endian.little);
      var size = view.getUint32(at + 24, Endian.little);
      final nameLength = view.getUint16(at + 28, Endian.little);
      final extraLength = view.getUint16(at + 30, Endian.little);
      final commentLength = view.getUint16(at + 32, Endian.little);
      var headerOffset = view.getUint32(at + 42, Endian.little);
      final nameAt = at + 46;
      final extraAt = nameAt + nameLength;
      final next = extraAt + extraLength + commentLength;
      if (next > directory.length) {
        throw const ZipFormatException(ZipProblem.damaged, 'The list of files doesn\'t add up');
      }
      final path = _name(directory.sublist(nameAt, extraAt), utf8Flag: flags & 0x800 != 0);

      // Sizes and offsets too big for their fields are 0xFFFFFFFF there,
      // and given in full, in that order, in the Zip64 extra field.
      if (size == 0xFFFFFFFF || compressedSize == 0xFFFFFFFF || headerOffset == 0xFFFFFFFF) {
        var field = extraAt;
        final extraEnd = extraAt + extraLength;
        while (field + 4 <= extraEnd) {
          final id = view.getUint16(field, Endian.little);
          final dataLength = view.getUint16(field + 2, Endian.little);
          if (id == 0x0001) {
            var value = field + 4;
            int take() {
              final v = view.getUint64(value, Endian.little);
              value += 8;
              return v;
            }

            if (size == 0xFFFFFFFF) size = take();
            if (compressedSize == 0xFFFFFFFF) compressedSize = take();
            if (headerOffset == 0xFFFFFFFF) headerOffset = take();
            break;
          }
          field += 4 + dataLength;
        }
      }
      at = next;
      if (path.endsWith('/')) continue;
      entries.add(
        ZipEntry(
          path: path,
          method: method,
          crc: crc,
          compressedSize: compressedSize,
          size: size,
          headerOffset: headerOffset,
          encrypted: flags & 0x1 != 0,
        ),
      );
    }
    return entries;
  }

  /// A file name as the archive spells it: UTF-8 when it says so, and
  /// otherwise UTF-8 if it reads as such, which archivers often write
  /// without the flag, or else one byte per character.
  static String _name(Uint8List bytes, {required bool utf8Flag}) {
    if (utf8Flag) return utf8.decode(bytes, allowMalformed: true);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// The reason [source] has no end record: a file that starts the way a
  /// zip archive does was cut short; anything else isn't one.
  static Future<ZipFormatException> _notWhole(ZipSource source) async {
    final [head] = await source.read([(offset: 0, length: 4)]);
    final isZip = head.length == 4 && ByteData.sublistView(head).getUint32(0, Endian.little) == _localSignature;
    return isZip
        ? const ZipFormatException(ZipProblem.incomplete, 'The archive is cut short')
        : const ZipFormatException(ZipProblem.notZip, 'Not a zip archive');
  }
}

/// The CRC-32 zip archives check each file against.
final class Crc32 {
  Crc32();

  static final Uint32List _table = () {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }();

  int _value = 0xFFFFFFFF;

  void add(List<int> bytes) {
    var c = _value;
    for (final byte in bytes) {
      c = _table[(c ^ byte) & 0xFF] ^ (c >> 8);
    }
    _value = c;
  }

  int get value => _value ^ 0xFFFFFFFF;

  static int of(List<int> bytes) => (Crc32()..add(bytes)).value;
}
