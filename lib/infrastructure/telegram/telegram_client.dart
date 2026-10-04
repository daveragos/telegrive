import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart' show TdPlugin;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/config/telegram_api.dart';
import 'device_info.dart';
import 'secure_store.dart';
import 'td_receiver.dart';
import 'telegram_exception.dart';

/// The one connection to Telegram.
///
/// Wraps TDLib's JSON interface: requests go out with an `@extra` tag and the
/// matching reply completes the future returned by [send]; everything else is
/// an update and goes to [updates]. No TDLib type is meant to leak past the
/// `infrastructure` and `features/*/data` layers — screens see app models.
///
/// The client is restartable. Signing out closes the
/// TDLib instance; when it reports `authorizationStateClosed` a fresh client
/// is created on the same receiver, which lands back on the sign-in screen.
class TelegramClient {
  TelegramClient(this._secureStore) {
    _receiver = TdReceiver(onPayload: _handlePayload);
  }

  final SecureStore _secureStore;
  late final TdReceiver _receiver;

  int? _clientId;
  int _requestSeq = 0;
  bool _disposed = false;
  Future<void>? _starting;

  final Map<String, Completer<td.TdObject>> _pending = {};

  final _updates = StreamController<td.TdObject>.broadcast();
  final _authStates = StreamController<td.AuthorizationState>.broadcast();
  td.AuthorizationState? _authState;
  final _connectionStates = StreamController<td.ConnectionState>.broadcast();
  td.ConnectionState? _connectionState;

  /// Set when configuration itself failed — a missing native library, a
  /// corrupt database that could not be recovered. Shown on the splash screen.
  final ValueNotifier<String?> fatalError = ValueNotifier(null);

  Stream<td.TdObject> get updates => _updates.stream;

  td.AuthorizationState? get authState => _authState;

  /// Authorization states, replaying the current one to each new listener.
  Stream<td.AuthorizationState> get authStates async* {
    final current = _authState;
    if (current != null) yield current;
    yield* _authStates.stream;
  }

  /// TDLib's own view of the connection: waiting for a network, connecting,
  /// catching up, ready. It is the one place the app asks whether Telegram
  /// can be reached; the phone's network state only says whether there is
  /// a connection at all.
  td.ConnectionState? get connectionState => _connectionState;

  /// Connection states, replaying the current one to each new listener.
  Stream<td.ConnectionState> get connectionStates async* {
    final current = _connectionState;
    if (current != null) yield current;
    yield* _connectionStates.stream;
  }

  /// File progress updates, for uploads and downloads alike.
  Stream<td.File> get fileUpdates => _updates.stream
      .where((u) => u is td.UpdateFile)
      .map((u) => (u as td.UpdateFile).file);

