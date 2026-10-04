import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/network/data/proxies.dart';
import 'package:telegrive/features/network/domain/proxy_link.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// TDLib's proxy list: kept in [proxies], at most one enabled, with pings
/// that answer in 240 ms unless the proxy is [unreachable]. With
/// [refuseNew], it turns down every new proxy, the way TDLib does a secret
/// it can't read.
class _FakeTelegram extends FakeTelegram {
  _FakeTelegram(this.proxies);

  final List<td.Proxy> proxies;
  final sent = <td.TdFunction>[];
  final unreachable = <int>{};
  bool refuseNew = false;
  var _nextId = 10;

  void _enableOnly(int? id) {
    for (final (index, proxy) in proxies.indexed) {
      proxies[index] = proxy.copyWith(isEnabled: proxy.id == id);
    }
  }

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    sent.add(function);
    switch (function) {
      case td.GetProxies():
        return td.Proxies(proxies: [...proxies]);
      case td.AddProxy(:final server, :final port, :final enable, :final type):
        if (refuseNew) throw const TelegramException(400, 'Unsupported proxy secret');
        final proxy = td.Proxy(
          id: _nextId++,
          server: server,
          port: port,
          lastUsedDate: 0,
          isEnabled: false,
          type: type,
        );
        proxies.add(proxy);
        if (enable) _enableOnly(proxy.id);
        return proxies.last;
      case td.EditProxy(:final proxyId, :final server, :final port, :final enable, :final type):
        final index = proxies.indexWhere((p) => p.id == proxyId);
        proxies[index] = proxies[index].copyWith(server: server, port: port, type: type);
        if (enable) _enableOnly(proxyId);
        return proxies[index];
      case td.EnableProxy(:final proxyId):
        _enableOnly(proxyId);
        return const td.Ok();
      case td.DisableProxy():
        _enableOnly(null);
        return const td.Ok();
      case td.RemoveProxy(:final proxyId):
        proxies.removeWhere((p) => p.id == proxyId);
        return const td.Ok();
      case td.PingProxy(:final proxyId):
        if (unreachable.contains(proxyId)) {
          throw const TelegramException(400, 'Proxy is unreachable');
        }
        return const td.Seconds(seconds: 0.2404);
      default:
        return null;
    }
  }
}

td.Proxy _proxy(
  int id,
  String server, {
  int port = 443,
  int lastUsed = 0,
  bool enabled = false,
  td.ProxyType type = const td.ProxyTypeMtproto(secret: 'ee00'),
}) => td.Proxy(
  id: id,
  server: server,
  port: port,
  lastUsedDate: lastUsed,
  isEnabled: enabled,
  type: type,
);

