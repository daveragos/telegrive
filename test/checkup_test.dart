import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/backup/data/backup_controller.dart';
import 'package:telegrive/features/checkup/data/drive_checkup.dart';
import 'package:telegrive/features/drive/data/drive_repository.dart';
import 'package:telegrive/features/drive/data/drive_session.dart';
import 'package:telegrive/features/drive/data/drive_sync.dart';
import 'package:telegrive/infrastructure/database/app_database.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:telegrive/infrastructure/telegram/telegram_client.dart';
import 'package:telegrive/infrastructure/telegram/telegram_exception.dart';

import 'support/fake_telegram.dart';

/// An account whose channel has a one-month auto-delete timer, no public
/// link, no two-step verification and a six-month inactivity timer.
class _Telegram extends FakeTelegram {
  _Telegram({this.passwordFails = false});

  final bool passwordFails;
  final List<td.TdFunction> requests = [];
  int autoDelete = 2592000;
  List<String> usernames = const [];
  int ttl = 180;

  @override
  Future<td.TdObject?> answer(td.TdFunction function) async {
    requests.add(function);
    switch (function) {
      case td.GetChat():
        return channelChat(autoDeleteSeconds: autoDelete);
      case td.GetSupergroup():
        return ownedSupergroup(usernames: usernames);
      case td.GetPasswordState():
        if (passwordFails) throw const TelegramException(500, 'Internal Server Error');
        return passwordState(hasPassword: false);
      case td.GetAccountTtl():
        return td.AccountTtl(days: ttl);
      case td.SetChatMessageAutoDeleteTime(:final messageAutoDeleteTime):
        autoDelete = messageAutoDeleteTime;
        return const td.Ok();
      case td.SetSupergroupUsername():
        usernames = const [];
        return const td.Ok();
      case td.SetAccountTtl(:final ttl):
        this.ttl = ttl.days;
        return const td.Ok();
      case td.OpenChat() || td.CloseChat():
        return const td.Ok();
      default:
        return null;
    }
  }
}

/// A drive caught up this run, without a full read of the channel.
class _Sync extends DriveSync {
  @override
  SyncState build() => SyncState(lastSynced: DateTime.now());
}

/// Backup switched on, without a pass running.
class _Backup extends BackupController {
  @override
  BackupState build() {
    super.build();
    return const BackupState(phase: BackupPhase.upToDate);
  }

  @override
  void schedule({bool immediate = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photos = MethodChannel('com.fluttercandies/photo_manager');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      photos,
      (call) async => null,
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photos, null),
  );

  final now = DateTime(2026, 9, 25);

