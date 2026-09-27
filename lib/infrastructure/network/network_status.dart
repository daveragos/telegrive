import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../telegram/telegram_client.dart';

/// The phone's connection as Android reports it: whether there is internet
/// at all, and whether the bytes are paid for. Metered is Android's word and
/// it covers more than a mobile radio: a phone's hotspot is Wi-Fi to the
/// radio and mobile data to whoever pays the bill, and Android knows which.
@immutable
class NetworkState {
  const NetworkState({required this.online, required this.metered});

  /// One `{online, metered}` event from the `telegrive/network` channel.
  /// Anything else reads as [unknown], so a malformed event never blocks.
  factory NetworkState.fromEvent(Object? event) {
    if (event is! Map) return unknown;
    return NetworkState(
      online: event['online'] as bool? ?? unknown.online,
      metered: event['metered'] as bool? ?? unknown.metered,
    );
  }

  final bool online;
  final bool metered;

  /// What is assumed until Android has said otherwise, and everywhere it
  /// never will: other platforms and tests. Online and unmetered, so nothing
  /// waits on a signal that may not come.
  static const unknown = NetworkState(online: true, metered: false);

  /// How TDLib should book this connection's traffic. Metered means mobile
  /// whatever the radio, so a hotspot's bytes count against the data plan.
  td.NetworkType get telegramType {
    if (!online) return const td.NetworkTypeNone();
    return metered ? const td.NetworkTypeMobile() : const td.NetworkTypeWiFi();
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkState && other.online == online && other.metered == metered;

  @override
  int get hashCode => Object.hash(online, metered);

  @override
  String toString() => 'NetworkState(online: $online, metered: $metered)';
}

/// The one source of whether the phone is online and whether its data is
/// metered. Android's default-network callback feeds it event by event, so
/// a move from home Wi-Fi to a hotspot's Wi-Fi reaches Dart, where
/// connectivity_plus would report "still wifi" and say nothing.
///
/// It also tells TDLib the network type. That call is what makes TDLib drop
/// dead sockets and reconnect straight away, and TDLib books traffic under
/// it, so a metered connection is reported as mobile whatever the radio.
/// TDLib only takes the type once it has its parameters, so the current one
/// goes again the moment it is configured, and after each restart.
class NetworkStatus extends Notifier<NetworkState> {
  static const _channel = EventChannel('telegrive/network');

  /// Whether Android's network callback is there to listen to. Anywhere it
  /// isn't (other platforms, host tests) the state stays
  /// [NetworkState.unknown]; tests that mock the channel turn this on.
  @visibleForTesting
  static bool onAndroid = !kIsWeb && Platform.isAndroid;

  // Mirrors [state], which cannot be read while build() is still running.
  NetworkState _network = NetworkState.unknown;
  bool _heard = false;
  bool _telegramConfigured = false;

  @override
  NetworkState build() {
    if (!onAndroid) return NetworkState.unknown;
    final events = _channel
        .receiveBroadcastStream()
        .map(NetworkState.fromEvent)
        .distinct()
        .listen(_onNetwork, onError: (Object e) => debugPrint('[Network] $e'));
    ref.onDispose(events.cancel);
    ref.listen<AsyncValue<td.AuthorizationState>>(
      authStateProvider,
      (_, next) => _onAuthState(next.value),
      fireImmediately: true,
    );
    return _network;
  }

  void _onNetwork(NetworkState next) {
    _network = next;
    _heard = true;
    state = next;
    _tellTelegram();
  }

  void _onAuthState(td.AuthorizationState? auth) {
    final configured =
        auth != null && auth is! td.AuthorizationStateWaitTdlibParameters;
    if (configured == _telegramConfigured) return;
    _telegramConfigured = configured;
    if (configured) _tellTelegram();
  }

  /// Only what Android actually said: a guess is no better than the default
  /// TDLib starts with.
  void _tellTelegram() {
    if (!_heard || !_telegramConfigured) return;
    unawaited(
      ref.read(telegramClientProvider).setNetworkType(_network.telegramType),
    );
  }
}

final networkStatusProvider = NotifierProvider<NetworkStatus, NetworkState>(
  NetworkStatus.new,
);
