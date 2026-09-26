import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/telegram_client.dart';
import 'drive_repository.dart';

/// Local path of a server-made thumbnail, fetched at low priority the first
/// time a tile asks for it. Paths stay cached once resolved.
final thumbnailPathProvider = FutureProvider.autoDispose.family<String?, int>((
  ref,
  tdFileId,
) async {
  final client = ref.watch(telegramClientProvider);
  try {
    final file = await client.send<td.File>(
      td.DownloadFile(
        fileId: tdFileId,
        priority: 1,
        offset: 0,
        limit: 0,
        synchronous: true,
      ),
      timeout: const Duration(minutes: 2),
    );
    if (!file.local.isDownloadingCompleted) return null;
    ref.keepAlive();
    return file.local.path;
  } catch (e) {
    debugPrint('[Thumbnail] $tdFileId: $e');
    return null;
  }
});

/// Progress of fetching a file for in-app preview.
@immutable
class PreviewProgress {
  const PreviewProgress({required this.received, required this.total, this.path});

  final int received;
  final int total;

  /// Set once the file is fully on the device.
  final String? path;

  bool get isReady => path != null;
  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

/// Fetches a single-part file for the viewer without putting it in the
/// Transfers list — looking at a photo is not a transfer anyone needs to
/// manage. Leaving the viewer early stops the fetch.
final filePreviewProvider = StreamProvider.autoDispose
    .family<PreviewProgress, String>((ref, fileId) async* {
      final client = ref.watch(telegramClientProvider);
      final repository = ref.watch(driveRepositoryProvider);

      final parts = await repository.partsOf(fileId);
      if (parts.length != 1) {
        throw const DriveException('This file is too large to preview.');
      }
      final file = await repository.resolveTdFile(parts.first);
      final total = file.size != 0 ? file.size : file.expectedSize;

      if (file.local.isDownloadingCompleted &&
          await File(file.local.path).exists()) {
        yield PreviewProgress(received: total, total: total, path: file.local.path);
        return;
      }

      var finished = false;
      ref.onDispose(() {
        if (finished) return;
        unawaited(
          client
              .send<td.Ok>(
                td.CancelDownloadFile(fileId: file.id, onlyIfPending: false),
              )
              .then<void>((_) {}, onError: (Object _) {}),
        );
      });

      final updates = StreamController<PreviewProgress>();
      final subscription = client.fileUpdates
          .where((f) => f.id == file.id)
          .listen((f) {
            if (f.local.isDownloadingCompleted) {
              finished = true;
              updates.add(
                PreviewProgress(received: total, total: total, path: f.local.path),
              );
              updates.close();
            } else {
              updates.add(
                PreviewProgress(received: f.local.downloadedSize, total: total),
              );
            }
          });
      ref.onDispose(subscription.cancel);

      yield PreviewProgress(received: file.local.downloadedSize, total: total);
      final result = await client.send<td.File>(
        td.DownloadFile(
          fileId: file.id,
          priority: 32,
          offset: 0,
          limit: 0,
          synchronous: false,
        ),
      );
      if (result.local.isDownloadingCompleted) {
        finished = true;
        yield PreviewProgress(received: total, total: total, path: result.local.path);
        return;
      }
      yield* updates.stream;
    });
