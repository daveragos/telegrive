import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/auth/data/auth_controller.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

const _chatId = -1001234567890;

/// A channel an earlier drive on this phone used.
const _oldChatId = -1009876543210;

/// Accepts the log-out and keeps what was sent.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram() : super(SecureStore());

  final List<td.TdFunction> sent = [];

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    sent.add(function);
    if (function is td.LogOut) return const td.Ok() as T;
    throw UnsupportedError('$function');
  }
}

void main() {
  test('signing out clears the sync checkpoints with the index', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'drive_chat_1': _chatId,
      'synced_upto_$_chatId': 900,
      'full_sync_$_chatId': DateTime(2026, 9, 26).millisecondsSinceEpoch,
      'synced_upto_$_oldChatId': 40,
      'theme_mode': 'dark',
      'backup_enabled': true,
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final prefs = container.read(preferencesProvider);

    container.read(driveSessionProvider.notifier).open(
      const DriveSession(
        userId: 1,
        chatId: _chatId,
        channelTitle: 'Telegrive',
        firstName: 'A',
        lastName: '',
        phoneNumber: '',
        username: null,
        isPremium: false,
      ),
    );
    final now = DateTime(2026, 9, 26);
    await db.upsertFolder(
      FoldersCompanion.insert(
        id: 'docs',
        name: 'Docs',
        messageId: 1,
        createdAt: now,
        modifiedAt: now,
      ),
    );
    await db.markAssetBackedUp('asset-1', null);
    expect(prefs.syncedChatIds, {_chatId, _oldChatId});

    await container.read(authControllerProvider.notifier).signOut();

    expect(telegram.sent.whereType<td.LogOut>(), hasLength(1));
    expect(container.read(driveSessionProvider), isNull);
    expect(await db.select(db.folders).get(), isEmpty);
    expect(await db.backupAssetMap(), isEmpty);

    // Signing in again reads the whole channel instead of trusting
    // checkpoints for an index that is gone.
    expect(prefs.lastFullSync(_chatId), isNull);
    expect(prefs.lastSyncedMessageId(_chatId), 0);
    expect(prefs.lastSyncedMessageId(_oldChatId), 0);
    expect(prefs.syncedChatIds, isEmpty);

    // App settings and the channel remembered for the account stay.
    expect(prefs.driveChatId(1), _chatId);
    expect(prefs.themeMode, ThemeMode.dark);
    expect(prefs.backupEnabled, isTrue);
  });
}
