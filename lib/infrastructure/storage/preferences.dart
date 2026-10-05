import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `bootstrap.dart` with an instance loaded before the first
/// frame, so every read here is synchronous.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Loaded in bootstrap'),
);

final preferencesProvider = Provider<Preferences>(
  (ref) => Preferences(ref.watch(sharedPreferencesProvider)),
);

enum ViewMode { list, grid }

/// Typed access to the small amount of non-secret state the app keeps.
class Preferences {
  Preferences(this._prefs);

  final SharedPreferences _prefs;

  ThemeMode get themeMode => ThemeMode.values.firstWhere(
    (m) => m.name == _prefs.getString('theme_mode'),
    orElse: () => ThemeMode.system,
  );
  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString('theme_mode', mode.name);

  ViewMode get viewMode => ViewMode.values.firstWhere(
    (m) => m.name == _prefs.getString('view_mode'),
    orElse: () => ViewMode.list,
  );
  Future<void> setViewMode(ViewMode mode) =>
      _prefs.setString('view_mode', mode.name);

  /// Reading the words in documents for search, or [fallback] until the
  /// person has turned it on or off.
  bool contentSearchOr(bool fallback) =>
      _prefs.getBool('content_search') ?? fallback;
  Future<void> setContentSearch(bool on) =>
      _prefs.setBool('content_search', on);

  /// Save memory as the person set it in Settings, or null while it still
  /// follows what kind of phone this is.
  bool? get saveMemory => _prefs.getBool('save_memory');
  Future<void> setSaveMemory(bool on) => _prefs.setBool('save_memory', on);

  bool get appLock => _prefs.getBool('app_lock') ?? false;
  Future<void> setAppLock(bool on) => _prefs.setBool('app_lock', on);

  /// Whether the person wants the drive in Android's file picker. Off until
  /// switched on, and set back to off when the drive leaves the phone. App
  /// lock keeps the picker off without changing this.
  bool get pickerEnabled => _prefs.getBool('picker_enabled') ?? false;
  Future<void> setPickerEnabled(bool on) =>
      _prefs.setBool('picker_enabled', on);

  /// Name of the app lock's delay, see `LockAfter`.
  String? get appLockAfter => _prefs.getString('app_lock_after');
  Future<void> setAppLockAfter(String name) =>
      _prefs.setString('app_lock_after', name);

  /// How many photos across the Photos grid shows; pinch changes it.
  int get photoColumns => _prefs.getInt('photo_columns') ?? 4;
  Future<void> setPhotoColumns(int columns) =>
      _prefs.setInt('photo_columns', columns);

  /// The playback speed the player last used for audio, or for video, so a
  /// newly opened file of that kind starts at it. The player checks the
  /// value against the speeds it offers.
  double playbackSpeed({required bool audio}) =>
      _prefs.getDouble(audio ? _speedAudio : _speedVideo) ?? 1.0;
  Future<void> setPlaybackSpeed(double speed, {required bool audio}) =>
      _prefs.setDouble(audio ? _speedAudio : _speedVideo, speed);

  static const String _speedAudio = 'play_speed_audio';
  static const String _speedVideo = 'play_speed_video';

  String? get sortField => _prefs.getString('sort_field');
  bool get sortDescending => _prefs.getBool('sort_descending') ?? false;
  Future<void> setSort(String field, {required bool descending}) async {
    await _prefs.setString('sort_field', field);
    await _prefs.setBool('sort_descending', descending);
  }

  /// The drive channel, per Telegram account so switching accounts never
  /// points one person's app at another's files.
  int? driveChatId(int userId) => _prefs.getInt('drive_chat_$userId');
  Future<void> setDriveChatId(int userId, int chatId) =>
      _prefs.setInt('drive_chat_$userId', chatId);
  Future<void> clearDriveChatId(int userId) =>
      _prefs.remove('drive_chat_$userId');

  /// The account and channel of the drive last opened here, as JSON
  /// without the phone number, so Home can show the drive before Telegram
  /// answers. The wipe removes it with the drive.
  String? get driveSnapshot => _prefs.getString('drive_snapshot');
  Future<void> setDriveSnapshot(String json) =>
      _prefs.setString('drive_snapshot', json);
  Future<void> clearDriveSnapshot() => _prefs.remove('drive_snapshot');

