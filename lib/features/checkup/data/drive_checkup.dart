import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../backup/data/backup_controller.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/drive_session.dart';
import '../../drive/data/drive_sync.dart';
import '../../drive/domain/drive_models.dart';
import '../../transfers/data/transfer_queue.dart';

/// How a check-up row reads: fine, a fact with nothing to do, or something
/// that needs the person.
enum CheckSeverity { fine, neutral, action }

/// One check's answer. The screen turns each into a row.
@immutable
sealed class CheckFinding {
  const CheckFinding();

  CheckSeverity get severity;
}

/// Whether the drive channel is the account's own, private, and keeps its
/// messages.
@immutable
class ChannelFinding extends CheckFinding {
  const ChannelFinding.ok({this.supergroupId})
    : autoDeleteSeconds = 0,
      username = null,
      error = null;

  /// Telegram's auto-delete timer is on for the channel, so every file
  /// goes after [autoDeleteSeconds].
  const ChannelFinding.autoDelete(this.autoDeleteSeconds, {this.supergroupId})
    : username = null,
      error = null;

  /// The channel has a public link, so anyone with it sees the files.
  const ChannelFinding.public(String this.username, {this.supergroupId})
    : autoDeleteSeconds = 0,
      error = null;

  /// The channel couldn't be looked at, for the reason in [error].
  const ChannelFinding.unreachable(String this.error)
    : supergroupId = null,
      autoDeleteSeconds = 0,
      username = null;

  final int? supergroupId;
  final int autoDeleteSeconds;
  final String? username;
  final String? error;

  bool get isFine => autoDeleteSeconds == 0 && username == null && error == null;

  @override
  CheckSeverity get severity => isFine ? CheckSeverity.fine : CheckSeverity.action;
}

/// When the channel was last read in full, and whether a read is running or
/// the last one failed.
@immutable
class IndexFinding extends CheckFinding {
  const IndexFinding({
    required this.lastFull,
    required this.error,
    required this.running,
    required this.scanned,
  });

  /// A full read older than this wants another.
  static const Duration staleAfter = Duration(hours: 48);

  final DateTime? lastFull;
  final String? error;
  final bool running;
  final int scanned;

  bool get isStale => lastFull == null || DateTime.now().difference(lastFull!) > staleAfter;

  @override
  CheckSeverity get severity => running
      ? CheckSeverity.neutral
      : (error != null || isStale ? CheckSeverity.action : CheckSeverity.fine);
}

/// A split file with parts gone from the channel, and which parts, counted
/// from one.
typedef IncompleteFile = ({DriveFile file, List<int> missingParts});

/// Whether every split file still has all its parts.
@immutable
class SplitFinding extends CheckFinding {
  const SplitFinding({required this.total, required this.incomplete});

  /// How many split files the drive shows.
  final int total;
  final List<IncompleteFile> incomplete;

  @override
  CheckSeverity get severity => incomplete.isEmpty ? CheckSeverity.fine : CheckSeverity.action;
}

/// Whether the photos backed up from this phone are all still in the drive.
@immutable
class BackupFinding extends CheckFinding {
  const BackupFinding({
    required this.enabled,
    required this.outcome,
    required this.verifiedCount,
    required this.missingCount,
    required this.verifiedAt,
  });

  final bool enabled;
  final VerifyOutcome outcome;

  /// Backed-up photos whose file is in the drive.
  final int verifiedCount;

  /// Backed-up photos whose file is gone, waiting for the person's choice.
  final int missingCount;

  /// When the backed-up photos were last matched against the index, or null
  /// before the first match. The match's result is kept in the records, so
  /// a run without a full read of the channel still has it.
  final DateTime? verifiedAt;

  /// The index can't be trusted for this: so much looks gone that the index
  /// is the likelier culprit, and nothing was recorded.
  bool get cannotCheck => enabled && missingCount == 0 && outcome == VerifyOutcome.suspect;

