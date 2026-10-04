import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/features/checkup/data/drive_checkup.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/previews.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';

import 'support/fake_telegram.dart';

/// Telegram before any account has signed in, which keeps what it was asked
/// and answers a file lookup, a download, the account timer and the list of
/// devices (with none listed).
class _Telegram extends FakeTelegram {
  _Telegram() : super(signedIn: false);

  final requests = <td.TdFunction>[];

  Iterable<T> asked<T extends td.TdFunction>() => requests.whereType<T>();

  /// Hands the client an authorization state the way TDLib's update would.
  void signal(td.AuthorizationState state) =>
      receive(td.UpdateAuthorizationState(authorizationState: state).toJson());

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    return switch (function) {
      td.GetFile(:final fileId) => tdFile(fileId, path: '/files/$fileId', downloaded: true),
      td.DownloadFile(:final fileId) => tdFile(
        fileId,
        path: '/thumbs/$fileId.jpg',
        downloaded: true,
      ),
      td.GetAccountTtl() => const td.AccountTtl(days: 180),
      td.GetActiveSessions() => const td.Sessions(sessions: [], inactiveSessionTtlDays: 180),
      td.SetOption() || td.CancelDownloadFile() => const td.Ok(),
      _ => null,
    };
  }
}

/// The drive saved on the phone, which a returning person's Home shows
/// while Telegram starts.
class _Snapshot extends DriveSnapshotNotifier {
  @override
  DriveSession? build() => testSession;
}

const _part = PartRow(fileId: 'f', partIndex: 0, messageId: 5, tdFileId: 7, size: 10);

void main() {
  late _Telegram telegram;
  late ProviderContainer container;

  Future<ProviderContainer> start({bool saved = false}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    telegram = _Telegram();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        if (saved) driveSnapshotProvider.overrideWith(_Snapshot.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return container;
  }

  /// Whether [TelegramClient.ready] has completed, after the microtasks
  /// that would complete it have run.
  Future<bool> isReady() async {
    var done = false;
    unawaited(telegram.ready.then((_) => done = true));
    await pumpEventQueue();
    return done;
  }

  group('ready', () {
    setUp(() async => start());

    test('waits for an account, and waits again after it signs out', () async {
      expect(await isReady(), isFalse);
      telegram.signal(const td.AuthorizationStateWaitPhoneNumber());
      expect(await isReady(), isFalse);

      telegram.signal(const td.AuthorizationStateReady());
      expect(await isReady(), isTrue);

      telegram.signal(const td.AuthorizationStateLoggingOut());
      expect(await isReady(), isFalse);

      // The next account to sign in ends the wait.
      telegram.signal(const td.AuthorizationStateReady());
      expect(await isReady(), isTrue);
    });

    test('waits again once the client has closed', () async {
      telegram.signal(const td.AuthorizationStateReady());
      expect(await isReady(), isTrue);

      // A closed app doesn't make a fresh client, which would need TDLib.
      await telegram.close();
      telegram.signal(const td.AuthorizationStateClosed());
      expect(await isReady(), isFalse);
    });

    test('work already waiting is released by the next sign-in', () async {
      var released = false;
      unawaited(telegram.ready.then((_) => released = true));

      telegram.signal(const td.AuthorizationStateLoggingOut());
      await pumpEventQueue();
      expect(released, isFalse);

      telegram.signal(const td.AuthorizationStateReady());
      await pumpEventQueue();
      expect(released, isTrue);
    });
  });

  group('work only Telegram can do', () {
    setUp(() async => start());

    test('a file is looked up once an account has signed in', () async {
      final lookup = container.read(driveRepositoryProvider).resolveTdFile(_part);
      await pumpEventQueue();
      expect(telegram.asked<td.GetFile>(), isEmpty);

      telegram.signal(const td.AuthorizationStateReady());
      expect((await lookup).id, 7);
      expect(telegram.asked<td.GetFile>(), hasLength(1));
    });

    test('a file still waiting after a minute fails instead of hanging', () {
      fakeAsync((async) {
        Object? failure;
        container
            .read(driveRepositoryProvider)
            .resolveTdFile(_part)
            .then<void>((_) {}, onError: (Object e) => failure = e);

        async.elapse(const Duration(seconds: 59));
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(failure, isA<TimeoutException>());
        expect(telegram.asked<td.GetFile>(), isEmpty);
      });
    });

    test('a thumbnail is asked for once an account has signed in', () async {
      container.listen(thumbnailPathProvider(5), (_, _) {});
      await pumpEventQueue();
      expect(telegram.asked<td.DownloadFile>(), isEmpty);

      telegram.signal(const td.AuthorizationStateReady());
      expect(await container.read(thumbnailPathProvider(5).future), '/thumbs/5.jpg');
      expect(telegram.asked<td.DownloadFile>(), hasLength(1));
    });

    test('a thumbnail nobody waits for before then is never asked for', () async {
      final tile = container.listen(thumbnailPathProvider(5), (_, _) {});
      await pumpEventQueue();

      // The tile scrolls away while Telegram is still starting.
      tile.close();
      await container.pump();
      telegram.signal(const td.AuthorizationStateReady());
      await pumpEventQueue();

      expect(telegram.asked<td.DownloadFile>(), isEmpty);
      expect(telegram.asked<td.CancelDownloadFile>(), isEmpty);
    });
  });

  group('Settings opened before Telegram has started', () {
    setUp(() async => start());

    test('asks for the account timer once an account has signed in', () async {
      container.listen(accountTtlProvider, (_, _) {});
      await pumpEventQueue();
      expect(telegram.asked<td.GetAccountTtl>(), isEmpty);
      expect(container.read(accountTtlProvider).isLoading, isTrue);

      telegram.signal(const td.AuthorizationStateReady());
      expect(await container.read(accountTtlProvider.future), 180);
      expect(telegram.asked<td.GetAccountTtl>(), hasLength(1));
    });

    test('asks for this phone\'s entry in the devices list once signed in', () async {
      container.listen(currentSessionProvider, (_, _) {});
      await pumpEventQueue();
      expect(telegram.asked<td.GetActiveSessions>(), isEmpty);

      telegram.signal(const td.AuthorizationStateReady());
      expect(await container.read(currentSessionProvider.future), isNull);
      expect(telegram.asked<td.GetActiveSessions>(), hasLength(1));
    });
  });

  group('a change with no drive open', () {
    Matcher refusedWith(String message) =>
        throwsA(isA<DriveException>().having((e) => e.message, 'message', message));

    test('says Telegram is still connecting when the drive is only saved', () async {
      await start(saved: true);
      expect(container.read(driveSessionProvider), isNull);

      await expectLater(
        container.read(driveRepositoryProvider).createFolder('Docs'),
        refusedWith(stillConnecting),
      );
      expect(telegram.requests, isEmpty);
    });

    test('says the drive is not open when nothing is saved either', () async {
      await start();

      await expectLater(
        container.read(driveRepositoryProvider).createFolder('Docs'),
        refusedWith('Your drive is not open.'),
      );
      expect(telegram.requests, isEmpty);
    });
  });
}
