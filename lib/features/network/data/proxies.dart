import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../domain/proxy_link.dart';

/// What the last ping of a saved proxy said.
sealed class ProxyLatency {
  const ProxyLatency();
}

/// A ping is on its way.
final class LatencyChecking extends ProxyLatency {
  const LatencyChecking();
}

/// The proxy answered in [time].
final class LatencyMeasured extends ProxyLatency {
  const LatencyMeasured(this.time);

  final Duration time;
}

/// The proxy didn't answer, or Telegram couldn't reach it through it.
final class LatencyFailed extends ProxyLatency {
  const LatencyFailed();
}

/// A proxy TDLib keeps in its encrypted database, as the app shows it.
@immutable
class ProxyEntry {
  const ProxyEntry({
    required this.id,
    required this.server,
    required this.port,
    required this.kind,
    required this.enabled,
    required this.lastUsed,
    this.latency,
  });

  final int id;
  final String server;
  final int port;
  final ProxyKind kind;

  /// Whether Telegram connects through it now. At most one is.
  final bool enabled;

  /// When Telegram last connected through it, or null for never.
  final DateTime? lastUsed;

  /// What its last ping said, or null when it hasn't been pinged.
  final ProxyLatency? latency;

  String get label => proxyLabel(server, port);
}

/// The saved proxies, newest used first, and the ways to change which one
/// Telegram connects through. Everything lives in TDLib, which keeps it
/// encrypted and needs it before sign-in as much as after, so nothing is
/// stored here; each change reads the list back from TDLib.
///
/// The list is read once TDLib has its parameters, since it answers
/// nothing before that, and again whenever it is restarted.
class ProxyController extends AsyncNotifier<List<ProxyEntry>> {
  static const _pingTimeout = Duration(seconds: 10);

  /// Ping results by proxy id. They outlive each reload of the list, which
  /// would otherwise forget them every time a proxy is switched.
  final Map<int, ProxyLatency> _latency = {};

  /// TDLib's own rows, for matching a link against what is saved.
  List<td.Proxy> _saved = const [];

  /// Read before the first await of each change: closing the sheet can
  /// dispose this while TDLib is still answering, and the answer is still
  /// wanted.
  TelegramClient get _client => ref.read(telegramClientProvider);

  @override
  Future<List<ProxyEntry>> build() async {
    final configured = ref.watch(
      authStateProvider.select((auth) => telegramConfigured(auth.value)),
    );
    if (!configured) {
      _saved = const [];
      return const [];
    }
    return _load(_client);
  }

  Future<List<ProxyEntry>> _load(TelegramClient client) async {
    final proxies = await client.send<td.Proxies>(const td.GetProxies());
    // Never-used proxies tie at 0; the one added last goes first.
    _saved = [...proxies.proxies]
      ..sort((a, b) {
        final byUse = b.lastUsedDate.compareTo(a.lastUsedDate);
        return byUse != 0 ? byUse : b.id.compareTo(a.id);
      });
    return _entries();
  }

  /// The saved proxies of the kinds Telegrive adds; TDLib's HTTP proxies
  /// never come from here.
  List<ProxyEntry> _entries() => [
    for (final proxy in _saved)
      if (_kindOf(proxy.type) case final kind?)
        ProxyEntry(
          id: proxy.id,
          server: proxy.server,
          port: proxy.port,
          kind: kind,
          enabled: proxy.isEnabled,
          lastUsed: proxy.lastUsedDate == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(proxy.lastUsedDate * 1000),
          latency: _latency[proxy.id],
        ),
  ];

  Future<void> _reload(TelegramClient client) async {
    final entries = await _load(client);
    if (ref.mounted) state = AsyncData(entries);
  }

