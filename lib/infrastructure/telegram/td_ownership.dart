import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Which engine in this process may run TDLib.
///
/// TDLib's receive call must never run on two threads at once, and the
/// background backup job runs on its own engine in the app's own process,
/// so a lock file can't keep the two apart: file locks don't exclude the
/// process that holds them. A Unix socket in [dir] can. Whoever binds it
/// owns TDLib; anyone else finds it taken, and can ask the owner to hand
/// over by sending the line `yield`. A socket file that nobody answers on
/// is treated as left over and is replaced. Whether a bound socket outlives
/// the engine that bound it is not assumed, so an owner is expected to
/// [release] when it is done.
class TdOwnership {
  TdOwnership(this.dir);

  /// Where `owner.sock` lives: TDLib's folder in app support.
  final Directory dir;

  ServerSocket? _server;

  /// Single-subscription, so a request that comes before the owner listens
  /// waits for it rather than being dropped.
  final StreamController<void> _yields = StreamController<void>();

  /// The ownership of TDLib's folder in app support, for code that only
  /// needs to ask whether someone holds it.
  static Future<TdOwnership> inAppSupport() async =>
      TdOwnership(Directory('${(await getApplicationSupportDirectory()).path}/tdlib'));

  File get _file => File('${dir.path}/owner.sock');

  InternetAddress get _address => InternetAddress(_file.path, type: InternetAddressType.unix);

  /// Each time another engine asks this owner to hand TDLib over. One
  /// listener only.
  Stream<void> get yieldRequests => _yields.stream;

  /// Takes ownership, and says whether it did. A socket somebody still
  /// answers on is theirs; one nobody answers on is left over from an
  /// owner that went away, and is replaced.
  Future<bool> tryAcquire() async {
    if (_server != null) return true;
    await dir.create(recursive: true);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final server = await ServerSocket.bind(_address, 0);
        _server = server;
        server.listen(_serve, onError: (Object _) {});
        return true;
      } on SocketException {
        if (await _answers()) return false;
        await _deleteQuietly();
      }
    }
    return false;
  }

  /// Asks the owner to hand TDLib over, and says whether there was an
  /// owner to ask.
  Future<bool> requestYield() async {
    try {
      final socket = await Socket.connect(_address, 0, timeout: _connectTimeout);
      socket.write('yield\n');
      await socket.flush();
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// Whether anyone, this engine included, owns TDLib now.
  Future<bool> isHeld() async => _server != null || await _answers();

  /// Gives ownership up. Closing the socket removes its file; one left
  /// behind is deleted only while nobody answers on it, so another engine
  /// that took over in the meantime keeps its own.
  Future<void> release() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    await server.close();
    if (await _file.exists() && !await _answers()) await _deleteQuietly();
  }

  static const Duration _connectTimeout = Duration(seconds: 2);

  /// Probes and requests that don't say `yield` are read to the end and
  /// closed.
  void _serve(Socket socket) {
    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim() == 'yield') _yields.add(null);
          },
          onError: (Object _) => socket.destroy(),
          onDone: socket.destroy,
          cancelOnError: true,
        );
  }

  Future<bool> _answers() async {
    try {
      final socket = await Socket.connect(_address, 0, timeout: _connectTimeout);
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> _deleteQuietly() async {
    try {
      await _file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
