import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

void main() {
  test('a reply listing messages by id leaves out those that are gone', () {
    final reply = <String, dynamic>{
      '@type': 'messages',
      'total_count': 1,
      'messages': [null, textMessage(7 << 20, 'kept').toJson(), null],
    };

    final object = td.convertMapToObject(TelegramClient.withoutGoneMessages(reply));

    expect(object, isA<td.Messages>());
    expect([for (final message in (object! as td.Messages).messages) message.id], [7 << 20]);
  });

  test('a reply with nothing gone passes as it is', () {
    final reply = <String, dynamic>{'@type': 'messages', 'total_count': 0, 'messages': []};

    expect(TelegramClient.withoutGoneMessages(reply), same(reply));
  });
}
