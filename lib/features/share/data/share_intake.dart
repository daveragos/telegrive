import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file another app shared into Telegrive: a copy in the cache, a
/// gallery photo or video right where it is, or one the phone had no room
/// to take.
@immutable
class SharedFile {
  const SharedFile({
    required this.path,
    required this.name,
    required this.size,
    this.owned = true,
    this.tooBig = false,
    this.free,
    this.folderId,
  });

  factory SharedFile.fromMap(Map<Object?, Object?> map) => SharedFile(
    path: map['path'] as String?,
    name: map['name']! as String,
    size: (map['size']! as num).toInt(),
    owned: map['owned'] as bool? ?? true,
    tooBig: map['tooBig'] as bool? ?? false,
    free: (map['free'] as num?)?.toInt(),
    folderId: map['folderId'] as String?,
  );

  /// What the activity hands over, the files the phone had no room to take
  /// included, so the share sheet can say so.
  static List<SharedFile> listFrom(Iterable<Map<Object?, Object?>> maps) => [
    for (final map in maps) SharedFile.fromMap(map),
  ];

  /// Where the file is on the phone, or null when it was [tooBig] to take.
  final String? path;
  final String name;
  final int size;

  /// Whether [path] is Telegrive's own copy, which goes once it is uploaded
  /// or the share is cancelled. An original from the gallery never does.
  final bool owned;

  /// The phone had too little room to copy it, so nothing was kept and it
  /// can't be uploaded; [free] is the space it had.
  final bool tooBig;
  final int? free;

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
    for (final file in files) {
      final path = file.path;
      if (!file.owned || path == null) continue;
      try {
        await File(path).parent.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final shareIntakeProvider = NotifierProvider<ShareIntake, List<SharedFile>>(
  ShareIntake.new,
);
