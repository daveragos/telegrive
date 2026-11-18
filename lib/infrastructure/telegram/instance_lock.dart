import 'dart:io';

/// Keeps a second copy of the app on a computer away from TDLib's database.
///
/// On a computer no background job shares the app's process, so a lock
/// file does what [TdOwnership]'s socket does on a phone: the system holds
/// it for the process that took it and lets go when that process ends,
/// however it ends. It works on Windows too, which has no Unix sockets for
/// Dart. The lock is kept for the life of the process.
abstract final class InstanceLock {
  static RandomAccessFile? _held;

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
    return true;
  }
}

/// Another copy of the app holds [InstanceLock].
class AlreadyOpen implements Exception {
  const AlreadyOpen();

  String get message => 'Telegrive is already open on this computer. Close the other window first.';

  @override
  String toString() => 'AlreadyOpen';
}
