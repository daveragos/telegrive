import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:handy_tdlib/handy_tdlib.dart';

import 'td_library.dart';

/// Runs TDLib's blocking `td_receive` on a background isolate.
///
/// TDLib's client registry is process-global, so an isolate that opens the
/// library itself receives updates for every client id in the process. Both
/// the native wait and the JSON decode happen off the UI thread; the isolate
/// hands back plain maps.
///
/// `td_receive` must never be called concurrently, so this is the only place
/// in the app that calls it. It keeps running across client restarts (sign
/// out creates a fresh client id); payloads carry `@client_id` so the caller
/// can drop ones meant for a client that no longer exists.
class TdReceiver {
  TdReceiver({required this.onPayload});

  /// How long each native wait lasts before returning empty.
  static const double _receiveTimeoutSeconds = 1.0;

  static const Duration _readyTimeout = Duration(seconds: 3);

  /// A native wait lasts [_receiveTimeoutSeconds], so the loop has gone well
  /// within this.
  static const Duration _exitTimeout = Duration(seconds: 3);

  final void Function(Map<String, dynamic> payload) onPayload;

  Isolate? _isolate;
  ReceivePort? _port;
  StreamSubscription<dynamic>? _subscription;

  bool get isRunning => _isolate != null;

  /// Spawns the isolate. Throws if TDLib could not be opened there.
  Future<void> start() async {
    if (_isolate != null) return;

    final port = ReceivePort();
    final ready = Completer<Object?>();
    _port = port;
    _subscription = port.listen((message) {
      if (!ready.isCompleted && (message is bool || message is String)) {
        ready.complete(message);
        return;
      }
      if (message is Map<String, dynamic>) onPayload(message);
    });

    _isolate = await Isolate.spawn(
      _receiveLoop,
      port.sendPort,
      debugName: 'tdlib-receiver',
      errorsAreFatal: false,
    );

    final result = await ready.future.timeout(
      _readyTimeout,
      onTimeout: () => 'TDLib receiver did not start in time',
    );
    if (result != true) {
      await stop();
      throw StateError('Could not load TDLib: $result');
    }
    debugPrint('[TdReceiver] Receiving on a background isolate');
  }

  /// Ends the receive loop and waits for its isolate to exit. A kill lands
  /// only once the native wait under way returns, so until then the loop
  /// may still be inside `td_receive`; another engine in this process
  /// starts receiving only after this completes.
  Future<void> stop() async {
    final isolate = _isolate;
    _isolate = null;
    if (isolate != null) {
      final exited = ReceivePort();
      isolate.addOnExitListener(exited.sendPort);
      isolate.kill(priority: Isolate.immediate);
      await exited.first.timeout(_exitTimeout, onTimeout: () => null);
      exited.close();
    }
    await _subscription?.cancel();
    _subscription = null;
    _port?.close();
    _port = null;
  }

  static Future<void> _receiveLoop(SendPort sendPort) async {
    try {
      await openTdLibrary();
    } catch (e) {
      sendPort.send(e.toString());
      return;
    }
    sendPort.send(true);

    while (true) {
      final raw = TdPlugin.instance.tdReceive(_receiveTimeoutSeconds);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) sendPort.send(decoded);
      } catch (_) {
        // One unparseable payload is not worth tearing the loop down for.
      }
    }
  }
}
