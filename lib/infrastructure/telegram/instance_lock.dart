import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Keeps a second copy of the app on a computer away from TDLib's database.
///
/// On a computer no background job shares the app's process, so a lock
/// file does what [TdOwnership]'s socket does on a phone: the system holds
/// it for the process that took it and lets go when that process ends,
/// however it ends. It works on Windows too, which has no Unix sockets for
/// Dart. The lock is kept for the life of the process.
///
/// The copy that holds it also listens on the loopback address, on a port
/// it writes beside the lock, so opening Telegrive again while it runs
/// hidden in the tray brings its window back ([wakeHolder]) rather than
/// saying it is already open.
abstract final class InstanceLock {
  static RandomAccessFile? _held;

  /// What a second copy asking this one to show itself does.
  static void Function()? onWake;

  /// Takes the lock in [dir], and says whether this process holds it.
  static Future<bool> tryAcquire(Directory dir) async {
    if (_held != null) return true;
    await dir.create(recursive: true);
    final file = await File('${dir.path}/instance.lock').open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException {
      await file.close();
      return false;
    }
    _held = file;
    await _listen(dir);
    return true;
  }

  static Future<void> _listen(Directory dir) async {
    try {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await File('${dir.path}/instance.port').writeAsString('${listener.port}', flush: true);
      listener.listen((socket) {
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .listen(
              (said) {
                if (said.trim() == 'show') onWake?.call();
              },
              onDone: socket.destroy,
              onError: (_) => socket.destroy(),
            );
      });
    } catch (e) {
      debugPrint('[Instance] Not listening for a second copy: $e');
    }
  }

  /// Asks the copy holding the lock in [dir] to show its window, and says
  /// whether it was reached.
  static Future<bool> wakeHolder(Directory dir) async {
    try {
      final port = int.parse((await File('${dir.path}/instance.port').readAsString()).trim());
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2));
      socket.write('show\n');
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('[Instance] Could not reach the copy already open: $e');
      return false;
    }
  }
}

/// Another copy of the app holds [InstanceLock].
class AlreadyOpen implements Exception {
  const AlreadyOpen();

  String get message => 'Telegrive is already open on this computer. Close the other window first.';

  @override
  String toString() => 'AlreadyOpen';
}
