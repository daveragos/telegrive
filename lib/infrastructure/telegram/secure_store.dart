import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/platform/app_platform.dart';

/// The device's keystore couldn't keep or hand back the database key: it
/// failed, or didn't answer within [SecureStore.timeout]. Some phones with
/// a changed system have a keystore that does neither, and a Linux desktop
/// may have no keyring running at all.
class SecureStoreException implements Exception {
  const SecureStoreException(this.cause);

  final Object cause;

  String get message => isLinux
      ? 'Telegrive keeps the key that protects its data in the system keyring, and '
            'none answered. Make sure GNOME Keyring or KWallet is running and unlocked, '
            'then try again.'
      : 'This ${AppPlatform.device}\'s secure storage isn\'t working, so Telegrive can\'t '
            'keep the key that protects its data. Try again, or restart the '
            '${AppPlatform.device} if it keeps happening.';

  /// Whether this is the Linux desktop, whose keyring is a separate service.
  @visibleForTesting
  static bool get isLinux => AppPlatform.isDesktop && !kIsWeb && Platform.isLinux;

  @override
  String toString() => 'SecureStoreException: $cause';
}

/// The key TDLib encrypts its local database with. It lives in the platform
/// keystore (Keychain, EncryptedSharedPreferences, Windows' data protection,
/// or the Secret Service keyring on Linux), never next to the data it
/// protects.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The data protection keychain takes an entitlement only a
            // signed, provisioned Mac app has; the login keychain is the
            // one an app from outside the App Store can use.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  /// Changing this orphans every existing TDLib database, so it is fixed.
  static const String _databaseKey = 'tdlib_database_key';

  /// How long the keystore gets to answer. A read or write takes it a moment
  /// at most; one that takes longer never answers.
  static const Duration timeout = Duration(seconds: 15);

  Future<String?> readDatabaseKey() => _read(_databaseKey);

  /// Throws [SecureStoreException] when the key couldn't be kept.
  Future<void> writeDatabaseKey(String key) async {
    try {
      await _storage.write(key: _databaseKey, value: key).timeout(timeout);
    } catch (e) {
      debugPrint('[SecureStore] write($_databaseKey) failed: $e');
      throw SecureStoreException(e);
    }
  }

  Future<void> clearDatabaseKey() => _storage.delete(key: _databaseKey);

  /// 256 random bits from the platform CSPRNG.
  ///
  /// Standard base64, not base64url: TDLib's JSON interface carries `bytes`
  /// fields as base64 and rejects `-` and `_`.
  static String generateDatabaseKey() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  /// The value under [key], or null when there is none or it couldn't be
  /// read. A keystore that doesn't answer throws [SecureStoreException]
  /// instead: taking its silence for no key would make a new one, and start
  /// the database, and the sign-in in it, over. So does any failure on a
  /// computer, where it means the keychain or keyring is locked or missing
  /// rather than a key that no longer opens; a phone's restored data
  /// without its keystore entry is the case the null is for.
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key).timeout(timeout);
    } on TimeoutException catch (e) {
      debugPrint('[SecureStore] read($key) timed out');
      throw SecureStoreException(e);
    } catch (e) {
      debugPrint('[SecureStore] read($key) failed: $e');
      if (AppPlatform.isDesktop) throw SecureStoreException(e);
      return null;
    }
  }
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
