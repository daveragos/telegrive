import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// How much room the disk under a folder has on a computer, read where
/// the system keeps it: from df on macOS and Linux, and from
/// GetDiskFreeSpaceExW on Windows. A phone asks its own channel instead.
abstract final class DiskSpace {
  /// Answers are kept this long, since room checks ask before every
  /// transfer and the disk doesn't change much in between.
  static const Duration _keep = Duration(seconds: 10);

  static final Map<String, ({DateTime at, int free, int total})> _known = {};

  /// The bytes free and in all on the disk holding [path], or null when
  /// they can't be read.
  static Future<({int free, int total})?> of(String path) async {
    final known = _known[path];
    if (known != null && DateTime.now().difference(known.at) < _keep) {
      return (free: known.free, total: known.total);
    }
    try {
      final read = Platform.isWindows ? _windows(path) : await _df(path);
      if (read != null) _known[path] = (at: DateTime.now(), free: read.free, total: read.total);
      return read;
    } catch (e) {
      debugPrint('[DiskSpace] $path: $e');
      return null;
    }
  }

  /// The free and total bytes in df's POSIX listing for [path], in 1024
  /// byte blocks.
  static Future<({int free, int total})?> _df(String path) async {
    final result = await Process.run('df', ['-Pk', path]);
    if (result.exitCode != 0) return null;
    return parseDf(result.stdout as String);
  }

  /// The second line of `df -Pk`: total, used and available blocks.
  @visibleForTesting
  static ({int free, int total})? parseDf(String output) {
    final lines = output.trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    // A long device name can push the figures onto a line of their own.
    final numbers = [for (final field in fields) int.tryParse(field)].whereType<int>().toList();
    if (numbers.length < 3) return null;
    return (free: numbers[2] * 1024, total: numbers[0] * 1024);
  }

  static ({int free, int total})? _windows(String path) => using((arena) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getDiskFreeSpace = kernel32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
      int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)
    >('GetDiskFreeSpaceExW');
    final free = arena<Uint64>();
    final total = arena<Uint64>();
    final ok = getDiskFreeSpace(path.toNativeUtf16(allocator: arena), free, total, nullptr);
    return ok == 0 ? null : (free: free.value, total: total.value);
  });
}