  /// Loads TDLib, starts receiving and creates the first client. Safe to call
  /// more than once.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      await TdPlugin.initialize();
      // Keep TDLib's own logging to errors only; it is chatty by default and
      // writes to logcat on every network hiccup.
      TdPlugin.instance.tdExecute(
        jsonEncode(const td.SetLogVerbosityLevel(newVerbosityLevel: 1).toJson()),
      );
      await _receiver.start();
      _createClient();
    } catch (e) {
      _starting = null;
      fatalError.value = 'Could not start Telegram: $e';
      rethrow;
    }
  }

  void _createClient() {
    _clientId = TdPlugin.instance.tdCreateClientId();
    debugPrint('[Telegram] Client $_clientId created');
    // TDLib emits its first authorization state in response to any request.
    unawaited(_sendQuietly(const td.GetOption(name: 'version')));
  }

  /// Sends [function] and waits for its typed reply.
  ///
  /// A short flood wait (≤ 10 s) is sat out once and the request retried;
  /// anything longer surfaces as a [TelegramException] so the caller can tell
  /// the person how long to wait.
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await _sendOnce<T>(function, timeout);
    } on TelegramException catch (e) {
      final wait = e.retryAfterSeconds;
      if (!e.isFloodWait || wait == null || wait > 10) rethrow;
      await Future<void>.delayed(Duration(seconds: wait, milliseconds: 250));
      return _sendOnce<T>(function, timeout);
    }
  }

  Future<T> _sendOnce<T extends td.TdObject>(
    td.TdFunction function,
    Duration timeout,
  ) async {
    final clientId = _clientId;
    if (clientId == null) {
      throw const TelegramException(500, 'Telegram is not running');
    }
    final extra = '${++_requestSeq}';
    final completer = Completer<td.TdObject>();
    _pending[extra] = completer;
    TdPlugin.instance.tdSend(clientId, jsonEncode(function.toJson(extra)));

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(extra);
        throw const TelegramException(408, 'Request timeout');
      },
    );
    if (result is! T) {
      throw TelegramException(
        500,
        'Expected $T from ${function.runtimeType}, got ${result.runtimeType}',
      );
    }
    return result;
  }

  void _handlePayload(Map<String, dynamic> map) {
    // Leftovers from a client closed by sign-out still drain through the
    // shared receiver; they belong to nobody now.
    final owner = map['@client_id'];
    if (owner != null && owner != _clientId) return;

    if (map.containsKey('@extra')) {
      final completer = _pending.remove('${map['@extra']}');
      if (completer == null) return;
      final object = td.convertMapToObject(map);
      if (object == null) {
        completer.completeError(
          TelegramException(500, 'Unreadable reply: ${map['@type']}'),
        );
      } else if (object is td.TdError) {
        completer.completeError(TelegramException(object.code, object.message));
      } else {
        completer.complete(object);
      }
      return;
    }

    final object = td.convertMapToObject(map);
    if (object == null) return;
    if (object is td.UpdateAuthorizationState) {
      _onAuthorizationState(object.authorizationState);
    }
    if (object is td.UpdateConnectionState) _onConnectionState(object.state);
    if (!_updates.isClosed) _updates.add(object);
  }

  /// Takes [payload] as if the receiver had brought it from TDLib. Tests
  /// hand the client an update this way; nothing else needs to.
  @visibleForTesting
  void receive(Map<String, dynamic> payload) => _handlePayload(payload);

  void _onConnectionState(td.ConnectionState state) {
    _connectionState = state;
    if (!_connectionStates.isClosed) _connectionStates.add(state);
  }

  void _onAuthorizationState(td.AuthorizationState state) {
    debugPrint('[Telegram] Auth state → ${state.runtimeType}');
    _authState = state;
    if (!_authStates.isClosed) _authStates.add(state);

    switch (state) {
      case td.AuthorizationStateWaitTdlibParameters():
        unawaited(_configure());
      case td.AuthorizationStateReady():
        // A drive app has no business showing its owner as "online" to
        // their contacts every time they browse files.
        unawaited(_setOption('online', const td.OptionValueBoolean(value: false)));
      case td.AuthorizationStateClosed():
        _failPending();
        if (!_disposed) _createClient();
      default:
        break;
    }
  }

  Future<void> _configure() async {
    final root = await getApplicationSupportDirectory();
    final databaseDir = Directory('${root.path}/tdlib/db');
    final filesDir = Directory('${root.path}/tdlib/files');
    await databaseDir.create(recursive: true);
    await filesDir.create(recursive: true);

    // The cache is created encrypted from the very first launch. TDLib only
    // allows changing the key after sign-in, so there is no "encrypt later".
    var key = await _secureStore.readDatabaseKey();
    if (key == null || key.isEmpty) {
      key = SecureStore.generateDatabaseKey();
      await _secureStore.writeDatabaseKey(key);
    }

    // Telegram's Devices list names the session after these, so the person
    // can tell this phone from another one signed in with Telegrive.
    final device = await DeviceInfo.read();
    td.SetTdlibParameters parameters(String key) => td.SetTdlibParameters(
      useTestDc: false,
      databaseDirectory: databaseDir.path,
      filesDirectory: filesDir.path,
      databaseEncryptionKey: key,
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: TelegramApi.apiId,
      apiHash: TelegramApi.apiHash,
      systemLanguageCode: Platform.localeName.split('_').first,
      deviceModel: device.model,
      systemVersion: device.system,
      applicationVersion: AppConfig.appVersion,
    );

    try {
      await send<td.Ok>(parameters(key));
    } on TelegramException catch (e) {
      // The database and its key disagree — typically restored app data
      // without the keystore entry. The local cache is only a cache; start it
      // over rather than leaving the app stuck.
      debugPrint('[Telegram] Parameters rejected (${e.message}); resetting');
      await databaseDir.delete(recursive: true);
      await databaseDir.create(recursive: true);
      final fresh = SecureStore.generateDatabaseKey();
      await _secureStore.writeDatabaseKey(fresh);
      try {
        await send<td.Ok>(parameters(fresh));
      } on TelegramException catch (e) {
        fatalError.value = e.friendlyMessage;
      }
    }
  }

  Future<void> logOut() => _sendQuietly(const td.LogOut());

  Future<void> setNetworkType(td.NetworkType type) async {
    // TDLib only answers this once it has its parameters.
    final state = _authState;
    if (state == null || state is td.AuthorizationStateWaitTdlibParameters) return;
    await _sendQuietly(td.SetNetworkType(type: type));
  }

  Future<void> _setOption(String name, td.OptionValue value) =>
      _sendQuietly(td.SetOption(name: name, value: value));

  Future<void> _sendQuietly(td.TdFunction function) async {
    try {
      await send<td.TdObject>(function, timeout: const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Telegram] ${function.runtimeType} failed: $e');
    }
  }

  void _failPending() {
    final pending = Map.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      completer.completeError(
        const TelegramException(500, 'Telegram session closed'),
      );
    }
  }

  /// Asks TDLib to flush and close. It buffers writes, so a process killed
  /// without this pays for recovery on the next launch.
  Future<void> close() async {
    _disposed = true;
    await _sendQuietly(const td.Close());
  }

  Future<void> dispose() async {
    _disposed = true;
    await _receiver.stop();
    _failPending();
    await _updates.close();
    await _authStates.close();
    await _connectionStates.close();
    fatalError.dispose();
  }
}

final telegramClientProvider = Provider<TelegramClient>((ref) {
  final client = TelegramClient(ref.watch(secureStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});

/// The live TDLib authorization state.
final authStateProvider = StreamProvider<td.AuthorizationState>((ref) {
  return ref.watch(telegramClientProvider).authStates;
});

/// The live TDLib connection state: whether Telegram can be reached.
final connectionStateProvider = StreamProvider<td.ConnectionState>((ref) {
  return ref.watch(telegramClientProvider).connectionStates;
});
