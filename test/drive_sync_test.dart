import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/secure_store.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

const _chatId = -1001234567890;

class _Session extends DriveSessionNotifier {
  @override
  DriveSession? build() => const DriveSession(
    userId: 1,
    chatId: _chatId,
    channelTitle: 'Telegrive',
    firstName: 'A',
    lastName: '',
    phoneNumber: '',
    username: null,
    isPremium: false,
  );
}

/// Answers history requests with [failures] first, then an empty channel.
class _FakeTelegram extends TelegramClient {
  _FakeTelegram(this.failures) : super(SecureStore());

  final List<TelegramException> failures;
  int historyCalls = 0;

  @override
  Future<T> send<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (function is td.GetChatHistory) {
      historyCalls++;
      if (failures.isNotEmpty) throw failures.removeAt(0);
      return const td.Messages(totalCount: 0, messages: []) as T;
    }
    if (function is td.OpenChat || function is td.CloseChat) return const td.Ok() as T;
    throw UnsupportedError('$function');
  }
}

void main() {
  Future<(ProviderContainer, _FakeTelegram, Preferences)> start(
    List<TelegramException> failures,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _FakeTelegram(failures);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        driveSessionProvider.overrideWith(_Session.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return (container, telegram, container.read(preferencesProvider));
  }

  test('a rate limit halfway through reading is waited out, not fatal', () async {
    final (container, telegram, prefs) = await start([
      const TelegramException(420, 'FLOOD_WAIT_1'),
    ]);
    await container.read(driveSyncProvider.notifier).fullSync();

    expect(telegram.historyCalls, 2);
    expect(container.read(driveSyncProvider).error, isNull);
    expect(prefs.lastFullSync(_chatId), isNotNull);
  });

  test('a bad request fails the sync and leaves the index marked unfinished', () async {
    final (container, _, prefs) = await start([
      const TelegramException(400, 'CHANNEL_INVALID'),
    ]);
    await container.read(driveSyncProvider.notifier).fullSync();

    expect(container.read(driveSyncProvider).error, isNotNull);
    // Backup reads this to know the index can't be trusted yet.
    expect(prefs.lastFullSync(_chatId), isNull);
  });

  test('a failure stays while the next try runs, and clears when it succeeds', () async {
    final (container, _, _) = await start([
      const TelegramException(400, 'CHANNEL_INVALID'),
    ]);
    final sync = container.read(driveSyncProvider.notifier);
    await sync.refresh();
    expect(container.read(driveSyncProvider).error, isNotNull);

    final whileRunning = <String?>[];
    container.listen<SyncState>(driveSyncProvider, (_, next) {
      if (next.running) whileRunning.add(next.error);
    });
    await sync.refresh();

    // Home keeps saying Telegram can't be reached until a try gets through.
    expect(whileRunning, isNotEmpty);
    expect(whileRunning, everyElement(isNotNull));
    expect(container.read(driveSyncProvider).error, isNull);
  });
}
