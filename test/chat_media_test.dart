import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/import/data/chat_media.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

const _chat = 777;

td.Message _document(int id, String name, {int size = 1000}) =>
    documentMessage(id, '', fileName: name, mimeType: 'application/pdf', size: size)
        .copyWith(chatId: _chat);

/// A chat whose search answers two pages: three documents and a text, then
/// one PDF Telegram gave no name.
class _ChatTelegram extends FakeTelegram {
  final List<td.SearchChatMessages> searches = [];

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    if (function is! td.SearchChatMessages) return null;
    searches.add(function);
    return function.fromMessageId == 0
        ? td.FoundChatMessages(
            totalCount: 5,
            messages: [
              _document(504, 'Lease.pdf'),
              _document(503, 'Payslip.pdf').copyWith(canBeSaved: false),
              _document(502, 'Old contract.pdf', size: 2400),
              textMessage(501, 'Not a file').copyWith(chatId: _chat),
            ],
            nextFromMessageId: 501,
          )
        : td.FoundChatMessages(
            totalCount: 5,
            messages: [
              _document(
                500,
                '',
              ).copyWith(date: DateTime(2023, 3, 3, 18, 4, 12).millisecondsSinceEpoch ~/ 1000),
            ],
            nextFromMessageId: 0,
          );
  }
}

void main() {
  test('pages leave out what the drive has and what the chat protects', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _ChatTelegram();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(TestSession.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    // Saved before, so its name and size are already in the drive.
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'old',
        name: 'Old contract.pdf',
        mimeType: 'application/pdf',
        kind: FileKind.document,
        size: 2400,
        createdAt: DateTime(2023),
        modifiedAt: DateTime(2023),
      ),
      FilePartsCompanion.insert(fileId: 'old', partIndex: 0, messageId: 1, tdFileId: 1, size: 2400),
    );

    const source = (chatId: _chat, filter: ImportFilter.documents);
    container.listen(chatMediaProvider(source), (_, _) {});
    var state = await container.read(chatMediaProvider(source).future);
    expect(telegram.searches.single.filter, isA<td.SearchMessagesFilterDocument>());
    expect(state.items.map((i) => i.name), ['Lease.pdf']);
    expect(state.items.single.preview.id, 'chat:504');
    expect(state.hiddenSaved, 1);
    expect(state.hiddenProtected, 1);
    expect(state.totalCount, 5);
    expect(state.complete, isFalse);

    await container.read(chatMediaProvider(source).notifier).loadMore();
    state = container.read(chatMediaProvider(source)).requireValue;
    expect(telegram.searches.last.fromMessageId, 501);
    expect(state.items.map((i) => i.name), ['Lease.pdf', 'File 2023-03-03 18.04.12.pdf']);
    expect(state.complete, isTrue);

    // Nothing more to read.
    await container.read(chatMediaProvider(source).notifier).loadMore();
    expect(telegram.searches, hasLength(2));
  });
}
