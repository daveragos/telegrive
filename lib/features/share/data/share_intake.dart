import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file another app shared into Telegrive, already copied into the cache.
@immutable
class SharedFile {
  const SharedFile({required this.path, required this.name, required this.size});

  factory SharedFile.fromMap(Map<Object?, Object?> map) => SharedFile(
    path: map['path']! as String,
    name: map['name']! as String,
    size: (map['size']! as num).toInt(),
  );

  final String path;
  final String name;
  final int size;
}

/// "Share to Telegrive" from any app (Android). The activity copies what
/// arrives into the cache and holds it until the drive is open to take it.
class ShareIntake extends Notifier<List<SharedFile>> {
  static const _channel = MethodChannel('telegrive/share');

  @override
  List<SharedFile> build() {
    if (kIsWeb || !Platform.isAndroid) return const [];
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedAvailable') await _take();
    });
    ref.onDispose(() => _channel.setMethodCallHandler(null));
    unawaited(_take());
    return const [];
  }

  Future<void> _take() async {
    try {
      final items = await _channel.invokeListMethod<Map<Object?, Object?>>('takeShared');
      if (items == null || items.isEmpty) return;
      state = [...state, ...items.map(SharedFile.fromMap)];
    } catch (e) {
      debugPrint('[Share] $e');
    }
  }

  /// Forgets the waiting files; with [discard], deletes their copies too.
  Future<void> clear({bool discard = false}) async {
    final files = state;
    state = const [];
    if (!discard) return;
    for (final file in files) {
      try {
        await File(file.path).parent.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final shareIntakeProvider = NotifierProvider<ShareIntake, List<SharedFile>>(
  ShareIntake.new,
);
