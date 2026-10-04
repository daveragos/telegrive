import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the connection state is kept, replayed to late listeners and still an update', () async {
    final telegram = FakeTelegram();
    final updates = <td.TdObject>[];
    telegram.updates.listen(updates.add);
    expect(telegram.connectionState, isNull);

    telegram.setConnectionState(const td.ConnectionStateConnecting());
    expect(telegram.connectionState, isA<td.ConnectionStateConnecting>());

    // A listener that arrives late hears where things stand first.
    final seen = <td.ConnectionState>[];
    final listening = telegram.connectionStates.listen(seen.add);
    await settle();
    expect(seen, [isA<td.ConnectionStateConnecting>()]);

    telegram.setConnectionState(const td.ConnectionStateReady());
    await settle();
    expect(seen, [isA<td.ConnectionStateConnecting>(), isA<td.ConnectionStateReady>()]);
    expect(updates.whereType<td.UpdateConnectionState>(), hasLength(2));

    await listening.cancel();
    await telegram.dispose();
  });

  test('a change goes straight out only while Telegram is connected', () async {
    final telegram = FakeTelegram();
    // Before TDLib has said anything, changes go out as they always did.
    expect(telegram.isOnline, isTrue);
    final seen = <bool>[];
    final listening = telegram.onlineChanges.listen(seen.add);

    telegram.setConnectionState(const td.ConnectionStateWaitingForNetwork());
    telegram.setConnectionState(const td.ConnectionStateConnecting());
    expect(telegram.isOnline, isFalse);
    telegram.setConnectionState(const td.ConnectionStateUpdating());
    expect(telegram.isOnline, isTrue);
    telegram.setConnectionState(const td.ConnectionStateReady());
    await settle();

    // Each change once: connecting after waiting is still offline, and
    // ready after catching up is still online.
    expect(seen, [false, true]);
    await listening.cancel();
    await telegram.dispose();
  });

  test('telegramOnlineProvider starts from where the client stands', () async {
    final telegram = FakeTelegram()
      ..setConnectionState(const td.ConnectionStateConnecting());
    final container = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(telegram)],
    );
    addTearDown(container.dispose);
    container.listen(telegramOnlineProvider, (_, _) {});
    await settle();
    expect(container.read(telegramOnlineProvider).value, isFalse);

    telegram.setConnectionState(const td.ConnectionStateReady());
    await settle();
    expect(container.read(telegramOnlineProvider).value, isTrue);
  });

  test('connectionStateProvider follows the client', () async {
    final telegram = FakeTelegram();
    final container = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(telegram)],
    );
    addTearDown(container.dispose);
    container.listen(connectionStateProvider, (_, _) {});
    await settle();
    expect(container.read(connectionStateProvider).value, isNull);

    telegram.setConnectionState(const td.ConnectionStateWaitingForNetwork());
    await settle();
    await settle();
    expect(
      container.read(connectionStateProvider).value,
      isA<td.ConnectionStateWaitingForNetwork>(),
    );
  });
}
