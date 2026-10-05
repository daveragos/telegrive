import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';

void main() {
  const chatId = -100;

  Future<Preferences> prefsWith(Map<String, Object> stored) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    return Preferences(await SharedPreferences.getInstance());
  }

  final everything = <String, Object>{
    'synced_upto_$chatId': 900,
    'full_sync_$chatId': 1,
    'indexed_with_$chatId': 4,
    'forward_filing_from_$chatId': 900,
    'drive_card_$chatId': 5,
    'index_copy_at_$chatId': 1,
    'index_copy_print_$chatId': 7,
  };

  test('reading the index again keeps what the phone knows of the channel', () async {
    final prefs = await prefsWith(everything);

    await prefs.clearSyncState(chatId);

    expect(prefs.lastSyncedMessageId(chatId), 0);
    expect(prefs.lastFullSync(chatId), isNull);
    expect(prefs.driveCardId(chatId), 5);
    expect(prefs.indexCopyPrint(chatId), 7);
    expect(prefs.indexCopyAt(chatId), isNotNull);
  });

  test('forgetting a channel forgets all of it, and it is counted until then', () async {
    final prefs = await prefsWith({'drive_card_$chatId': 5});
    expect(prefs.syncedChatIds, {chatId});

    final full = await prefsWith(everything);
    await full.forgetChannel(chatId);

    expect(full.driveCardId(chatId), isNull);
    expect(full.indexCopyAt(chatId), isNull);
    expect(full.lastFullSync(chatId), isNull);
    expect(full.syncedChatIds, isEmpty);
  });
}
