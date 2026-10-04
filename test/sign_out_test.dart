import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/auth/data/auth_controller.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/photos/data/photos_visibility.dart';
import 'package:telegrive/features/trash/data/pending_deletes.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('sign_out_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => support.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
    support.deleteSync(recursive: true);
  });

  test('signing out clears the sync checkpoints with the index', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'drive_chat_1': _chatId,
      'synced_upto_$_chatId': 900,
      'full_sync_$_chatId': DateTime(2026, 9, 26).millisecondsSinceEpoch,
      'indexed_with_$_chatId': 2,
      'synced_upto_$_oldChatId': 40,
      'theme_mode': 'dark',
      'backup_enabled': true,
      'photos_hidden_folders': ['Screenshots'],
      'delete_phone_copy_too': true,
      'offline_wifi_only': true,
      'recent_send_chats': ['42', '7'],
      'recent_destinations': ['docs', ''],
      'cache_swept_at': DateTime(2026, 9, 26).millisecondsSinceEpoch,
      'notifications_asked': true,
      BackupPrefKeys.remindAfter: DateTime(2026, 9, 27).millisecondsSinceEpoch,
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
    final kept = File('${support.path}/offline/report/report.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('kept offline');
    container.read(revealHiddenProvider.notifier).toggle();

    // A delete of phone copies whose window closed while the app was away,
    // and a delete for good still waiting out its Undo.
    final pending = container.read(pendingDeletesProvider.notifier);
    final deleted = <String>[];
    final phone = pending.schedulePhoneDelete(
      copies: {
        'photo': ['asset-1'],
      },
      label: '"photo.jpg" from this phone',
      failure: 'Couldn\'t delete "photo.jpg" from this phone',
      run: (assetIds) async => deleted.addAll(assetIds),
    );
    await pending.appPaused();
    await pending.commit(phone);
    final forGood = pending.schedule(
      fileIds: {'report'},
      label: '"report.pdf"',
      run: () async => deleted.add('report'),
    );
    expect(container.read(pendingDeletesProvider).hiddenIds, {'report'});
    pending.reportFailure('Couldn\'t delete "notes.txt" for good: Telegram took too long.');

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
    expect(shared.containsKey('indexed_with_$_chatId'), isFalse);
    expect(prefs.syncedChatIds, isEmpty);

    // Deleting phone copies along with the trash starts off again, and so
    // do showing the folders Photos keeps out and keeping offline files to
    // Wi-Fi.
    expect(prefs.deletePhoneCopyToo, isFalse);
    expect(container.read(revealHiddenProvider), isFalse);
    expect(prefs.offlineWifiOnly, isFalse);

    // The chats this account sent files to aren't offered to the next one.
    expect(prefs.recentSendChats, isEmpty);
    // The folders this drive's uploads went into are its own, and the next
    // account starts with none.
    expect(prefs.recentDestinations, isEmpty);
    expect(shared.containsKey('recent_destinations'), isFalse);
    // The next drive on this phone is trimmed once when it opens, not left
    // waiting out the last account's day.
    expect(prefs.cacheSweptAt, isNull);
    expect(shared.containsKey('cache_swept_at'), isFalse);

    // Nothing that was waiting to be deleted goes after signing out, from
    // Telegram or from the phone; it is all still in the channel.
    await pending.appResumed();
    await pending.flush();
    expect(deleted, isEmpty);
    expect(pending.undo(forGood), isFalse);
    expect(container.read(pendingDeletesProvider).hiddenIds, isEmpty);
    expect(container.read(pendingDeletesProvider).lastFailure, isNull);

    // Files kept offline go with the index that knew them.
    expect(kept.existsSync(), isFalse);
    expect(Directory('${support.path}/offline').existsSync(), isFalse);

    // App settings and the channel remembered for the account stay.
    expect(prefs.driveChatId(1), _chatId);
    expect(prefs.themeMode, ThemeMode.dark);
    expect(prefs.backupEnabled, isTrue);
    expect(prefs.photosHiddenFolders, {'Screenshots'});
    // Whether the phone was asked to allow notifications, and when a
    // swiped-away backup reminder may come back, are about the phone.
    expect(prefs.notificationsAsked, isTrue);
    expect(
      shared.getInt(BackupPrefKeys.remindAfter),
      DateTime(2026, 9, 27).millisecondsSinceEpoch,
    );
  });
}