  /// Backup is on, but its photos have never been matched against the
  /// index. That happens after the next full read of the channel.
  bool get notCheckedYet =>
      enabled && missingCount == 0 && outcome == VerifyOutcome.skipped && verifiedAt == null;

  @override
  CheckSeverity get severity {
    if (!enabled) return CheckSeverity.neutral;
    if (missingCount > 0) return CheckSeverity.action;
    if (cannotCheck || notCheckedYet || verifiedCount == 0) return CheckSeverity.neutral;
    return CheckSeverity.fine;
  }
}

/// What the trash holds and how much of it goes for good soon.
@immutable
class TrashFinding extends CheckFinding {
  const TrashFinding({required this.count, required this.dueSoon});

  /// Items whose 30 days end within this long count as due.
  static const Duration dueWithin = Duration(days: 7);

  final int count;
  final int dueSoon;

  @override
  CheckSeverity get severity => dueSoon > 0 ? CheckSeverity.action : CheckSeverity.neutral;
}

/// Whether the account asks for a password on a new sign-in. Null when
/// Telegram couldn't say.
@immutable
class TwoStepFinding extends CheckFinding {
  const TwoStepFinding(this.hasPassword);

  final bool? hasPassword;

  @override
  CheckSeverity get severity => switch (hasPassword) {
    true => CheckSeverity.fine,
    false => CheckSeverity.action,
    null => CheckSeverity.neutral,
  };
}

/// After how many days without activity Telegram deletes the account, and
/// the drive with it. Null when Telegram couldn't say.
@immutable
class AccountTtlFinding extends CheckFinding {
  const AccountTtlFinding(this.days);

  /// A timer this short, or shorter, is called out.
  static const int shortAtOrBelow = 90;

  final int? days;

  @override
  CheckSeverity get severity => switch (days) {
    null => CheckSeverity.neutral,
    final d when d <= shortAtOrBelow => CheckSeverity.action,
    _ => CheckSeverity.neutral,
  };
}

/// Every check's answer, from one run, with the rows that need the person
/// first.
@immutable
class CheckupReport {
  CheckupReport({required List<CheckFinding> findings, required this.at})
    : findings = List.unmodifiable([
        ...findings.where((f) => f.severity == CheckSeverity.action),
        ...findings.where((f) => f.severity != CheckSeverity.action),
      ]);

  final List<CheckFinding> findings;
  final DateTime at;

  T? find<T extends CheckFinding>() => findings.whereType<T>().firstOrNull;
}

/// The inactive-account timers Telegram offers, in days.
const List<int> accountTtlChoices = [30, 90, 180, 365, 548, 730];

/// Looks the drive over: the channel, the index, split files, photo
/// backup, the trash and the account, each in its own try, so a check that
/// fails only degrades its own row. Reading it runs the check-up;
/// invalidating it runs it again.
class DriveCheckup extends AsyncNotifier<CheckupReport> {
  TelegramClient get _client => ref.read(telegramClientProvider);
  Preferences get _prefs => ref.read(preferencesProvider);
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveRepository get _repository => ref.read(driveRepositoryProvider);

  /// Uploads younger than this with parts still to come aren't incomplete,
  /// only under way.
  static const Duration settlesWithin = Duration(hours: 24);

  @override
  Future<CheckupReport> build() async {
    final session = ref.read(driveSessionProvider);
    if (session == null) return CheckupReport(findings: const [], at: DateTime.now());
    final findings = <CheckFinding>[
      await _channel(session.chatId),
      _index(session.chatId),
      ?await _split(),
      await _backup(),
      ?await _trash(),
      await _twoStep(),
      await _accountTtl(),
    ];
    final at = DateTime.now();
    await ref.read(checkupLastRunProvider.notifier).set(at);
    return CheckupReport(findings: findings, at: at);
  }