  /// Newest channel message already in the index; incremental syncs stop
  /// when they reach it.
  int lastSyncedMessageId(int chatId) =>
      _prefs.getInt('synced_upto_$chatId') ?? 0;
  Future<void> setLastSyncedMessageId(int chatId, int messageId) =>
      _prefs.setInt('synced_upto_$chatId', messageId);

  DateTime? lastFullSync(int chatId) {
    final millis = _prefs.getInt('full_sync_$chatId');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastFullSync(int chatId, DateTime at) =>
      _prefs.setInt('full_sync_$chatId', at.millisecondsSinceEpoch);

  /// The MessageIndexer.version of the last full read of the channel. An
  /// index from before this was recorded was built by version 1.
  int indexedWith(int chatId) => _prefs.getInt('indexed_with_$chatId') ?? 1;
  Future<void> setIndexedWith(int chatId, int version) =>
      _prefs.setInt('indexed_with_$chatId', version);

  /// The newest channel message the forward filer has looked at, or null
  /// before it has run on this index. Only manifest-less media newer than
  /// this is filed by its comment, so what was in the channel before the
  /// filer first ran never moves on its own.
  int? forwardFilingFrom(int chatId) =>
      _prefs.getInt('forward_filing_from_$chatId');
  Future<void> setForwardFilingFrom(int chatId, int messageId) =>
      _prefs.setInt('forward_filing_from_$chatId', messageId);

  /// The drive message pinned in the channel, as this phone last saw it,
  /// so opening the drive asks Telegram for that one message rather than
  /// looking for it.
  int? driveCardId(int chatId) => _prefs.getInt('drive_card_$chatId');
  Future<void> setDriveCardId(int chatId, int messageId) =>
      _prefs.setInt('drive_card_$chatId', messageId);

  /// When this phone last wrote the copy of the index into the channel,
  /// and a fingerprint of what it held, so an unchanged index isn't sent
  /// again.
  DateTime? indexCopyAt(int chatId) {
    final millis = _prefs.getInt('index_copy_at_$chatId');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  int? indexCopyPrint(int chatId) => _prefs.getInt('index_copy_print_$chatId');

  Future<void> setIndexCopy(int chatId, DateTime at, int print) async {
    await _prefs.setInt('index_copy_at_$chatId', at.millisecondsSinceEpoch);
    await _prefs.setInt('index_copy_print_$chatId', print);
  }

  /// Per-channel keys that describe what this phone knows of the channel,
  /// so they go with the index.
  static const List<String> _syncKeys = [
    'synced_upto_',
    'full_sync_',
    'indexed_with_',
    'forward_filing_from_',
    'drive_card_',
    'index_copy_at_',
    'index_copy_print_',
  ];

  Future<void> clearSyncState(int chatId) async {
    for (final key in _syncKeys) {
      await _prefs.remove('$key$chatId');
    }
  }

  /// Channels this phone keeps sync progress for, whichever account they
  /// belong to.
  Set<int> get syncedChatIds => {
    for (final key in _prefs.getKeys())
      for (final prefix in _syncKeys)
        if (key.startsWith(prefix)) ?int.tryParse(key.substring(prefix.length)),
  };

  /// Transfers of 200 MB or more that start without anyone being asked wait
  /// for Wi-Fi, so moving onto mobile data mid-way doesn't spend the plan.
  /// On until switched off.
  bool get bigTransfersWifiOnly =>
      _prefs.getBool('big_transfers_wifi_only') ?? true;
  Future<void> setBigTransfersWifiOnly(bool on) =>
      _prefs.setBool('big_transfers_wifi_only', on);

  /// Files kept offline download only over Wi-Fi, whatever their size. Off
  /// until switched on, on the Offline screen or in the sheet that keeps a
  /// folder.
  bool get offlineWifiOnly => _prefs.getBool('offline_wifi_only') ?? false;
  Future<void> setOfflineWifiOnly(bool on) =>
      _prefs.setBool('offline_wifi_only', on);

  /// When the daily trim of what Telegrive keeps on the phone last ran.
  DateTime? get cacheSweptAt {
    final millis = _prefs.getInt('cache_swept_at');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setCacheSweptAt(DateTime at) =>
      _prefs.setInt('cache_swept_at', at.millisecondsSinceEpoch);
  Future<void> forgetCacheSweptAt() => _prefs.remove('cache_swept_at');

  /// Whether transfers have asked for permission to post notifications.
  /// They ask once, the first time one starts, and never again; Settings
  /// says when notifications are off.
  bool get notificationsAsked => _prefs.getBool('notifications_asked') ?? false;
  Future<void> setNotificationsAsked() =>
      _prefs.setBool('notifications_asked', true);

  bool get hasSeenWelcome => _prefs.getBool('seen_welcome') ?? false;
  Future<void> setSeenWelcome() => _prefs.setBool('seen_welcome', true);

  /// The account whose drive the local index holds. A different account
  /// signing in wipes the index before its own drive opens, so nobody ever
  /// sees another person's files on a shared phone. The wipe clears it with
  /// the index it names.
  int? get lastUserId => _prefs.getInt('last_user_id');
  Future<void> setLastUserId(int userId) => _prefs.setInt('last_user_id', userId);
  Future<void> clearLastUserId() => _prefs.remove('last_user_id');

  /// When Telegram ended this phone's session without the person signing
  /// out here, or null. Welcome explains it, and the local data is wiped
  /// once it is seven days old. Cleared on sign-in and by the wipe.
  DateTime? get sessionEndedAt => _dateTime('session_ended_at');
  Future<void> setSessionEndedAt(DateTime at) =>
      _prefs.setInt('session_ended_at', at.millisecondsSinceEpoch);
  Future<void> clearSessionEnded() => _prefs.remove('session_ended_at');

  /// When Check my drive last finished, for its row in Settings. The wipe
  /// clears it with the drive it described.
  DateTime? get checkupLastRun => _dateTime('checkup_last_run');
  Future<void> setCheckupLastRun(DateTime at) =>
      _prefs.setInt('checkup_last_run', at.millisecondsSinceEpoch);
  Future<void> clearCheckupLastRun() => _prefs.remove('checkup_last_run');

  /// When backed-up photos were last matched against the index. The wipe
  /// clears it with the index.
  DateTime? get backupVerifiedAt => _dateTime('backup_verified_at');
  Future<void> setBackupVerifiedAt(DateTime at) =>
      _prefs.setInt('backup_verified_at', at.millisecondsSinceEpoch);
  Future<void> clearBackupVerified() => _prefs.remove('backup_verified_at');

  DateTime? _dateTime(String key) {
    final millis = _prefs.getInt(key);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// The chats this phone last sent files to, newest first, which the chat
  /// picker lists right after Saved Messages. They stay on this phone
  /// rather than in the channel.
  List<int> get recentSendChats => [
    for (final id in _prefs.getStringList(_recentSendChats) ?? const <String>[])
      ?int.tryParse(id),
  ];

  /// Puts [chatIds] at the front of [recentSendChats], which keeps five.
  Future<void> rememberSentTo(Iterable<int> chatIds) => _prefs.setStringList(
    _recentSendChats,
    [
      for (final id in {...chatIds, ...recentSendChats}.take(_recentSendLimit))
        '$id',
    ],
  );

  Future<void> forgetRecentSendChats() => _prefs.remove(_recentSendChats);

  static const String _recentSendChats = 'recent_send_chats';
  static const int _recentSendLimit = 5;

  // ---------------------------------------------------------------------------
  // Photo backup. Keys are shared with the background worker, which reads
  // them from its own isolate — see [BackupPrefKeys].
  // ---------------------------------------------------------------------------

  bool get backupEnabled => _prefs.getBool(BackupPrefKeys.enabled) ?? false;
  Future<void> setBackupEnabled(bool value) =>
      _prefs.setBool(BackupPrefKeys.enabled, value);

  bool get backupVideos => _prefs.getBool(BackupPrefKeys.videos) ?? true;
  Future<void> setBackupVideos(bool value) =>
      _prefs.setBool(BackupPrefKeys.videos, value);

  /// What backup sends over mobile data; see [BackupPrefKeys.mobileDataOf].
  BackupMobileData get backupMobileData => BackupPrefKeys.mobileDataOf(_prefs);
  Future<void> setBackupMobileData(BackupMobileData value) =>
      _prefs.setString(BackupPrefKeys.mobileData, value.name);

  /// Whether a photo that can't go up in full right now, on mobile data
  /// backup may not use for it or past the monthly limit, goes up as a
  /// small copy, with the original following once it may. Off until
  /// switched on.
  bool get backupSmallCopies => _prefs.getBool(_backupSmallCopies) ?? false;
  Future<void> setBackupSmallCopies(bool on) => _prefs.setBool(_backupSmallCopies, on);

  static const String _backupSmallCopies = 'backup_small_copies';

  /// Device folders ("WhatsApp Images", "Screenshots") left out of backup.
  /// Everything else — including folders that appear later — is included.
  Set<String> get backupExcludedFolders =>
      (_prefs.getStringList('backup_excluded_folders') ?? const []).toSet();
  Future<void> setBackupExcludedFolders(Set<String> folders) =>
      _prefs.setStringList('backup_excluded_folders', folders.toList()..sort());

  /// Device folders whose backups stay out of the Photos timeline and its
  /// Favorites and Videos. They still back up and show in Files and Search.
  static const Set<String> defaultPhotosHiddenFolders = {
    'Screenshots',
    'WhatsApp Images',
    'WhatsApp Video',
    'Telegram',
    'Telegram Images',
    'Telegram Video',
  };

  /// [defaultPhotosHiddenFolders] until the person picks for themselves; an
  /// empty set then means every folder shows in Photos.
  Set<String> get photosHiddenFolders {
    final list = _prefs.getStringList('photos_hidden_folders');
    return list == null ? defaultPhotosHiddenFolders : list.toSet();
  }

  Future<void> setPhotosHiddenFolders(Set<String> folders) =>
      _prefs.setStringList('photos_hidden_folders', folders.toList()..sort());

  DateTime? get backupLastCompleted {
    final millis = _prefs.getInt('backup_last_completed');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Marks everything captured up to [at] as dealt with; the background
  /// check only counts photos newer than this.
  Future<void> setBackupCompleted(DateTime at) async {
    await _prefs.setInt('backup_last_completed', at.millisecondsSinceEpoch);
    await _prefs.setInt(BackupPrefKeys.checkpoint, at.millisecondsSinceEpoch);
    await _prefs.remove(BackupPrefKeys.notifiedCount);
    await _prefs.remove(BackupPrefKeys.remindAfter);
  }

  /// Whether backup also runs on its own while the phone charges, with the
  /// app closed. Off until switched on.
  bool get backupUnattended => _prefs.getBool(BackupPrefKeys.unattended) ?? false;
  Future<void> setBackupUnattended(bool on) =>
      _prefs.setBool(BackupPrefKeys.unattended, on);

  /// When the last pass that left everything dealt with started; photos
  /// added to the phone since then are the ones a pass has to look at.
  DateTime? get backupCheckpoint => _dateTime(BackupPrefKeys.checkpoint);

  /// When a pass last looked through the whole library, or null when the
  /// next one has to: what is backed up changed, or a photo left the phone.
  DateTime? get backupLastFullScan => _dateTime(_lastFullScan);

  /// How many of backup's records were for photos the last look through the
  /// whole library didn't find: deleted from the phone, or in folders left
  /// out. Passes in between count from the records, and take these off.
  int get backupUnfoundRecords => _prefs.getInt(_unfoundRecords) ?? 0;

  Future<void> setBackupFullScan(DateTime at, {required int unfound}) async {
    await _prefs.setInt(_lastFullScan, at.millisecondsSinceEpoch);
    await _prefs.setInt(_unfoundRecords, unfound);
  }

  /// Makes the next pass look through the whole library.
  Future<void> forgetBackupFullScan() async {
    await _prefs.remove(_lastFullScan);
    await _prefs.remove(_unfoundRecords);
  }

  static const String _lastFullScan = 'backup_last_full_scan';
  static const String _unfoundRecords = 'backup_unfound_records';

  /// When a background job last looked for new photos: the check, or the
  /// job that backs them up. Written from the jobs' own engines.
  DateTime? get backgroundChecked => _dateTime(BackupPrefKeys.lastChecked);
  Future<void> setBackgroundChecked(DateTime at) =>
      _prefs.setInt(BackupPrefKeys.lastChecked, at.millisecondsSinceEpoch);

  /// When the background backup job last ran a pass, and how many photos
  /// it sent up then.
  DateTime? get backgroundRun => _dateTime(BackupPrefKeys.lastRun);
  int get backgroundUploaded => _prefs.getInt(BackupPrefKeys.lastUploaded) ?? 0;

  Future<void> setBackgroundRun(DateTime at, int uploaded) async {
    await _prefs.setInt(BackupPrefKeys.lastRun, at.millisecondsSinceEpoch);
    await _prefs.setInt(BackupPrefKeys.lastUploaded, uploaded);
  }

  Future<void> forgetBackgroundRun() async {
    await _prefs.remove(BackupPrefKeys.lastRun);
    await _prefs.remove(BackupPrefKeys.lastUploaded);
  }

  /// Whether the "back up your photos?" question has been asked.
  bool get backupPromptShown => _prefs.getBool('backup_prompt_shown') ?? false;
  Future<void> setBackupPromptShown() =>
      _prefs.setBool('backup_prompt_shown', true);

  /// The last answer to 'Also delete from this phone' when trashing photos
  /// this phone still has; off until someone ticks it.
  bool get deletePhoneCopyToo =>
      _prefs.getBool('delete_phone_copy_too') ?? false;
  Future<void> setDeletePhoneCopyToo(bool on) =>
      _prefs.setBool('delete_phone_copy_too', on);

  /// Name of how much of the newest Free up space keeps on the phone, see
  /// `KeepWindow`.
  String? get freeUpKeep => _prefs.getString('free_up_keep');
  Future<void> setFreeUpKeep(String name) =>
      _prefs.setString('free_up_keep', name);

  /// The drive folders this phone last uploaded into, most recent first,
  /// with '' for the root. Folder ids belong to one drive, so the list goes
  /// when the drive leaves the phone.
  List<String> get recentDestinations =>
      _prefs.getStringList('recent_destinations') ?? const [];
  Future<void> setRecentDestinations(List<String> ids) =>
      _prefs.setStringList('recent_destinations', ids);
  Future<void> clearRecentDestinations() =>
      _prefs.remove('recent_destinations');

  // ---------------------------------------------------------------------------
  // The monthly mobile data limit and what the current period has used.
  // They describe the phone's data plan rather than the drive, so they stay
  // when an account signs out.
  // ---------------------------------------------------------------------------

  /// The monthly mobile data limit in bytes, or null for none.
  int? get dataLimitBytes => _prefs.getInt('data_limit_bytes');

  /// The day of the month the data plan renews on, 1 to 28.
  int get dataRenewDay =>
      (_prefs.getInt('data_limit_renew_day') ?? 1).clamp(1, 28);

  Future<void> setDataLimit(int? bytes, int renewDay) async {
    if (bytes == null) {
      await _prefs.remove('data_limit_bytes');
    } else {
      await _prefs.setInt('data_limit_bytes', bytes);
    }
    await _prefs.setInt('data_limit_renew_day', renewDay);
  }

  /// Where the count for the current period stands, or null before one has
  /// started.
  DataPeriodSnapshot? get dataPeriod {
    int? read(String key) => _prefs.getInt(key);
    final start = read(_DataKeys.start);
    final mobileBase = read(_DataKeys.mobileBase);
    final wifiBase = read(_DataKeys.wifiBase);
    final mobileCarry = read(_DataKeys.mobileCarry);
    final wifiCarry = read(_DataKeys.wifiCarry);
    final since = read(_DataKeys.since);
    if (start == null ||
        mobileBase == null ||
        wifiBase == null ||
        mobileCarry == null ||
        wifiCarry == null ||
        since == null) {
      return null;
    }
    return (
      start: start,
      mobileBase: mobileBase,
      wifiBase: wifiBase,
      mobileCarry: mobileCarry,
      wifiCarry: wifiCarry,
      since: since,
    );
  }

  Future<void> setDataPeriod(DataPeriodSnapshot period) async {
    await _prefs.setInt(_DataKeys.start, period.start);
    await _prefs.setInt(_DataKeys.mobileBase, period.mobileBase);
    await _prefs.setInt(_DataKeys.wifiBase, period.wifiBase);
    await _prefs.setInt(_DataKeys.mobileCarry, period.mobileCarry);
    await _prefs.setInt(_DataKeys.wifiCarry, period.wifiCarry);
    await _prefs.setInt(_DataKeys.since, period.since);
  }

  /// Drops the current period, so the next count starts a new one.
  Future<void> clearDataPeriod() async {
    for (final key in _DataKeys.all) {
      await _prefs.remove(key);
    }
  }
}

/// How far the current data period's count has got, in TDLib's terms.
///
/// * [start]: when the period began, in milliseconds since the epoch.
/// * [mobileBase], [wifiBase]: TDLib's cumulative mobile and Wi-Fi counters
///   when [mobileCarry] and [wifiCarry] were last brought up to date.
/// * [mobileCarry], [wifiCarry]: bytes this period had used by then,
///   including what was counted before TDLib's counters last restarted.
/// * [since]: the date TDLib counts from (its NetworkStatistics.sinceDate,
///   in seconds). A different one means its counters restarted, after a
///   sign-out or a reset of its database.
typedef DataPeriodSnapshot = ({
  int start,
  int mobileBase,
  int wifiBase,
  int mobileCarry,
  int wifiCarry,
  int since,
});

abstract final class _DataKeys {
  static const String start = 'data_period_start';
  static const String mobileBase = 'data_mobile_baseline';
  static const String wifiBase = 'data_wifi_baseline';
  static const String mobileCarry = 'data_mobile_carry';
  static const String wifiCarry = 'data_wifi_carry';
  static const String since = 'data_stats_since';
  static const List<String> all = [
    start,
    mobileBase,
    wifiBase,
    mobileCarry,
    wifiCarry,
    since,
  ];
}

/// What photo backup may send over mobile data, a phone's hotspot included.
enum BackupMobileData {
  /// Nothing: backup waits for Wi-Fi.
  off,

  /// Photos; videos wait for Wi-Fi.
  photos,

  /// Photos and videos.
  all,
}

/// Preference keys the background worker reads without the rest of the app.
abstract final class BackupPrefKeys {
  static const String enabled = 'backup_enabled';
  static const String videos = 'backup_videos';
  static const String checkpoint = 'backup_checkpoint';
  static const String notifiedCount = 'backup_notified_count';
  static const String mobileData = 'backup_mobile_data';

  /// Backing up on its own while the phone charges; see
  /// [Preferences.backupUnattended].
  static const String unattended = 'backup_unattended';

  /// When a background job last looked for new photos, in milliseconds
  /// since the epoch.
  static const String lastChecked = 'backup_bg_last_checked';

  /// When the background backup job last ran a pass, in milliseconds since
  /// the epoch, and how many photos it sent up.
  static const String lastRun = 'backup_bg_last_run';
  static const String lastUploaded = 'backup_bg_last_uploaded';

  /// When, in milliseconds since the epoch, the background check may post
  /// the backup reminder again after it was swiped away. A finished backup
  /// pass clears it.
  static const String remindAfter = 'backup_remind_after';

  /// The switch [mobileData] took over from: true meant Wi-Fi only. It is
  /// read until a choice is saved, and never written.
  static const String _wifiOnly = 'backup_wifi_only';

  /// What backup may send over mobile data, from the app or the worker's
  /// isolate. A phone that never chose keeps the old switch's answer: Wi-Fi
  /// only, or never set, reads as [BackupMobileData.off], and mobile data
  /// allowed as [BackupMobileData.all].
  static BackupMobileData mobileDataOf(SharedPreferences prefs) {
    final saved = prefs.getString(mobileData);
    for (final value in BackupMobileData.values) {
      if (value.name == saved) return value;
    }
    return (prefs.getBool(_wifiOnly) ?? true)
        ? BackupMobileData.off
        : BackupMobileData.all;
  }
}
