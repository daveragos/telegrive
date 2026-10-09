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
import 'td_library.dart';
import 'td_ownership.dart';
import 'td_receiver.dart';
import 'telegram_exception.dart';

/// Which engine a [TelegramClient] runs in: the app's own, or the
/// background backup job's, which never takes TDLib from the app and never
/// starts its database over.
enum TdRole { app, worker }

/// The background job's client didn't start, because the app's engine owns
/// TDLib or a client another engine in this process opened may still be
/// running. The app backs up by itself then.
class TdBusy implements Exception {
  const TdBusy(this.reason);

  final String reason;

  @override
  String toString() => 'TdBusy($reason)';
}

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
///
/// Only one engine in the process runs TDLib at a time; see [TdOwnership].
/// The app's client asks a background job holding it to hand over, and the
/// job's client ([TdRole.worker]) gives up when the app holds it.
class TelegramClient {
  TelegramClient(this._secureStore, {this.role = TdRole.app}) {
    _receiver = TdReceiver(onPayload: _handlePayload);
  }

  final SecureStore _secureStore;
  late final TdReceiver _receiver;
  final TdRole role;

  /// TDLib's folder in app support, once [start] has found it.
  Directory? _root;
  TdOwnership? _ownership;

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
  final _online = StreamController<bool>.broadcast();
  Completer<void> _ready = Completer<void>();

  /// Set when configuration itself failed — a missing native library, a
  /// corrupt database that could not be recovered. Shown on the splash screen.
  final ValueNotifier<String?> fatalError = ValueNotifier(null);

  Stream<td.TdObject> get updates => _updates.stream;

  /// Each time another engine asks this one to hand TDLib over: the app
  /// opening while the background job runs.
  Stream<void> get yieldRequests => _ownership?.yieldRequests ?? const Stream.empty();

  td.AuthorizationState? get authState => _authState;

  /// Authorization states, replaying the current one to each new listener.
  Stream<td.AuthorizationState> get authStates async* {
    final current = _authState;
    if (current != null) yield current;
    yield* _authStates.stream;
  }

  /// Completes once an account is signed in, from which point TDLib answers
  /// about the account's chats and files. Home can show the drive before
  /// that, so work only Telegram can do (fetching a thumbnail, finding a
  /// file to download, play or read) waits for this first. A log-out starts
  /// the wait over, for the next account to sign in.
  Future<void> get ready => _ready.future;

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

  /// Whether a change sent now would reach Telegram: TDLib is connected,
  /// or connected and catching up. A change made otherwise waits on the
  /// phone rather than wait for a reply that may take minutes, since TDLib
  /// holds a request it can't send instead of failing it. Before TDLib
  /// has said anything about its connection, changes go straight out.
  bool get isOnline => _reaches(_connectionState);

  /// [isOnline] each time it changes, never the same value twice running.
  Stream<bool> get onlineChanges => _online.stream;

  static bool _reaches(td.ConnectionState? state) =>
      state == null ||
      state is td.ConnectionStateReady ||
      state is td.ConnectionStateUpdating;

  /// File progress updates, for uploads and downloads alike.
  Stream<td.File> get fileUpdates => _updates.stream
      .where((u) => u is td.UpdateFile)
      .map((u) => (u as td.UpdateFile).file);

  /// Loads TDLib, starts receiving and creates the first client. Safe to call
  /// more than once: a call while TDLib still waits for its parameters, after
  /// they failed, sends them again.
  Future<void> start() {
    if (_clientId != null &&
        _authState is td.AuthorizationStateWaitTdlibParameters &&
        fatalError.value == null) {
      unawaited(_configureOnce());
    }
    return _starting ??= _start();
  }

  Future<void>? _configuring;

  /// Sends TDLib its parameters, joining a send already under way: a second
  /// one TDLib doesn't expect would read as a database it can't open.
  Future<void> _configureOnce() =>
      _configuring ??= _configure().whenComplete(() => _configuring = null);

  /// How long the app waits for a background job to hand TDLib over.
  static const Duration _handOverTimeout = Duration(seconds: 20);
  static const Duration _handOverPoll = Duration(milliseconds: 250);

