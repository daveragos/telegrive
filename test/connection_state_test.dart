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
