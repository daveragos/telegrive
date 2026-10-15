import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:telegrive/core/files/zip_reader.dart';

/// Builds zip archives in memory for tests, the way an archiver writes
/// them: local headers with each file's data, then the central directory
/// and the end record. With [zip64], every size and offset goes in the
/// Zip64 fields, as an archiver does once an archive passes 4 GB.
class ZipBuilder {
  final List<({String path, Uint8List data, bool deflate})> _files = [];

  void add(String path, List<int> data, {bool deflate = true}) =>
      _files.add((path: path, data: Uint8List.fromList(data), deflate: deflate));

  void addText(String path, String text, {bool deflate = true}) => add(path, utf8.encode(text), deflate: deflate);

  void addJson(String path, Object json) => addText(path, jsonEncode(json));

  Uint8List build({bool zip64 = false, String comment = ''}) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    for (final file in _files) {
      final name = utf8.encode(file.path);
      final packed = file.deflate ? Uint8List.fromList(ZLibEncoder(raw: true).convert(file.data)) : file.data;
      final crc = Crc32.of(file.data);
      final offset = out.length;
      final zip64Extra = _u16(1) + _u16(16) + _u64(file.data.length) + _u64(packed.length);
      out
        ..add(_u32(0x04034b50))
        ..add(_u16(45))
        ..add(_u16(0x800))
        ..add(_u16(file.deflate ? 8 : 0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(crc))
        ..add(_u32(zip64 ? 0xFFFFFFFF : packed.length))
        ..add(_u32(zip64 ? 0xFFFFFFFF : file.data.length))
        ..add(_u16(name.length))
        ..add(_u16(zip64 ? zip64Extra.length : 0))
        ..add(name);
      if (zip64) out.add(zip64Extra);
      out.add(packed);

      final centralExtra = _u16(1) + _u16(24) + _u64(file.data.length) + _u64(packed.length) + _u64(offset);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(45))
        ..add(_u16(45))
        ..add(_u16(0x800))
        ..add(_u16(file.deflate ? 8 : 0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(crc))
        ..add(_u32(zip64 ? 0xFFFFFFFF : packed.length))
        ..add(_u32(zip64 ? 0xFFFFFFFF : file.data.length))
        ..add(_u16(name.length))
        ..add(_u16(zip64 ? centralExtra.length : 0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(zip64 ? 0xFFFFFFFF : offset))
        ..add(name);
      if (zip64) central.add(centralExtra);
    }
    final directoryOffset = out.length;
    final directory = central.takeBytes();
    out.add(directory);
    if (zip64) {
      final recordAt = out.length;
      out
        ..add(_u32(0x06064b50))
        ..add(_u64(44))
        ..add(_u16(45))
        ..add(_u16(45))
        ..add(_u32(0))
        ..add(_u32(0))
        ..add(_u64(_files.length))
        ..add(_u64(_files.length))
        ..add(_u64(directory.length))
        ..add(_u64(directoryOffset))
        ..add(_u32(0x07064b50))
        ..add(_u32(0))
        ..add(_u64(recordAt))
        ..add(_u32(1));
    }
    final commentBytes = utf8.encode(comment);
    out
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(zip64 ? 0xFFFF : _files.length))
      ..add(_u16(zip64 ? 0xFFFF : _files.length))
      ..add(_u32(zip64 ? 0xFFFFFFFF : directory.length))
      ..add(_u32(zip64 ? 0xFFFFFFFF : directoryOffset))
      ..add(_u16(commentBytes.length))
      ..add(commentBytes);
    return out.takeBytes();
  }

  /// Writes the archive to [path] and answers it.
  Future<File> write(String path, {bool zip64 = false}) => File(path).writeAsBytes(build(zip64: zip64));

  static List<int> _u16(int v) => (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List();
  static List<int> _u32(int v) => (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
  static List<int> _u64(int v) => (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();
}

/// A zip archive held in memory, read as a [ZipSource].
class MemoryZipSource implements ZipSource {
  MemoryZipSource(this.bytes);

  final Uint8List bytes;

  /// How many times [read] was called, to check that reads are batched.
  int calls = 0;

  @override
  int get length => bytes.length;

  @override
  Future<List<Uint8List>> read(List<ByteRange> ranges) async {
    calls++;
    return [
      for (final range in ranges)
        bytes.sublist(
          range.offset.clamp(0, bytes.length),
          (range.offset + range.length).clamp(0, bytes.length),
        ),
    ];
  }

  @override
  Future<void> extract(ZipEntry entry, int dataOffset, String path) async {
    final raw = bytes.sublist(dataOffset, (dataOffset + entry.compressedSize).clamp(0, bytes.length));
    await File(path).writeAsBytes(ZipReader.unpack(entry, raw));
  }
}