  Future<ChannelFinding> _channel(int chatId) async {
    try {
      final chat = await _client.send<td.Chat>(td.GetChat(chatId: chatId));
      int? supergroupId;
      var usernames = const <String>[];
      if (chat.type case td.ChatTypeSupergroup(supergroupId: final id)) {
        supergroupId = id;
        final group = await _client.send<td.Supergroup>(td.GetSupergroup(supergroupId: id));
        if (group.status is! td.ChatMemberStatusCreator) {
          return const ChannelFinding.unreachable('This account no longer owns the channel.');
        }
        usernames = group.usernames?.activeUsernames ?? const [];
      }
      if (chat.messageAutoDeleteTime > 0) {
        return ChannelFinding.autoDelete(chat.messageAutoDeleteTime, supergroupId: supergroupId);
      }
      if (usernames.isNotEmpty) {
        return ChannelFinding.public(usernames.first, supergroupId: supergroupId);
      }
      return ChannelFinding.ok(supergroupId: supergroupId);
    } on TelegramException catch (e) {
      return ChannelFinding.unreachable(e.friendlyMessage);
    } catch (e) {
      debugPrint('[Checkup] channel: $e');
      return const ChannelFinding.unreachable('Telegram didn\'t answer.');
    }
  }

  IndexFinding _index(int chatId) {
    final sync = ref.read(driveSyncProvider);
    return IndexFinding(
      lastFull: _prefs.lastFullSync(chatId),
      error: sync.error,
      running: sync.running,
      scanned: sync.scanned,
    );
  }

  /// Null when the drive has no split files, so the row isn't shown.
  Future<SplitFinding?> _split() async {
    try {
      final total = await _db.countSplitFiles();
      if (total == 0) return null;
      final uploading = {
        for (final item in ref.read(transferQueueProvider).items)
          if (item.status.isPending) item.row.fileId,
      };
      final since = DateTime.now().subtract(settlesWithin);
      final incomplete = <IncompleteFile>[];
      for (final row in await _db.incompleteFiles()) {
        if (uploading.contains(row.id) || row.createdAt.isAfter(since)) continue;
        final present = {for (final part in await _repository.partsOf(row.id)) part.partIndex};
        incomplete.add((
          file: DriveFile.fromRow(row),
          missingParts: [
            for (var i = 0; i < row.partCount; i++)
              if (!present.contains(i)) i + 1,
          ],
        ));
      }
      return SplitFinding(total: total, incomplete: incomplete);
    } catch (e) {
      debugPrint('[Checkup] split files: $e');
      return null;
    }
  }

  Future<BackupFinding> _backup() async {
    if (!_prefs.backupEnabled) {
      return const BackupFinding(
        enabled: false,
        outcome: VerifyOutcome.skipped,
        verifiedCount: 0,
        missingCount: 0,
        verifiedAt: null,
      );
    }
    var outcome = VerifyOutcome.skipped;
    try {
      outcome = await ref.read(backupControllerProvider.notifier).verify();
    } catch (e) {
      debugPrint('[Checkup] backup: $e');
    }
    return BackupFinding(
      enabled: true,
      outcome: outcome,
      verifiedCount: await _db.countBackedUpWithFile(),
      missingCount: await _db.watchMissingCount().first,
      verifiedAt: _prefs.backupVerifiedAt,
    );
  }

  /// Null when the trash is empty, so the row isn't shown.
  Future<TrashFinding?> _trash() async {
    try {
      final contents = await _repository.watchTrash().first;
      if (contents.isEmpty) return null;
      final horizon = DateTime.now().add(TrashFinding.dueWithin);
      bool due(DateTime? trashedAt) =>
          trashedAt != null && trashedAt.add(DriveRepository.trashKeepsFor).isBefore(horizon);
      return TrashFinding(
        count: contents.count,
        dueSoon:
            contents.folders.where((f) => due(f.trashedAt)).length +
            contents.files.where((f) => due(f.trashedAt)).length,
      );
    } catch (e) {
      debugPrint('[Checkup] trash: $e');
      return null;
    }
  }

  Future<TwoStepFinding> _twoStep() async {
    try {
      final state = await _client.send<td.PasswordState>(const td.GetPasswordState());
      return TwoStepFinding(state.hasPassword);
    } catch (e) {
      debugPrint('[Checkup] two-step: $e');
      return const TwoStepFinding(null);
    }
  }

