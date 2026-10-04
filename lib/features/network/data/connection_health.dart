import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/telegram/telegram_client.dart';

/// Whether Telegram can be reached from here, as far as it matters to
/// someone looking at the screen.
enum ConnectionHealth {
  /// Connected, or still within a fair time of connecting.
  ok,

  /// The phone has no network, which is no fault of Telegram's.
  noNetwork,

  /// The phone has a network, but Telegram hasn't answered on it for a
  /// while: often a network that blocks Telegram.
  stuck,

  /// The same, through the proxy that is switched on.
  proxyStuck,
}

/// Turns TDLib's connection states into [ConnectionHealth]. Connecting is
/// normal for a few seconds, so only connecting for [after] while Android
/// reports a network counts as stuck; a slow network stays quiet that
/// long, and Ready or Updating clears it at once. Moving between connecting
/// directly and through a proxy starts the clock again, since that is a
/// different route being tried.
class ConnectionHealthTracker {
  ConnectionHealthTracker({
    required Stream<td.ConnectionState> states,
    required Stream<bool> hasNetwork,
    this.after = const Duration(seconds: 20),
  }) {
    _subscriptions = [
      states.listen((state) {
        _state = state;
        _evaluate();
      }),
      hasNetwork.listen((online) {
        _online = online;
        _evaluate();
      }),
    ];
  }

  final Duration after;

  late final List<StreamSubscription<Object?>> _subscriptions;
  final _changes = StreamController<ConnectionHealth>.broadcast();
  td.ConnectionState? _state;

  /// Until Android says otherwise there is a network, as NetworkStatus
  /// assumes, so nothing waits on a signal that may never come.
  bool _online = true;
  Timer? _timer;

  /// Whether the timer, or the stuck state it led to, is about going
  /// through a proxy.
  bool? _throughProxy;

  ConnectionHealth _health = ConnectionHealth.ok;
  ConnectionHealth get health => _health;

  /// Each change of [health], never the same value twice running.
  Stream<ConnectionHealth> get changes => _changes.stream;

  void _evaluate() {
    final state = _state;
    final connecting = state is td.ConnectionStateConnecting ||
        state is td.ConnectionStateConnectingToProxy;
    if (state is td.ConnectionStateWaitingForNetwork || (connecting && !_online)) {
      _stopClock();
      _set(ConnectionHealth.noNetwork);
      return;
    }
    if (!connecting) {
      _stopClock();
      _set(ConnectionHealth.ok);
      return;
    }
    final throughProxy = state is td.ConnectionStateConnectingToProxy;
    if (_throughProxy == throughProxy) return;
    _stopClock();
    _throughProxy = throughProxy;
    _set(ConnectionHealth.ok);
    _timer = Timer(after, () {
      _timer = null;
      _set(throughProxy ? ConnectionHealth.proxyStuck : ConnectionHealth.stuck);
    });
  }

  void _stopClock() {
    _timer?.cancel();
    _timer = null;
    _throughProxy = null;
  }

  void _set(ConnectionHealth health) {
    if (health == _health) return;
    _health = health;
    if (!_changes.isClosed) _changes.add(health);
  }

  Future<void> dispose() async {
    _stopClock();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }
}

/// What [state] says once waiting has gone on long enough, without waiting
/// for the tracker's clock: for a screen whose own request to Telegram has
/// already timed out.
ConnectionHealth healthAfterWaiting(td.ConnectionState? state) => switch (state) {
  td.ConnectionStateConnecting() => ConnectionHealth.stuck,
  td.ConnectionStateConnectingToProxy() => ConnectionHealth.proxyStuck,
  td.ConnectionStateWaitingForNetwork() => ConnectionHealth.noNetwork,
  _ => ConnectionHealth.ok,
};

/// Whether Telegram can be reached, from TDLib's connection state and
/// whether Android reports a network.
class ConnectionHealthNotifier extends Notifier<ConnectionHealth> {
  @override
  ConnectionHealth build() {
    final network = StreamController<bool>();
    final tracker = ConnectionHealthTracker(
      states: ref.watch(telegramClientProvider).connectionStates,
      hasNetwork: network.stream,
    );
    final changes = tracker.changes.listen((health) => state = health);
    ref.listen<bool>(
      networkStatusProvider.select((network) => network.online),
      (_, online) => network.add(online),
      fireImmediately: true,
    );
    ref.onDispose(() async {
      await changes.cancel();
      await tracker.dispose();
      await network.close();
    });
    return tracker.health;
  }
}

final connectionHealthProvider = NotifierProvider<ConnectionHealthNotifier, ConnectionHealth>(
  ConnectionHealthNotifier.new,
);
