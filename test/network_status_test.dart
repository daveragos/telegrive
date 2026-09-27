import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/infrastructure/network/network_status.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Records the network types TDLib is told, and lets a test move the
/// authorization state without TDLib.
class _FakeTelegram extends FakeTelegram {
  final types = <td.NetworkType>[];
  final auth = StreamController<td.AuthorizationState>.broadcast();

  @override
  Stream<td.AuthorizationState> get authStates => auth.stream;

  @override
  Future<void> setNetworkType(td.NetworkType type) async => types.add(type);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = EventChannel('telegrive/network');

  group('NetworkState', () {
    test('reads what Android sends and shrugs off anything else', () {
      expect(
        NetworkState.fromEvent({'online': true, 'metered': true}),
        const NetworkState(online: true, metered: true),
      );
      expect(
        NetworkState.fromEvent({'online': false, 'metered': false}),
        const NetworkState(online: false, metered: false),
      );
      expect(NetworkState.fromEvent(<Object?, Object?>{}), NetworkState.unknown);
      expect(NetworkState.fromEvent('offline'), NetworkState.unknown);
      expect(NetworkState.fromEvent(null), NetworkState.unknown);
    });

    test('two states with the same answers are the same state', () {
      const offline = NetworkState(online: false, metered: false);
      expect(offline, const NetworkState(online: false, metered: false));
      expect(offline.hashCode, const NetworkState(online: false, metered: false).hashCode);
      expect(offline, isNot(NetworkState.unknown));
      expect({offline, NetworkState.fromEvent({'online': false, 'metered': false})}, hasLength(1));
    });

    test('TDLib books metered traffic as mobile, whatever the radio', () {
      expect(const NetworkState(online: true, metered: false).telegramType, isA<td.NetworkTypeWiFi>());
      expect(const NetworkState(online: true, metered: true).telegramType, isA<td.NetworkTypeMobile>());
      expect(const NetworkState(online: false, metered: true).telegramType, isA<td.NetworkTypeNone>());
    });
  });

  group('NetworkStatus', () {
    final onAndroid = NetworkStatus.onAndroid;
    late _FakeTelegram telegram;
    late ProviderContainer container;
    MockStreamHandlerEventSink? sink;
    var listens = 0;

    /// Lets platform messages and provider updates go round.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    void start({
      bool android = true,
      void Function(MockStreamHandlerEventSink events)? onListen,
    }) {
      NetworkStatus.onAndroid = android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, events) {
            listens++;
            sink = events;
            onListen?.call(events);
          },
          onCancel: (_) => sink = null,
        ),
      );
      telegram = _FakeTelegram();
      container = ProviderContainer(
        overrides: [telegramClientProvider.overrideWithValue(telegram)],
      );
      container.listen(networkStatusProvider, (_, _) {});
    }

    setUp(() {
      listens = 0;
      sink = null;
    });

    tearDown(() async {
      container.dispose();
      await telegram.auth.close();
      NetworkStatus.onAndroid = onAndroid;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    });

    NetworkState state() => container.read(networkStatusProvider);

    test('off Android it stays unknown and never asks the phone', () async {
      start(android: false);
      await settle();
      expect(state(), NetworkState.unknown);
      expect(listens, 0);
    });

    test('follows what Android reports, once per change', () async {
      start();
      await settle();
      expect(listens, 1);
      expect(state(), NetworkState.unknown);
      final seen = <NetworkState>[];
      container.listen(networkStatusProvider, (_, next) => seen.add(next));

      sink!.success({'online': true, 'metered': true});
      sink!.success({'online': true, 'metered': true});
      sink!.success({'online': false, 'metered': false});
      sink!.success({'online': true, 'metered': false});
      await settle();
      expect(seen, const [
        NetworkState(online: true, metered: true),
        NetworkState(online: false, metered: false),
        NetworkState(online: true, metered: false),
      ]);
      expect(state(), const NetworkState(online: true, metered: false));
    });

    test('tells TDLib the type once it is configured, then on every change', () async {
      start();
      await settle();
      sink!.success({'online': true, 'metered': true});
      await settle();
      // TDLib only takes the type once it has its parameters.
      expect(telegram.types, isEmpty);

      telegram.auth.add(const td.AuthorizationStateWaitPhoneNumber());
      await settle();
      expect(telegram.types, [isA<td.NetworkTypeMobile>()]);

      // The same again is not a change; the two that follow are.
      sink!.success({'online': true, 'metered': true});
      sink!.success({'online': true, 'metered': false});
      sink!.success({'online': false, 'metered': false});
      await settle();
      expect(telegram.types, [
        isA<td.NetworkTypeMobile>(),
        isA<td.NetworkTypeWiFi>(),
        isA<td.NetworkTypeNone>(),
      ]);

      // Signing out restarts TDLib, which starts over without a network type.
      telegram.auth.add(const td.AuthorizationStateWaitTdlibParameters());
      await settle();
      telegram.auth.add(const td.AuthorizationStateWaitPhoneNumber());
      await settle();
      expect(telegram.types, hasLength(4));
      expect(telegram.types.last, isA<td.NetworkTypeNone>());
    });

    test('without the callback it stays unknown and tells TDLib nothing', () async {
      start(onListen: (events) => events.error(code: 'unavailable', message: 'no callback'));
      await settle();
      expect(state(), NetworkState.unknown);
      telegram.auth.add(const td.AuthorizationStateWaitPhoneNumber());
      await settle();
      expect(telegram.types, isEmpty);
    });
  });
}