  Future<void> _start() async {
    try {
      final root = _root = Directory(
        '${(await getApplicationSupportDirectory()).path}/tdlib',
      );
      await _own(_ownership = TdOwnership(root));
      // A client this process opened and never closed: the engine that
      // opened it went away and this one took its place. The app takes it
      // over, rather than open the database a second time; the job can't
      // know that receiver has stopped, so it leaves it to the app.
      final leftOpen = await _leftOpenClient(root);
      if (leftOpen != null && role == TdRole.worker) {
        throw const TdBusy('A client opened in this process is still open.');
      }
      await openTdLibrary();
      // Keep TDLib's own logging to errors only; it is chatty by default and
      // writes to logcat on every network hiccup.
      TdPlugin.instance.tdExecute(
        jsonEncode(const td.SetLogVerbosityLevel(newVerbosityLevel: 1).toJson()),
      );
      await _receiver.start();
      if (leftOpen != null) {
        _adopt(leftOpen);
      } else {
        _createClient();
      }
    } on TdBusy {
      _starting = null;
      await _letGo();
      rethrow;
    } catch (e) {
      _starting = null;
      await _letGo();
      fatalError.value = 'Could not start Telegram: $e';
      rethrow;
    }
  }

  /// Releases the ownership a start that failed was holding, so a retry
  /// builds its own rather than finding this one's socket answering.
  Future<void> _letGo() async {
    final ownership = _ownership;
    _ownership = null;
    await ownership?.release();
  }

