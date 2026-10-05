import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/app/app_phase.dart';
import 'package:telegrive/features/auth/data/auth_controller.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/message_indexer.dart';
import 'package:telegrive/features/setup/data/drive_opener.dart';
import 'package:telegrive/features/setup/data/drive_setup.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// The channel a drive on this phone used before it was replaced.
const _oldChatId = -555;

/// TDLib that knows account 1 and its drive channel, and keeps the kinds of
/// request it was asked. The channel [gone] answers as no chat at all, and
/// a search finds the drive channel. A log-out hangs until the test lets it
/// through with [loggedOut].
class _Telegram extends FakeTelegram {
  _Telegram({this.gone});

  final int? gone;
  final asked = <Type>[];
  final loggedOut = Completer<void>();

  @override
  Future<void> logOut() => loggedOut.future;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    asked.add(function.runtimeType);
    return switch (function) {
      td.GetChat(:final chatId) when chatId == gone => throw const TelegramException(
        400,
        'CHAT_NOT_FOUND',
      ),
      td.GetMe() => testUser(),
      td.GetChat() => channelChat(),
      td.GetSupergroup() => ownedSupergroup(),
      td.GetSupergroupFullInfo() => channelInfo(),
      td.SearchChatsOnServer() ||
      td.SearchChats() => const td.Chats(totalCount: 1, chatIds: [testChatId]),
      td.GetChatPinnedMessage() => driveMessage(50 << 20),
      td.OpenChat() || td.SetChatPhoto() => const td.Ok(),
      _ => null,
    };
  }
}

