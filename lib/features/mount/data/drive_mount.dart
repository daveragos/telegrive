import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Mounting the drive's WebDAV address with what each system has built
/// in: Finder's own WebDAV client on a Mac, the WebClient service behind
/// a drive letter on Windows, and GVfs on Linux. Nothing is installed.
abstract final class DriveMount {
  /// Mounts [address] and answers where it shows: a folder under /Volumes,
  /// a drive letter, or the GVfs address a Linux file manager opens.
  static Future<String> mount(Uri address) async {
    final url = address.toString();
    if (Platform.isMacOS) return _mountOnMac(address);
    if (Platform.isWindows) {
      final letter = await _freeLetter();
      await _run('net', ['use', '$letter:', url.replaceAll(RegExp(r'/$'), ''), '/persistent:no']);
    } else if (Platform.isLinux) {
      await _run('gio', ['mount', _davUrl(address)]);
    }
    final place = await mountedAt(address);
    if (place == null) throw const FileSystemException('The drive didn\'t mount');
    return place;
  }

  /// How long a Mac gets to show the disk.
  static const Duration _macMountWait = Duration(seconds: 30);

  /// AppleScript's `mount volume` mounts the disk and then waits for as
  /// long as it stays mounted, so it is left to it, and let go once the
  /// disk shows; the disk stays.
  static Future<String> _mountOnMac(Uri address) async {
    final process = await Process.start('osascript', ['-e', 'mount volume "$address"']);
    int? exitCode;
    unawaited(process.exitCode.then((code) => exitCode = code));
    final errors = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());
    final until = DateTime.now().add(_macMountWait);
    try {
      while (DateTime.now().isBefore(until)) {
        final place = await mountedAt(address);
        if (place != null) return place;
        if (exitCode case final code? when code != 0) {
          throw ProcessException('osascript', const ['mount volume'], (await errors).trim(), code);
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw const FileSystemException('The drive didn\'t mount');
    } finally {
      process.kill();
    }
  }

  /// Unmounts [address], wherever it shows.
  static Future<void> unmount(Uri address) async {
    final place = await mountedAt(address);
    if (place == null) return;
    if (Platform.isMacOS) {
      try {
        await _run('diskutil', ['unmount', place]);
      } on ProcessException {
        await _run('diskutil', ['unmount', 'force', place]);
      }
    } else if (Platform.isWindows) {
      await _run('net', ['use', place, '/delete', '/y']);
    } else if (Platform.isLinux) {
      await _run('gio', ['mount', '-u', _davUrl(address)]);
    }
  }

  /// Where [address] is mounted now, or null when it isn't.
  static Future<String?> mountedAt(Uri address) async {
    try {
      if (Platform.isMacOS) return macMountPoint((await _run('mount', const [])), address);
      if (Platform.isWindows) return windowsDriveLetter((await _run('net', ['use'])), address);
      if (Platform.isLinux) {
        final listed = await _run('gio', ['mount', '-l']);
        return listed.contains(_davUrl(address)) ? _davUrl(address) : null;
      }
    } catch (e) {
      debugPrint('[Mount] $e');
    }
    return null;
  }

  /// Where `mount` says [address] is mounted on a Mac, as
  /// `http://127.0.0.1:5000/t/Telegrive/ on /Volumes/Telegrive (webdav, …)`.
  @visibleForTesting
  static String? macMountPoint(String listing, Uri address) {
    final url = address.toString();
    final bare = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    for (final line in listing.split('\n')) {
      if (!line.startsWith(url) && !line.startsWith('$bare ')) continue;
      final match = RegExp(r' on (.+) \(').firstMatch(line);
      if (match != null) return match[1];
    }
    return null;
  }

  /// The drive letter `net use` lists [address] under, as
  /// `OK  T:  \\127.0.0.1@5000\t\Telegrive  Web Client Network`.
  @visibleForTesting
  static String? windowsDriveLetter(String listing, Uri address) {
    final unc = '\\\\${address.host}@${address.port}\\${address.pathSegments.where((s) => s.isNotEmpty).join('\\')}'
        .toLowerCase();
    for (final line in listing.split(RegExp(r'\r?\n'))) {
      if (!line.toLowerCase().contains(unc)) continue;
      final letter = RegExp(r'\b([A-Z]):', caseSensitive: false).firstMatch(line);
      if (letter != null) return '${letter[1]!.toUpperCase()}:';
    }
    return null;
  }

  /// The address as GVfs names it.
  static String _davUrl(Uri address) => address.replace(scheme: 'dav').toString();

  /// The first letter free from T on, then back from S, for the drive.
  static Future<String> _freeLetter() async {
    const letters = 'TUVWXYZSRQPONMLKJIHGFE';
    for (final letter in letters.split('')) {
      if (!await Directory('$letter:\\').exists()) return letter;
    }
    throw const FileSystemException('No drive letter is free');
  }

  static Future<String> _run(String command, List<String> args) async {
    final result = await Process.run(command, args);
    if (result.exitCode != 0) {
      throw ProcessException(command, args, '${result.stderr}'.trim(), result.exitCode);
    }
    return '${result.stdout}';
  }

  // ---------------------------------------------------------------------------
  // Windows' file size limit
  // ---------------------------------------------------------------------------

  /// Windows' WebClient refuses files bigger than this, by default, through
  /// a drive letter.
  static const int windowsDefaultLimit = 50000000;

  /// The most WebClient takes at all.
  static const int windowsMaxLimit = 0xFFFFFFFF;

  static const String _webClientKey = r'HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters';

  /// The biggest file Windows lets through the drive letter, or null when it
  /// can't be read.
  static Future<int?> windowsFileLimit() async {
    try {
      final listed = await _run('reg', ['query', _webClientKey, '/v', 'FileSizeLimitInBytes']);
      final hex = RegExp(r'0x([0-9a-fA-F]+)').firstMatch(listed);
      return hex == null ? windowsDefaultLimit : int.parse(hex[1]!, radix: 16);
    } catch (_) {
      return null;
    }
  }

  /// Raises Windows' limit to [windowsMaxLimit], about 4 GB, and restarts
  /// WebClient to take it, which Windows asks the person to allow.
  static Future<void> raiseWindowsFileLimit() => _run('powershell', [
    '-NoProfile',
    '-Command',
    "Start-Process -Verb RunAs -Wait -WindowStyle Hidden -FilePath cmd.exe -ArgumentList '/c "
        'reg add $_webClientKey /v FileSizeLimitInBytes /t REG_DWORD /d $windowsMaxLimit /f '
        "& net stop webclient & net start webclient'",
  ]);
}
