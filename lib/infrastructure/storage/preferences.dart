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

  /// Reading text and objects in photos and documents for search.
  bool get contentSearch => _prefs.getBool('content_search') ?? true;
  Future<void> setContentSearch(bool on) => _prefs.setBool('content_search', on);

  bool get appLock => _prefs.getBool('app_lock') ?? false;
  Future<void> setAppLock(bool on) => _prefs.setBool('app_lock', on);

  /// Name of the app lock's delay, see `LockAfter`.
  String? get appLockAfter => _prefs.getString('app_lock_after');
  Future<void> setAppLockAfter(String name) =>
      _prefs.setString('app_lock_after', name);

  /// How many photos across the Photos grid shows; pinch changes it.
  int get photoColumns => _prefs.getInt('photo_columns') ?? 4;
  Future<void> setPhotoColumns(int columns) =>
      _prefs.setInt('photo_columns', columns);

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

  /// Per-channel keys that describe what the local index holds, so they
  /// are only true while it is.
  static const List<String> _syncKeys = [
    'synced_upto_',
    'full_sync_',
    'indexed_with_',
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

  bool get hasSeenWelcome => _prefs.getBool('seen_welcome') ?? false;
  Future<void> setSeenWelcome() => _prefs.setBool('seen_welcome', true);

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

  /// Back up only on Wi-Fi (the default), or on mobile data too.
  bool get backupWifiOnly => _prefs.getBool('backup_wifi_only') ?? true;
  Future<void> setBackupWifiOnly(bool value) =>
      _prefs.setBool('backup_wifi_only', value);

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
  }

  /// Whether the "back up your photos?" question has been asked.
  bool get backupPromptShown => _prefs.getBool('backup_prompt_shown') ?? false;
  Future<void> setBackupPromptShown() =>
      _prefs.setBool('backup_prompt_shown', true);

  /// The last answer to 'Also delete from this phone' when trashing photos
  /// this phone still has; off until someone ticks it.
  bool get deletePhoneCopyToo => _prefs.getBool('delete_phone_copy_too') ?? false;
  Future<void> setDeletePhoneCopyToo(bool on) =>
      _prefs.setBool('delete_phone_copy_too', on);
}

/// Preference keys the background worker reads without the rest of the app.
abstract final class BackupPrefKeys {
  static const String enabled = 'backup_enabled';
  static const String videos = 'backup_videos';
  static const String checkpoint = 'backup_checkpoint';
  static const String notifiedCount = 'backup_notified_count';
}