/// What a returning person's phone holds: the drive saved when it last
/// opened, on [chatId], read in full a moment ago.
Map<String, Object> _returning({int chatId = testChatId}) => {
  'drive_snapshot': jsonEncode(
    DriveSession(
      userId: 1,
      chatId: chatId,
      channelTitle: 'Telegrive',
      firstName: 'Dawit',
      lastName: 'Beyene',
      phoneNumber: '',
      username: null,
      isPremium: false,
    ).toJson(),
  ),
  'drive_chat_1': chatId,
  'last_user_id': 1,
  'synced_upto_$chatId': 900,
  'full_sync_$chatId': DateTime.now().millisecondsSinceEpoch,
  'indexed_with_$chatId': MessageIndexer.version,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  late StreamController<td.AuthorizationState> auth;

  setUp(() {
    support = Directory.systemTemp.createTempSync('app_phase_test');
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

  /// The app as it starts, with [stored] preferences and the phases it
  /// goes through after the first, which the result's list collects.
  Future<(ProviderContainer, _Telegram, Preferences, List<AppPhase>)> start(
    Map<String, Object> stored, {
    int? gone,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _Telegram(gone: gone);
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
    final phases = <AppPhase>[];
    // The router and the app root keep these alive in the app.
    final phase = container.listen<AppPhase>(appPhaseProvider, (_, next) => phases.add(next));
    final opener = container.listen<void>(driveOpenerProvider, (_, _) {});
    addTearDown(phase.close);
    addTearDown(opener.close);
    return (container, telegram, container.read(preferencesProvider), phases);
  }

  Future<void> emit(td.AuthorizationState state) async {
    auth.add(state);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> until(FutureOr<bool> Function() condition) async {
    for (var i = 0; i < 300 && !await condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await condition(), isTrue);
  }

  Future<void> seedFolder(AppDatabase db) => db.upsertFolder(
    FoldersCompanion.insert(
      id: 'docs',
      name: 'Docs',
      messageId: 1,
      createdAt: DateTime(2026, 9, 26),
      modifiedAt: DateTime(2026, 9, 26),
    ),
  );

  test('a drive this phone knows shows before TDLib says anything', () async {
    final (container, _, _, _) = await start(_returning());

    expect(container.read(appPhaseProvider), AppPhase.ready);
    // Home's avatar and Settings' account row read it from the snapshot.
    final shown = container.read(visibleSessionProvider);
    expect(shown?.initials, 'DB');
    expect(shown?.phoneNumber, '');
    expect(container.read(driveSessionProvider), isNull);
  });

  test('once TDLib is signed in the drive opens behind Home', () async {
    final (container, telegram, prefs, phases) = await start(_returning());

    await emit(const td.AuthorizationStateWaitTdlibParameters());
    await emit(const td.AuthorizationStateReady());
    await until(() => container.read(driveSessionProvider) != null);

    expect(
      telegram.asked,
      containsAll([td.GetMe, td.GetChat, td.GetSupergroup]),
    );
    expect(container.read(driveSetupProvider).step, SetupStep.done);
    expect(container.read(driveSessionProvider)?.chatId, testChatId);
    // The phone number fills in from the session.
    expect(container.read(visibleSessionProvider)?.phoneNumber, '251911000000');
    // Home stayed the whole time, never the splash or the setup screen.
    expect(container.read(appPhaseProvider), AppPhase.ready);
    expect(phases.where((p) => p != AppPhase.ready), isEmpty);
    // Saved again for the next start, without the phone number.
    expect(prefs.driveSnapshot, isNot(contains('251911000000')));
  });

  test('TDLib asking for a phone number takes the drive off the phone', () async {
    final (container, _, prefs, _) = await start(_returning());
    final db = container.read(appDatabaseProvider);
    await seedFolder(db);
    await db.markAssetBackedUp('asset-1', null);

    await emit(const td.AuthorizationStateWaitTdlibParameters());
    expect(container.read(appPhaseProvider), AppPhase.ready);
    await emit(const td.AuthorizationStateWaitPhoneNumber());
    expect(container.read(appPhaseProvider), AppPhase.welcome);

    // The wipe runs on its own; give it a moment.
    await until(() async => (await db.backupAssetMap()).isEmpty);
    expect(container.read(driveSnapshotProvider), isNull);
    expect(prefs.lastSyncedMessageId(testChatId), 0);
    expect(prefs.syncedChatIds, isEmpty);
    expect(await db.folderById('docs'), isNull);
    expect(await db.backupAssetMap(), isEmpty);
    expect(container.read(appPhaseProvider), AppPhase.welcome);
  });

  test('without a saved drive the app starts at the splash', () async {
    final (container, _, _, _) = await start({
      'drive_chat_1': testChatId,
      'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
    });
    expect(container.read(appPhaseProvider), AppPhase.starting);
    expect(container.read(visibleSessionProvider), isNull);
  });

  test('a saved drive whose index was never read in full waits at the splash', () async {
    final (container, _, _, _) = await start({..._returning()}..remove('full_sync_$testChatId'));
    expect(container.read(appPhaseProvider), AppPhase.starting);
    expect(container.read(driveSnapshotProvider), isNull);
  });

  test('a saved drive on a channel no longer the account\'s waits too', () async {
    final (container, _, _, _) = await start({..._returning(), 'drive_chat_1': -777});
    expect(container.read(appPhaseProvider), AppPhase.starting);
  });

  test('a saved drive waits after a session ended from Telegram', () async {
    final (container, _, _, _) = await start({
      ..._returning(),
      'session_ended_at': DateTime.now().millisecondsSinceEpoch,
    });
    expect(container.read(appPhaseProvider), AppPhase.starting);
  });

  test('a session ended from Telegram lands on Welcome and keeps the index', () async {
    final (container, _, prefs, phases) = await start(_returning());
    final db = container.read(appDatabaseProvider);
    await seedFolder(db);

    await emit(const td.AuthorizationStateReady());
    await until(() => container.read(driveSessionProvider) != null);
    phases.clear();

    await emit(const td.AuthorizationStateLoggingOut());
    await emit(const td.AuthorizationStateClosed());
    await emit(const td.AuthorizationStateWaitTdlibParameters());
    await emit(const td.AuthorizationStateWaitPhoneNumber());

    // Home never comes back while TDLib restarts signed out.
    expect(phases, isNot(contains(AppPhase.ready)));
    expect(container.read(appPhaseProvider), AppPhase.welcome);
    expect(prefs.driveSnapshot, isNull);
    expect(prefs.sessionEndedAt, isNotNull);
    // The week-long keep still holds, so signing back in soon opens it.
    expect(prefs.lastFullSync(testChatId), isNotNull);
    expect(await db.folderById('docs'), isNotNull);
  });

  test('signing out forgets the saved drive', () async {
    final (container, telegram, prefs, phases) = await start(_returning());
    await emit(const td.AuthorizationStateReady());
    await until(() => container.read(driveSessionProvider) != null);
    phases.clear();

    final signingOut = container.read(authControllerProvider.notifier).signOut();
    await emit(const td.AuthorizationStateLoggingOut());
    await emit(const td.AuthorizationStateClosed());
    telegram.loggedOut.complete();
    await signingOut;
    await emit(const td.AuthorizationStateWaitPhoneNumber());

    expect(phases, isNot(contains(AppPhase.ready)));
    expect(prefs.driveSnapshot, isNull);
    expect(prefs.sessionEndedAt, isNull);
    expect(container.read(appPhaseProvider), AppPhase.welcome);
  });

  test('a replaced drive channel clears the old index before reading the new one', () async {
    final (container, _, prefs, _) = await start(_returning(chatId: _oldChatId), gone: _oldChatId);
    final db = container.read(appDatabaseProvider);
    await seedFolder(db);
    expect(container.read(appPhaseProvider), AppPhase.ready);

    await emit(const td.AuthorizationStateReady());
    await until(() => container.read(driveSetupProvider).step == SetupStep.done);

    expect(container.read(driveSessionProvider)?.chatId, testChatId);
    expect(prefs.driveChatId(1), testChatId);
    expect(await db.folderById('docs'), isNull);
    expect(prefs.lastSyncedMessageId(_oldChatId), 0);
    expect(prefs.lastFullSync(_oldChatId), isNull);
    // The new channel was read in full, so the next start opens it at once.
    expect(prefs.lastFullSync(testChatId), isNotNull);
    expect(prefs.driveSnapshot, contains('$testChatId'));
    expect(container.read(appPhaseProvider), AppPhase.ready);
  });
}
