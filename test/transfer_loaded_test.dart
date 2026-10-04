import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/transfers/data/transfer_queue.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _session = DriveSession(
  userId: 1,
  chatId: testChatId,
  channelTitle: 'Telegrive',
  firstName: 'A',
  lastName: '',
  phoneNumber: '',
  username: null,
  isPremium: false,
);

void main() {
  test('loaded waits for a drive, and again for the next one', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(FakeTelegram()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final createdAt = DateTime(2026, 10, 4, 9);
    await db.saveTransfers([
      TransferRow(
        id: 'report',
        kind: TransferKind.upload,
        status: TransferStatus.completed,
        name: 'report.pdf',
        mimeType: 'application/pdf',
        fileId: 'report',
        ownsSource: false,
        wifiOnly: false,
        totalBytes: 10,
        doneBytes: 10,
        partCount: 1,
        completedParts: 1,
        createdAt: createdAt,
        finishedAt: createdAt,
        origin: TransferOrigin.manual,
      ),
    ]);

    container.listen(transferQueueProvider, (_, _) {});
    final queue = container.read(transferQueueProvider.notifier);
    // Whether [future] completes within a moment.
    Future<bool> completes(Future<void> future) => Future.any([
      future.then((_) => true),
      Future.delayed(const Duration(milliseconds: 50), () => false),
    ]);

    // No drive is open, so there are no rows to wait for yet.
    final first = queue.loaded;
    expect(await completes(first), isFalse);

    container.read(driveSessionProvider.notifier).open(_session);
    await first.timeout(const Duration(seconds: 5));
    expect(container.read(transferQueueProvider).items.map((t) => t.id), ['report']);
    expect(await completes(queue.loaded), isTrue);

    // Signing out forgets the rows, and what asks again waits for the next
    // drive's.
    container.read(driveSessionProvider.notifier).close();
    expect(container.read(transferQueueProvider).items, isEmpty);
    final second = queue.loaded;
    expect(await completes(second), isFalse);

    container.read(driveSessionProvider.notifier).open(_session);
    await second.timeout(const Duration(seconds: 5));
    expect(container.read(transferQueueProvider).items.map((t) => t.id), ['report']);
  });
}