  /// Takes ownership of TDLib. The app asks a job that holds it to hand
  /// over and waits for it, and after [_handOverTimeout] goes ahead
  /// regardless, since it is the one the person is looking at. The job
  /// never waits.
  Future<void> _own(TdOwnership ownership) async {
    if (await ownership.tryAcquire()) return;
    if (role == TdRole.worker) throw const TdBusy('The app holds TDLib.');
    await ownership.requestYield();
    final until = DateTime.now().add(_handOverTimeout);
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(_handOverPoll);
      if (await ownership.tryAcquire()) return;
    }
    debugPrint('[Telegram] No hand-over after ${_handOverTimeout.inSeconds} s; going ahead');
    unawaited(_ownWhenFree(ownership));
  }

  /// Takes ownership as soon as the job lets go, so no other job starts
  /// TDLib while the app runs it.
  Future<void> _ownWhenFree(TdOwnership ownership) async {
    while (!_disposed && identical(_ownership, ownership) && !await ownership.tryAcquire()) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  /// The client id `client.json` names, when this very process wrote it.
  static Future<int?> _leftOpenClient(Directory root) async {
    try {
      final saved = jsonDecode(await File('${root.path}/client.json').readAsString());
      if (saved is Map && saved['pid'] == pid && saved['clientId'] is int) {
        return saved['clientId'] as int;
      }
    } catch (_) {
      // None saved, or unreadable: there is nothing to take over.
    }
    return null;
  }

  /// Records which client this process has open, so an engine that takes
  /// this one's place in the same process can take it over.
  Future<void> _saveClient(int clientId) async {
    final root = _root;
    if (root == null) return;
    try {
      await File('${root.path}/client.json').writeAsString(
        jsonEncode({'pid': pid, 'clientId': clientId}),
      );
    } catch (e) {
      debugPrint('[Telegram] Could not save the client id: $e');
    }
  }

  Future<void> _forgetClient() async {
    final root = _root;
    if (root == null) return;
    try {
      await File('${root.path}/client.json').delete();
    } on FileSystemException {
      // Nothing saved.
    }
  }

  void _createClient() {
    final clientId = _clientId = TdPlugin.instance.tdCreateClientId();
    debugPrint('[Telegram] Client $clientId created');
    unawaited(_saveClient(clientId));
    // TDLib emits its first authorization state in response to any request.
    unawaited(_sendQuietly(const td.GetOption(name: 'version')));
  }

  /// Carries on with [clientId], which TDLib still has open. It sends no
  /// update for a state it is already in, so the state is asked for. One
  /// TDLib no longer knows makes way for a new client.
  void _adopt(int clientId) {
    _clientId = clientId;
    debugPrint('[Telegram] Client $clientId taken over');
    unawaited(() async {
      try {
        _onAuthorizationState(
          await send<td.AuthorizationState>(const td.GetAuthorizationState()),
        );
      } catch (e) {
        debugPrint('[Telegram] Could not take client $clientId over: $e');
        if (!_disposed) _createClient();
      }
    }());
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
    final wasOnline = isOnline;
    _connectionState = state;
    if (!_connectionStates.isClosed) _connectionStates.add(state);
    if (isOnline != wasOnline && !_online.isClosed) _online.add(isOnline);
  }

  void _onAuthorizationState(td.AuthorizationState state) {
    debugPrint('[Telegram] Auth state → ${state.runtimeType}');
    _authState = state;
    if (!_authStates.isClosed) _authStates.add(state);

    switch (state) {
      case td.AuthorizationStateWaitTdlibParameters():
        unawaited(_configureOnce());
      case td.AuthorizationStateReady():
        if (!_ready.isCompleted) _ready.complete();
        // A drive app has no business showing its owner as "online" to
        // their contacts every time they browse files.
        unawaited(_setOption('online', const td.OptionValueBoolean(value: false)));
      case td.AuthorizationStateLoggingOut():
        _waitForSignIn();
      case td.AuthorizationStateClosed():
        _waitForSignIn();
        _failPending();
        if (!_disposed) _createClient();
      default:
        break;
    }
  }

  /// Makes [ready] wait for the next sign-in. Work already waiting keeps
  /// waiting on the same future, which the next sign-in completes.
  void _waitForSignIn() {
    if (_ready.isCompleted) _ready = Completer<void>();
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
      // The job can't tell a key it couldn't read from one that was never
      // made, and a new key would start the app's database over.
      if (role == TdRole.worker) {
        fatalError.value = 'The database key could not be read.';
        return;
      }
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
      // Another TDLib in this process, the background job's, hasn't let go
      // of the database yet. It is sound, so it is never started over.
      if (e.isDatabaseInUse) {
        fatalError.value = 'Telegram is still running in the background. Try again in a moment.';
        return;
      }
      // The job leaves the database as it is, whatever went wrong; the app
      // deals with it when it next opens.
      if (role == TdRole.worker) {
        fatalError.value = e.friendlyMessage;
        return;
      }
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

  Future<void> _sendQuietly(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await send<td.TdObject>(function, timeout: timeout);
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

  /// How long TDLib gets to take the request to close, and again to flush
  /// and close. With the receive loop's exit, it keeps [shutDown] inside the
  /// app's [_handOverTimeout].
  static const Duration _closeTimeout = Duration(seconds: 5);

  /// Closes TDLib and gives it up for another engine in this process: the
  /// background job ending, or handing over to the app. TDLib gets
  /// [_closeTimeout] to take the request and again to flush and close; then
  /// the receive loop stops and ownership is released, in that order, so
  /// the next owner never receives while this one still does. No new client
  /// is made after.
  Future<void> shutDown() async {
    _disposed = true;
    if (_clientId != null && _authState is! td.AuthorizationStateClosed) {
      final closed = Completer<void>();
      final watch = _authStates.stream.listen((state) {
        if (state is td.AuthorizationStateClosed && !closed.isCompleted) closed.complete();
      });
      await _sendQuietly(const td.Close(), timeout: _closeTimeout);
      await closed.future.timeout(_closeTimeout, onTimeout: () {});
      await watch.cancel();
    }
    await _forgetClient();
    await _receiver.stop();
    await _ownership?.release();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _receiver.stop();
    _failPending();
    await _updates.close();
    await _authStates.close();
    await _connectionStates.close();
    await _online.close();
    fatalError.dispose();
  }
}

/// The engine this container runs in. The background backup job overrides
/// it with [TdRole.worker].
final tdRoleProvider = Provider<TdRole>((ref) => TdRole.app);

final telegramClientProvider = Provider<TelegramClient>((ref) {
  final client = TelegramClient(
    ref.watch(secureStoreProvider),
    role: ref.watch(tdRoleProvider),
  );
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

/// Whether a change made now goes straight to Telegram; see
/// [TelegramClient.isOnline].
final telegramOnlineProvider = StreamProvider<bool>((ref) async* {
  final client = ref.watch(telegramClientProvider);
  yield client.isOnline;
  yield* client.onlineChanges;
});
