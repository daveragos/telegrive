import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The key TDLib encrypts its local database with. It lives in the platform
/// keystore (Keychain / EncryptedSharedPreferences), never next to the data
/// it protects.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Changing this orphans every existing TDLib database, so it is fixed.
  static const String _databaseKey = 'tdlib_database_key';

  Future<String?> readDatabaseKey() => _read(_databaseKey);

  Future<void> writeDatabaseKey(String key) =>
      _storage.write(key: _databaseKey, value: key);

  Future<void> clearDatabaseKey() => _storage.delete(key: _databaseKey);

  /// 256 random bits from the platform CSPRNG.
  ///
  /// Standard base64, not base64url: TDLib's JSON interface carries `bytes`
  /// fields as base64 and rejects `-` and `_`.
  static String generateDatabaseKey() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[SecureStore] read($key) failed: $e');
      return null;
    }
  }
}

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
