import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// A channel that turns caption edits down as if the message weren't there
/// while [refusing], though it still is.
class _Channel extends FakeTelegram {
  bool refusing = false;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (refusing && function is td.EditMessageCaption) {
      throw const TelegramException(400, 'MESSAGE_ID_INVALID');
    }
    return null;
  }
}

/// An item whose message went from the channel outside this phone, while
/// the index still held it: an edit to it lets it go and carries on, as
/// tidying up Photo backup needs. Telegram can also turn an edit away that
/// way for a message it still has, which is then swapped for its own copy.
void main() {
  late AppDatabase db;
  late _Channel telegram;
  late ProviderContainer container;
  late DriveRepository repository;

  Future<void> receive(td.Message message) async {
    telegram.messages[message.id] = message;
    await repository.ingest(message);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    telegram = _Channel();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    repository = container.read(driveRepositoryProvider);
    await receive(textMessage(1, '📁 Work\ntgrf1:{"id":"work","n":"Work","ct":1700000000000}'));
    await receive(textMessage(2, '📁 Home\ntgrf1:{"id":"home","n":"Home","ct":1700000000000}'));
    await receive(
      documentMessage(
        10,
        'Notes.pdf\ntgr1:{"id":"a","n":"Notes.pdf","f":"work",'
        '"m":"application/pdf","s":9,"ct":1700000000000}',
        fileName: 'Notes.pdf',
        mimeType: 'application/pdf',
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('moving a file whose message is gone lets it go from the index', () async {
    final file = (await repository.fileById('a'))!;
    telegram.messages.remove(10);

    await repository.moveFiles([file], 'home');

    expect(await repository.fileById('a'), isNull);
  });

  test('trashing a folder whose message is gone lets it go from the index', () async {
    final folder = (await repository.folderById('work'))!;
    telegram.messages.remove(1);

    await repository.trash(folders: [folder]);

    expect(await repository.folderById('work'), isNull);
  });

  test("a file Telegram won't edit though it still has it is swapped for a copy", () async {
    final file = (await repository.fileById('a'))!;
    telegram.refusing = true;

    await repository.moveFiles([file], 'home');

    final moved = (await repository.fileById('a'))!;
    expect(moved.folderId, 'home');
    expect(telegram.messages.containsKey(10), isFalse);
    final parts = await repository.partsOf('a');
    expect(parts.single.messageId, isNot(10));
  });
}
