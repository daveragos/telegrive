import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Telegram whose thumbnail downloads finish only when a test says so.
class _Telegram extends FakeTelegram {
  final downloads = <int, Completer<td.File>>{};
  final cancels = <({int fileId, bool onlyIfPending})>[];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    switch (function) {
      case td.DownloadFile(:final fileId):
        return (downloads[fileId] = Completer<td.File>()).future;
      case td.CancelDownloadFile(:final fileId, :final onlyIfPending):
        cancels.add((fileId: fileId, onlyIfPending: onlyIfPending));
        return const td.Ok();
      default:
        return null;
    }
  }
}

void main() {
  late _Telegram telegram;
  late ProviderContainer container;

  setUp(() {
    telegram = _Telegram();
    container = ProviderContainer(
      overrides: [telegramClientProvider.overrideWithValue(telegram)],
    );
  });

  test('a thumbnail nobody waits for any more is called off', () async {
    addTearDown(container.dispose);
    final tile = container.listen(thumbnailPathProvider(5), (_, _) {});
    await pumpEventQueue();
    expect(telegram.downloads.keys, [5]);

    // The tile scrolls away before Telegram has sent it.
    tile.close();
    await container.pump();
    await pumpEventQueue();
    expect(telegram.cancels, [(fileId: 5, onlyIfPending: true)]);
  });

  test('a thumbnail that lands after its tile went is left quietly', () async {
    addTearDown(container.dispose);
    final printed = <String?>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = print);
    final tile = container.listen(thumbnailPathProvider(5), (_, _) {});
    await pumpEventQueue();

    // The tile scrolls away while TDLib is already sending the file, which
    // it then finishes.
    tile.close();
    await container.pump();
    telegram.downloads[5]!.complete(tdFile(5, path: '/thumbs/5.jpg', downloaded: true));
    await pumpEventQueue();

    expect(printed, isEmpty);
    expect(container.exists(thumbnailPathProvider(5)), isFalse);
  });

  test('a thumbnail that arrived is kept, and nothing is called off', () async {
    final tile = container.listen(thumbnailPathProvider(5), (_, _) {});
    await pumpEventQueue();
    telegram.downloads[5]!.complete(tdFile(5, path: '/thumbs/5.jpg', downloaded: true));
    expect(await container.read(thumbnailPathProvider(5).future), '/thumbs/5.jpg');

    tile.close();
    await container.pump();
    expect(container.exists(thumbnailPathProvider(5)), isTrue);

    container.dispose();
    await pumpEventQueue();
    expect(telegram.cancels, isEmpty);
  });
}
