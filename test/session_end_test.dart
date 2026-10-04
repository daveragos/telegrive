import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/auth/data/auth_controller.dart';
import 'package:telegrive/features/checkup/data/drive_checkup.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/trash/data/pending_deletes.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Accepts the log-out and nothing else. The log-out hangs until the test
/// lets it through with [loggedOut], so the test can watch what happens
/// while it is still under way.
class _Telegram extends FakeTelegram {
  int logOuts = 0;
  final loggedOut = Completer<void>();

  @override
  Future<void> logOut() {
    logOuts++;
    return loggedOut.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  late StreamController<td.AuthorizationState> auth;

  setUp(() {
    support = Directory.systemTemp.createTempSync('session_end_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => support.path,
    );
    auth = StreamController<td.AuthorizationState>.broadcast();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider,
      null,
    );
    Pdfrx.cacheDirectoryPath = null;
    await auth.close();
    support.deleteSync(recursive: true);
  });

  Future<(ProviderContainer, _Telegram, Preferences)> open({
    Map<String, Object> stored = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'drive_chat_1': testChatId,
      'synced_upto_$testChatId': 900,
      'full_sync_$testChatId': DateTime(2026, 9, 26).millisecondsSinceEpoch,
      ...stored,
    });
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _Telegram();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        authStateProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    // The controller listens from the moment it exists, as it does in the
    // app, where the phase follows it and keeps it awake.
    final keep = container.listen(authControllerProvider, (_, _) {});
    addTearDown(keep.close);
    container
        .read(driveSessionProvider.notifier)
        .open(
          const DriveSession(
            userId: 1,
            chatId: testChatId,
            channelTitle: 'Telegrive',
            firstName: 'A',
            lastName: '',
            phoneNumber: '',
            username: null,
            isPremium: false,
          ),
        );
    return (container, telegram, container.read(preferencesProvider));
  }

  Future<void> emit(td.AuthorizationState state) async {
    auth.add(state);
    await Future<void>.delayed(Duration.zero);
  }

  test('a log-out nobody asked for here is an ended session', () async {
    final (container, _, prefs) = await open();
    final before = DateTime.now();
    var deleted = false;
    container
        .read(pendingDeletesProvider.notifier)
        .schedule(fileIds: {'file-1'}, label: '1 file', run: () async => deleted = true);

    await emit(const td.AuthorizationStateLoggingOut());

    expect(prefs.sessionEndedAt, isNotNull);
    expect(prefs.sessionEndedAt!.isBefore(before), isFalse);
    expect(container.read(driveSessionProvider), isNull);
    // A delete still waiting out its Undo is dropped, not run against a
    // drive that has gone.
    expect(container.read(pendingDeletesProvider).hiddenIds, isEmpty);
    expect(deleted, isFalse);
    // The index stays, so signing back in soon shows the drive at once.
    expect(prefs.lastFullSync(testChatId), isNotNull);
    expect(prefs.lastSyncedMessageId(testChatId), 900);
  });

  test('signing out is not an ended session, and forgets the checkpoints', () async {
    final (container, telegram, prefs) = await open(
      stored: {
        'checkup_last_run': DateTime(2026, 9, 25).millisecondsSinceEpoch,
        'backup_verified_at': DateTime(2026, 9, 25).millisecondsSinceEpoch,
      },
    );
    final controller = container.read(authControllerProvider.notifier);
    expect(container.read(checkupLastRunProvider), isNotNull);

    final signingOut = controller.signOut();
    // Telegram reports the log-out while the sign-out is still under way:
    // it is the sign-out's own, so nothing is noted and the wipe, not the
    // listener, closes the drive.
    await emit(const td.AuthorizationStateLoggingOut());
    expect(telegram.logOuts, 1);
    expect(prefs.sessionEndedAt, isNull);
    expect(container.read(driveSessionProvider), isNotNull);
    expect(prefs.lastFullSync(testChatId), isNotNull);

    telegram.loggedOut.complete();
    await signingOut;

    expect(prefs.sessionEndedAt, isNull);
    expect(prefs.lastFullSync(testChatId), isNull);
    expect(prefs.lastSyncedMessageId(testChatId), 0);
    expect(prefs.checkupLastRun, isNull);
    expect(prefs.backupVerifiedAt, isNull);
    expect(container.read(checkupLastRunProvider), isNull);
    expect(container.read(driveSessionProvider), isNull);
  });

  test('signing in again clears the note', () async {
    final (_, _, prefs) = await open(
      stored: {'session_ended_at': DateTime(2026, 9, 27).millisecondsSinceEpoch},
    );
    await emit(const td.AuthorizationStateReady());
    expect(prefs.sessionEndedAt, isNull);
  });

  test('a session ended over a week ago takes the local data with it', () async {
    final endedAt = DateTime.now().subtract(const Duration(days: 8));
    final (container, _, prefs) = await open(
      stored: {'session_ended_at': endedAt.millisecondsSinceEpoch},
    );
    final db = container.read(appDatabaseProvider);
    await db.markAssetBackedUp('asset-1', null);

    await emit(const td.AuthorizationStateWaitPhoneNumber());
    // The wipe runs on its own; give it a moment.
    Future<bool> wiped() async =>
        prefs.sessionEndedAt == null && (await db.backupAssetMap()).isEmpty;
    for (var i = 0; i < 500 && !await wiped(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(prefs.sessionEndedAt, isNull);
    expect(prefs.lastFullSync(testChatId), isNull);
    expect(await db.backupAssetMap(), isEmpty);
  });

  test('a session ended yesterday keeps the local data for now', () async {
    final endedAt = DateTime.now().subtract(const Duration(days: 1));
    final (container, _, prefs) = await open(
      stored: {'session_ended_at': endedAt.millisecondsSinceEpoch},
    );
    final db = container.read(appDatabaseProvider);
    await db.markAssetBackedUp('asset-1', null);

    await emit(const td.AuthorizationStateWaitPhoneNumber());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(prefs.sessionEndedAt, isNotNull);
    expect(prefs.lastFullSync(testChatId), isNotNull);
    expect(await db.backupAssetMap(), hasLength(1));
  });
}
