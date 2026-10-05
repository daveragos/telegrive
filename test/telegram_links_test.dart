import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/telegram/telegram_links.dart';

void main() {
  test('a channel post opens in the Telegram app by its own numbers', () {
    final link = TelegramLinks.post(-1004450027006, 1822 << 20);

    expect(link.toString(), 'tg://privatepost?channel=4450027006&post=1822');
  });
}