void main() {
  late _FakeTelegram telegram;
  late ProviderContainer container;

  /// A container whose TDLib has its parameters, as it does from the
  /// first sign-in screen on.
  Future<void> start(List<td.Proxy> proxies) async {
    telegram = _FakeTelegram(proxies);
    telegram.receive(
      const td.UpdateAuthorizationState(
        authorizationState: td.AuthorizationStateWaitPhoneNumber(),
      ).toJson(),
    );
    container = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(telegram)],
    );
    addTearDown(container.dispose);
    container.listen(proxiesProvider, (_, _) {});
    await container.read(proxiesProvider.future);
  }

  List<ProxyEntry> entries() => container.read(proxiesProvider).value!;
  ProxyController proxies() => container.read(proxiesProvider.notifier);
  Iterable<T> sent<T>() => telegram.sent.whereType<T>();

  test('saved proxies come newest used first', () async {
    await start([
      _proxy(1, 'old.example.org', lastUsed: 1_700_000_000),
      _proxy(2, 'never.example.org'),
      _proxy(3, 'recent.example.org', lastUsed: 1_750_000_000, enabled: true),
      _proxy(
        4,
        'socks.example.org',
        port: 1080,
        lastUsed: 1_720_000_000,
        type: const td.ProxyTypeSocks5(username: '', password: ''),
      ),
    ]);

    expect([for (final e in entries()) e.server], [
      'recent.example.org',
      'socks.example.org',
      'old.example.org',
      'never.example.org',
    ]);
    expect(entries().first.enabled, isTrue);
    expect(entries().first.lastUsed, DateTime.fromMillisecondsSinceEpoch(1_750_000_000 * 1000));
    expect(entries()[1].kind, ProxyKind.socks5);
    expect(entries()[1].label, 'socks.example.org:1080');
    expect(entries().last.lastUsed, isNull);
    expect(container.read(enabledProxyProvider)?.id, 3);
  });

  test('a link for a saved proxy switches it on instead of adding it twice', () async {
    await start([_proxy(1, '1.2.3.4', lastUsed: 1_700_000_000)]);

    await proxies().connect(const ProxyLink('1.2.3.4', 443, ProxyKind.mtproto, secret: 'ee00'));

    expect(sent<td.AddProxy>(), isEmpty);
    expect(sent<td.EnableProxy>().single.proxyId, 1);
    expect(entries().single.enabled, isTrue);
  });

  test('a saved proxy with a new secret gets the new one', () async {
    await start([_proxy(1, '1.2.3.4')]);

    await proxies().connect(const ProxyLink('1.2.3.4', 443, ProxyKind.mtproto, secret: 'ee11'));

    expect(sent<td.AddProxy>(), isEmpty);
    final edit = sent<td.EditProxy>().single;
    expect(edit.proxyId, 1);
    expect(edit.enable, isTrue);
    expect((edit.type as td.ProxyTypeMtproto).secret, 'ee11');
    expect(entries(), hasLength(1));
  });

  test('a new proxy is added, switched on and pinged', () async {
    await start([_proxy(1, '1.2.3.4')]);

    await proxies().connect(const ProxyLink('5.6.7.8', 1080, ProxyKind.socks5));
    await pumpEventQueue();

    final add = sent<td.AddProxy>().single;
    expect(add.server, '5.6.7.8');
    expect(add.port, 1080);
    expect(add.enable, isTrue);
    expect(add.type, isA<td.ProxyTypeSocks5>());
    final added = entries().firstWhere((e) => e.server == '5.6.7.8');
    expect(added.enabled, isTrue);
    expect(sent<td.PingProxy>().single.proxyId, added.id);
    expect((added.latency! as LatencyMeasured).time, const Duration(milliseconds: 240));
  });

  test('the same address as another kind of proxy is a different proxy', () async {
    await start([_proxy(1, '1.2.3.4', port: 1080)]);

    await proxies().connect(const ProxyLink('1.2.3.4', 1080, ProxyKind.socks5));

    expect(sent<td.AddProxy>(), hasLength(1));
    expect(sent<td.EnableProxy>(), isEmpty);
  });

  test('a ping that fails marks the proxy as not answering', () async {
    await start([_proxy(1, 'up.example.org'), _proxy(2, 'down.example.org')]);
    telegram.unreachable.add(2);

    await proxies().pingAll();

    final byId = {for (final e in entries()) e.id: e};
    expect((byId[1]!.latency! as LatencyMeasured).time, const Duration(milliseconds: 240));
    expect(byId[2]!.latency, isA<LatencyFailed>());
  });

  test('a ping result outlives the next reload', () async {
    await start([_proxy(1, 'up.example.org')]);
    await proxies().pingAll();

    await proxies().enable(1);

    expect(entries().single.latency, isA<LatencyMeasured>());
  });

  test('direct connection sends DisableProxy and keeps the list', () async {
    await start([_proxy(1, '1.2.3.4', enabled: true)]);

    await proxies().useDirect();

    expect(sent<td.DisableProxy>(), hasLength(1));
    expect(entries().single.enabled, isFalse);
    expect(container.read(enabledProxyProvider), isNull);
  });

  test('remove forgets the proxy', () async {
    await start([_proxy(1, '1.2.3.4'), _proxy(2, '5.6.7.8')]);

    await proxies().remove(1);

    expect(sent<td.RemoveProxy>().single.proxyId, 1);
    expect([for (final e in entries()) e.id], [2]);
  });

  test('Telegram refusing a proxy surfaces as a TelegramException', () async {
    await start(const []);
    telegram.refuseNew = true;

    await expectLater(
      proxies().connect(const ProxyLink('1.2.3.4', 443, ProxyKind.mtproto, secret: 'zz')),
      throwsA(isA<TelegramException>()),
    );
    expect(entries(), isEmpty);
  });

  test('nothing is asked before TDLib has its parameters', () async {
    final quiet = _FakeTelegram([_proxy(1, '1.2.3.4')]);
    final early = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(quiet)],
    );
    addTearDown(early.dispose);
    early.listen(proxiesProvider, (_, _) {});

    expect(await early.read(proxiesProvider.future), isEmpty);
    expect(quiet.sent, isEmpty);
  });
}
