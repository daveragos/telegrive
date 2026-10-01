import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file another app shared into Telegrive: a copy in the cache, or a
/// gallery photo or video right where it is.
@immutable
class SharedFile {
  const SharedFile({
    required this.path,
    required this.name,
    required this.size,
    this.owned = true,
    this.folderId,
  });

  factory SharedFile.fromMap(Map<Object?, Object?> map) => SharedFile(
    path: map['path']! as String,
    name: map['name']! as String,
    size: (map['size']! as num).toInt(),
    owned: map['owned'] as bool? ?? true,
    folderId: map['folderId'] as String?,
  );

  /// The files in what the activity hands over that can be uploaded. One
  /// the phone had no room to copy comes without a path, and is left out.
  static List<SharedFile> listFrom(Iterable<Map<Object?, Object?>> maps) => [
    for (final map in maps)
      if (map['tooBig'] != true) SharedFile.fromMap(map),
  ];

  final String path;
  final String name;
  final int size;

  /// Whether [path] is Telegrive's own copy, which goes once it is uploaded
  /// or the share is cancelled. An original from the gallery never does.
  final bool owned;

  /// The drive folder whose target in Android's share sheet it was shared
  /// to, or null when it came through the plain Telegrive target.
  final String? folderId;
}

/// "Share to Telegrive" from any app (Android). The activity copies what
/// arrives into the cache, unless it can be read where it is, and holds it
/// until the drive is open to take it.
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
      state = [...state, ...SharedFile.listFrom(items)];
    } catch (e) {
      debugPrint('[Share] $e');
    }
  }

  /// Forgets the waiting files; with [discard], deletes Telegrive's own
  /// copies of them too.
  Future<void> clear({bool discard = false}) async {
    final files = state;
    state = const [];
    if (!discard) return;
    for (final file in files.where((f) => f.owned)) {
      try {
        await File(file.path).parent.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final shareIntakeProvider = NotifierProvider<ShareIntake, List<SharedFile>>(
  ShareIntake.new,
);