  Future<AccountTtlFinding> _accountTtl() async {
    try {
      final ttl = await _client.send<td.AccountTtl>(const td.GetAccountTtl());
      return AccountTtlFinding(ttl.days);
    } catch (e) {
      debugPrint('[Checkup] account timer: $e');
      return const AccountTtlFinding(null);
    }
  }

  // ---------------------------------------------------------------------------
  // Fixes. Each runs the check-up again once it is through, unless the
  // screen has gone by the time Telegram answers: the fix has applied
  // either way, and the next visit runs the check-up afresh.
  // ---------------------------------------------------------------------------

  /// Switches the channel's auto-delete timer off.
  Future<void> turnOffAutoDelete() async {
    final chatId = ref.read(driveSessionProvider)?.chatId;
    if (chatId == null) return;
    await _client.send<td.Ok>(
      td.SetChatMessageAutoDeleteTime(chatId: chatId, messageAutoDeleteTime: 0),
    );
    if (ref.mounted) ref.invalidateSelf();
  }

  /// Takes the channel's public link away.
  Future<void> makePrivate(int supergroupId) async {
    await _client.send<td.Ok>(td.SetSupergroupUsername(supergroupId: supergroupId, username: ''));
    if (ref.mounted) ref.invalidateSelf();
  }

  /// Sets after how many days without activity Telegram deletes the account.
  Future<void> setAccountTtl(int days) => ref.read(accountTtlProvider.notifier).set(days);

  /// Removes what is left of a split file that can't be opened any more.
  Future<void> deleteParts(String fileId) async {
    await _repository.deleteFileById(fileId);
    if (ref.mounted) ref.invalidateSelf();
  }
}

final driveCheckupProvider = AsyncNotifierProvider.autoDispose<DriveCheckup, CheckupReport>(
  DriveCheckup.new,
);

/// After how many days without activity Telegram deletes the account, and
/// the drive with it. Settings and the check-up read and set it here.
class AccountTtlNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final ttl = await ref
        .watch(telegramClientProvider)
        .send<td.AccountTtl>(const td.GetAccountTtl());
    return ttl.days;
  }

  /// Sets the timer to [days]. Telegram refuses a value it doesn't offer,
  /// and the old one stays. Nobody may be listening by the time Telegram
  /// answers; the timer is set either way, and only the value here goes
  /// unrecorded.
  Future<void> set(int days) async {
    await ref
        .read(telegramClientProvider)
        .send<td.Ok>(td.SetAccountTtl(ttl: td.AccountTtl(days: days)));
    if (!ref.mounted) return;
    state = AsyncData(days);
    ref.invalidate(driveCheckupProvider);
  }
}

final accountTtlProvider = AsyncNotifierProvider.autoDispose<AccountTtlNotifier, int>(
  AccountTtlNotifier.new,
);

/// When Check my drive last finished, for its row in Settings. It starts
/// from what the phone remembers and follows each run from then on.
class CheckupLastRun extends Notifier<DateTime?> {
  @override
  DateTime? build() => ref.watch(preferencesProvider).checkupLastRun;

  Future<void> set(DateTime at) async {
    await ref.read(preferencesProvider).setCheckupLastRun(at);
    state = at;
  }
}

final checkupLastRunProvider = NotifierProvider<CheckupLastRun, DateTime?>(CheckupLastRun.new);

/// This phone's entry in Telegram's Devices list, as 'Telegrive 1.0.0 ·
/// Pixel 8 · Android 15', or null when Telegram doesn't list it.
final currentSessionProvider = FutureProvider.autoDispose<String?>((ref) async {
  final sessions = await ref
      .watch(telegramClientProvider)
      .send<td.Sessions>(const td.GetActiveSessions());
  final current = sessions.sessions.where((s) => s.isCurrent).firstOrNull;
  if (current == null) return null;
  return '${current.applicationName} ${current.applicationVersion} · '
      '${current.deviceModel} · ${current.systemVersion}';
});