  /// Connects through [link]. A saved proxy with the same server, port and
  /// kind is switched on rather than added twice, with the link's secret or
  /// login when they differ, since a link is how a changed secret arrives.
  Future<void> connect(ProxyLink link) async {
    final client = _client;
    await _load(client);
    final type = link.toTd();
    final match = _saved
        .where(
          (p) => p.server == link.server && p.port == link.port && _kindOf(p.type) == link.kind,
        )
        .firstOrNull;
    final int id;
    if (match == null) {
      final added = await client.send<td.Proxy>(
        td.AddProxy(server: link.server, port: link.port, enable: true, type: type),
      );
      id = added.id;
    } else if (_sameType(match.type, type)) {
      await client.send<td.Ok>(td.EnableProxy(proxyId: match.id));
      id = match.id;
    } else {
      final edited = await client.send<td.Proxy>(
        td.EditProxy(
          proxyId: match.id,
          server: link.server,
          port: link.port,
          enable: true,
          type: type,
        ),
      );
      id = edited.id;
    }
    _latency.remove(id);
    await _reload(client);
    unawaited(ping(id));
  }

  /// Connects through the saved proxy [id].
  Future<void> enable(int id) async {
    final client = _client;
    await client.send<td.Ok>(td.EnableProxy(proxyId: id));
    await _reload(client);
  }

  /// Connects to Telegram directly, keeping the saved proxies.
  Future<void> useDirect() async {
    final client = _client;
    await client.send<td.Ok>(const td.DisableProxy());
    await _reload(client);
  }

  /// Forgets the saved proxy [id]; when it was the one in use, Telegram
  /// connects directly.
  Future<void> remove(int id) async {
    final client = _client;
    await client.send<td.Ok>(td.RemoveProxy(proxyId: id));
    _latency.remove(id);
    await _reload(client);
  }

  /// Pings every saved proxy at once, for a list that is about to be shown.
  Future<void> pingAll() async {
    final List<ProxyEntry> entries;
    try {
      entries = await future;
    } on TelegramException {
      // The list didn't load, so there is nothing to ping.
      return;
    }
    await Future.wait([for (final entry in entries) ping(entry.id)]);
  }

  /// Measures how long Telegram takes to answer through proxy [id]. A ping
  /// can hang on a proxy that swallows traffic, so after ten seconds it
  /// counts as no answer; the client reports that as a TelegramException
  /// too.
  Future<void> ping(int id) async {
    // Nobody shows the list any more.
    if (!ref.mounted) return;
    final client = _client;
    _setLatency(id, const LatencyChecking());
    try {
      final took = await client.send<td.Seconds>(td.PingProxy(proxyId: id), timeout: _pingTimeout);
      _setLatency(id, LatencyMeasured(Duration(milliseconds: (took.seconds * 1000).round())));
    } on TelegramException {
      _setLatency(id, const LatencyFailed());
    }
  }

  void _setLatency(int id, ProxyLatency latency) {
    _latency[id] = latency;
    if (ref.mounted && state.hasValue) state = AsyncData(_entries());
  }

  static ProxyKind? _kindOf(td.ProxyType type) => switch (type) {
    td.ProxyTypeMtproto() => ProxyKind.mtproto,
    td.ProxyTypeSocks5() => ProxyKind.socks5,
    _ => null,
  };

  static bool _sameType(td.ProxyType a, td.ProxyType b) => switch ((a, b)) {
    (td.ProxyTypeMtproto(secret: final x), td.ProxyTypeMtproto(secret: final y)) => x == y,
    (
      td.ProxyTypeSocks5(username: final u1, password: final p1),
      td.ProxyTypeSocks5(username: final u2, password: final p2),
    ) =>
      u1 == u2 && p1 == p2,
    _ => false,
  };
}

/// Whether TDLib has its parameters, the point from which it answers
/// requests, proxies included.
bool telegramConfigured(td.AuthorizationState? auth) =>
    auth != null && auth is! td.AuthorizationStateWaitTdlibParameters;

/// The saved proxies, read while something shows them.
final proxiesProvider = AsyncNotifierProvider.autoDispose<ProxyController, List<ProxyEntry>>(
  ProxyController.new,
);

/// The proxy Telegram connects through, or null for a direct connection
/// (or while the list is still being read).
final enabledProxyProvider = Provider.autoDispose<ProxyEntry?>(
  (ref) => ref.watch(proxiesProvider).value?.where((p) => p.enabled).firstOrNull,
);