  Future<(ProviderContainer, _Telegram, AppDatabase)> open({
    bool passwordFails = false,
    bool driveOpen = true,
    Map<String, Object> stored = const {},
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(stored);
    final shared = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final telegram = _Telegram(passwordFails: passwordFails);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        appDatabaseProvider.overrideWithValue(db),
        telegramClientProvider.overrideWithValue(telegram),
        if (driveOpen) driveSessionProvider.overrideWith(TestSession.new),
        driveSyncProvider.overrideWith(_Sync.new),
        backupControllerProvider.overrideWith(_Backup.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return (container, telegram, db);
  }

  test('the report names the timer, the missing password and the account timer', () async {
    final (container, _, _) = await open(
      stored: {'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch},
    );
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    final report = await container.read(driveCheckupProvider.future);

    final channel = report.find<ChannelFinding>()!;
    expect(channel.autoDeleteSeconds, 2592000);
    expect(channel.supergroupId, testSupergroupId);
    expect(channel.severity, CheckSeverity.action);
    expect(report.find<TwoStepFinding>()!.hasPassword, isFalse);
    expect(report.find<AccountTtlFinding>()!.days, 180);
    expect(report.find<AccountTtlFinding>()!.severity, CheckSeverity.neutral);
    expect(report.find<IndexFinding>()!.severity, CheckSeverity.fine);
    expect(report.find<BackupFinding>()!.enabled, isFalse);
    // Nothing in the trash and no split files, so neither has a row.
    expect(report.find<TrashFinding>(), isNull);
    expect(report.find<SplitFinding>(), isNull);
    // What needs the person comes first.
    expect(report.findings.first, isA<ChannelFinding>());
    expect(report.findings[1], isA<TwoStepFinding>());
    expect(container.read(preferencesProvider).checkupLastRun, isNotNull);
    expect(container.read(checkupLastRunProvider), isNotNull);
  });

  test('without a full read this run, backup is not checked, and the index not doubted', () async {
    final (container, _, db) = await open(
      stored: {
        BackupPrefKeys.enabled: true,
        'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
      },
    );
    await db.markAssetBackedUp('a0', null);
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    final report = await container.read(driveCheckupProvider.future);

    final backup = report.find<BackupFinding>()!;
    expect(backup.outcome, VerifyOutcome.skipped);
    expect(backup.cannotCheck, isFalse);
    expect(backup.notCheckedYet, isTrue);
    expect(backup.severity, CheckSeverity.neutral);
  });

  test('a match made in an earlier run still counts', () async {
    final verifiedAt = DateTime(2026, 9, 24, 19, 32);
    final (container, _, db) = await open(
      stored: {
        BackupPrefKeys.enabled: true,
        'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
        'backup_verified_at': verifiedAt.millisecondsSinceEpoch,
      },
    );
    await db.upsertFilePart(
      DriveFilesCompanion.insert(
        id: 'f0',
        name: 'IMG_0.jpg',
        mimeType: 'image/jpeg',
        kind: FileKind.image,
        size: 100,
        createdAt: now,
        modifiedAt: now,
      ),
      FilePartsCompanion.insert(fileId: 'f0', partIndex: 0, messageId: 1, tdFileId: 1, size: 100),
    );
    await db.markAssetBackedUp('a0', 'f0');
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    final report = await container.read(driveCheckupProvider.future);

    final backup = report.find<BackupFinding>()!;
    expect(backup.outcome, VerifyOutcome.skipped);
    expect((backup.verifiedCount, backup.missingCount), (1, 0));
    expect(backup.verifiedAt, verifiedAt);
    expect(backup.notCheckedYet, isFalse);
    expect(backup.severity, CheckSeverity.fine);
  });

  test('a password check that fails only leaves that row unknown', () async {
    final (container, _, _) = await open(passwordFails: true);
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    final report = await container.read(driveCheckupProvider.future);

    expect(report.find<TwoStepFinding>()!.hasPassword, isNull);
    expect(report.find<TwoStepFinding>()!.severity, CheckSeverity.neutral);
    expect(report.find<ChannelFinding>()!.autoDeleteSeconds, 2592000);
    expect(report.find<AccountTtlFinding>()!.days, 180);
  });

  test('with no drive open the check-up fails rather than report an empty all-clear', () async {
    final (container, telegram, _) = await open(driveOpen: false);
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);

    await expectLater(
      container.read(driveCheckupProvider.future),
      throwsA(isA<DriveException>().having((e) => e.message, 'message', 'Your drive is not open.')),
    );
    final state = container.read(driveCheckupProvider);
    expect(state.hasError, isTrue);
    expect(state.hasValue, isFalse);
    // Nothing was asked, and no last-checked time was recorded.
    expect(telegram.requests, isEmpty);
    expect(container.read(preferencesProvider).checkupLastRun, isNull);
  });

  test('with the drive only saved the check-up says Telegram is still connecting', () async {
    final (container, _, _) = await open(
      driveOpen: false,
      stored: {
        'drive_snapshot': jsonEncode(testSession.toJson()),
        'drive_chat_1': testChatId,
        'full_sync_$testChatId': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);

    await expectLater(
      container.read(driveCheckupProvider.future),
      throwsA(isA<DriveException>().having((e) => e.message, 'message', stillConnecting)),
    );
  });

  test('turning the timer off sends zero and the row turns fine', () async {
    final (container, telegram, _) = await open();
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    await container.read(driveCheckupProvider.future);

    await container.read(driveCheckupProvider.notifier).turnOffAutoDelete();

    final sent = telegram.requests.whereType<td.SetChatMessageAutoDeleteTime>().single;
    expect((sent.chatId, sent.messageAutoDeleteTime), (testChatId, 0));
    final report = await container.read(driveCheckupProvider.future);
    expect(report.find<ChannelFinding>()!.isFine, isTrue);
  });

  test('a public link is reported and taken away', () async {
    final (container, telegram, _) = await open();
    telegram
      ..autoDelete = 0
      ..usernames = ['mydrive'];
    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    var report = await container.read(driveCheckupProvider.future);
    expect(report.find<ChannelFinding>()!.username, 'mydrive');

    await container.read(driveCheckupProvider.notifier).makePrivate(testSupergroupId);
    final sent = telegram.requests.whereType<td.SetSupergroupUsername>().single;
    expect((sent.supergroupId, sent.username), (testSupergroupId, ''));
    report = await container.read(driveCheckupProvider.future);
    expect(report.find<ChannelFinding>()!.isFine, isTrue);
  });

  test('the account timer is set through Telegram and read back', () async {
    final (container, telegram, _) = await open();
    final keep = container.listen(accountTtlProvider, (_, _) {});
    addTearDown(keep.close);
    expect(await container.read(accountTtlProvider.future), 180);

    await container.read(accountTtlProvider.notifier).set(730);
    expect(telegram.requests.whereType<td.SetAccountTtl>().single.ttl.days, 730);
    expect(container.read(accountTtlProvider).value, 730);
  });

  test('split files missing a part are named with the part, trash due is counted', () async {
    final (container, _, db) = await open();
    DriveFilesCompanion file(String id, String name, {int partCount = 1}) =>
        DriveFilesCompanion.insert(
          id: id,
          name: name,
          mimeType: 'video/mp4',
          kind: FileKind.video,
          size: 100,
          createdAt: now,
          modifiedAt: now,
          partCount: Value(partCount),
        );
    FilePartsCompanion part(String fileId, int index, int messageId) => FilePartsCompanion.insert(
      fileId: fileId,
      partIndex: index,
      messageId: messageId,
      tdFileId: messageId,
      size: 50,
    );
    final holiday = file('h', 'Summer holiday 4K.mp4', partCount: 12);
    for (var i = 0; i < 12; i++) {
      if (i != 6) await db.upsertFilePart(holiday, part('h', i, 100 + i));
    }
    await db.upsertFilePart(file('w', 'Whole.mp4', partCount: 2), part('w', 0, 200));
    await db.upsertFilePart(file('w', 'Whole.mp4', partCount: 2), part('w', 1, 201));
    // In the trash for 25 days: it goes within the week. The other is fresh.
    await db.upsertFilePart(file('old', 'Old.mp4'), part('old', 0, 300));
    await db.updateFile(
      'old',
      DriveFilesCompanion(trashedAt: Value(DateTime.now().subtract(const Duration(days: 25)))),
    );
    await db.upsertFilePart(file('new', 'New.mp4'), part('new', 0, 301));
    await db.updateFile('new', DriveFilesCompanion(trashedAt: Value(DateTime.now())));
    await db.refreshHidden();

    final keep = container.listen(driveCheckupProvider, (_, _) {});
    addTearDown(keep.close);
    final report = await container.read(driveCheckupProvider.future);

    final split = report.find<SplitFinding>()!;
    expect(split.total, 2);
    expect(split.incomplete.single.file.name, 'Summer holiday 4K.mp4');
    expect(split.incomplete.single.missingParts, [7]);
    final trash = report.find<TrashFinding>()!;
    expect((trash.count, trash.dueSoon), (2, 1));
    expect(trash.severity, CheckSeverity.action);
  });
}
