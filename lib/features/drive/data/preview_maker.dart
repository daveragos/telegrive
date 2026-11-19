import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/media/media_probe.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/device_storage.dart';
import '../../../infrastructure/telegram/telegram_exception.dart';
import '../../files/data/bulk_edits.dart';
import '../../transfers/data/room.dart';
import '../../transfers/data/transfer_queue.dart';
import '../domain/drive_models.dart';
import 'drive_repository.dart';

/// Gives photos and videos that have no preview from Telegram one each: a
/// video sent as a file, a HEIC photo, or anything another app put in the
/// channel. Telegram takes a document's preview only with the document, so
/// each is fetched, a preview made from it here, and its bytes sent again
/// into the same message with the preview. The previews are made on the
/// phone, so only Android makes them.
class PreviewMaker {
  PreviewMaker(this._ref);

  final Ref _ref;

  /// Left free on the phone on top of the two copies of the file in hand.
  static const int _keepFree = 200 << 20;

  /// Files this run couldn't make a preview of, by id, so making previews
  /// again doesn't fetch them for nothing.
  final Set<String> _noPicture = {};

  /// Files Telegram didn't hand over this run, by id: tried again after the
  /// app starts again rather than waited on every time.
  final Set<String> _notFetched = {};

  /// How long fetching a file of [bytes] may take before it is given up
  /// on: a minute, and a second more for every 50 KB, so a file Telegram
  /// sends nothing of doesn't hold up the rest.
  @visibleForTesting
  static Duration fetchWithin(int bytes) => Duration(seconds: 60 + bytes ~/ 50000);

  /// Whether this phone can make previews at all.
  static bool get canMake => !kIsWeb && Platform.isAndroid;

  /// Of [rows], the ones worth a try: those not already found to make no
  /// picture, nor that Telegram didn't hand over this run.
  List<FileRow> worthTrying(List<FileRow> rows) => [
    for (final row in rows)
      if (!_noPicture.contains(row.id) && !_notFetched.contains(row.id)) row,
  ];

  /// Makes previews for [rows], smallest first, as a bulk change the screen
  /// follows. On Wi-Fi unless [onMobileData] says the person agreed to
  /// mobile data, since each costs its size twice. A file Telegram doesn't
  /// hand over within [fetchWithin] is passed over and the rest carry on.
  /// Stops when the phone runs short of room or goes offline. Answers how
  /// it went, with how many files made no picture and how many couldn't
  /// be fetched.
  Future<({BulkOutcome outcome, int noPicture, int notFetched})> make(
    List<FileRow> rows, {
    bool onMobileData = false,
  }) async {
    if (!onMobileData && _ref.read(networkStatusProvider).metered) {
      throw const DriveException('Connect to Wi-Fi first: each file is fetched and sent again.');
    }
    final files = worthTrying(rows)..sort((a, b) => a.size.compareTo(b.size));
    final queue = _ref.read(transferQueueProvider.notifier);
    final repository = _ref.read(driveRepositoryProvider);
    var noPicture = 0;
    var notFetched = 0;
    final cache = await getTemporaryDirectory();
    final outcome = await _ref.read(bulkEditsProvider.notifier).run<FileRow>(
      label: 'Making previews for ${Formatters.count(files.length, 'file')}',
      icon: Icons.image_outlined,
      items: files,
      apply: (row) async {
        if (await Room.shortfall(_ref.read(deviceStorageProvider), row.size * 2 + _keepFree) != null) {
          throw const DriveException('This phone needs more room to make the rest.');
        }
        if (!_ref.read(networkStatusProvider).online) {
          throw const DriveException('This phone went offline. Make the rest once it is back.');
        }
        final file = DriveFile.fromRow(row);
        // A copy already on the phone, kept offline say, is the person's and
        // stays; one fetched for this goes once it has served.
        final kept = await queue.localPathIfAvailable(file);
        final local = kept ?? await _fetch(queue, file);
        if (local == null) {
          _notFetched.add(row.id);
          notFetched++;
          return;
        }
        final dir = Directory(p.join(cache.path, 'previews', '${DateTime.now().microsecondsSinceEpoch}'));
        try {
          await dir.create(recursive: true);
          // A copy of its own, so Telegram takes it as a file to send rather
          // than the one it already holds.
          final copy = await File(local).copy(p.join(dir.path, DeviceStorage.safeName(row.name)));
          final thumbnail = await MediaProbe.thumbnail(
            copy.path,
            video: row.kind == FileKind.video,
            out: p.join(dir.path, 'preview.jpg'),
          );
          if (thumbnail == null) {
            _noPicture.add(row.id);
            noPicture++;
            return;
          }
          await repository.addPreview(row.id, path: copy.path, thumbnailPath: thumbnail);
        } finally {
          await _deleteQuietly(dir);
          if (kept == null) await _deleteQuietly(File(local));
        }
      },
    );
    return (outcome: outcome, noPicture: noPicture, notFetched: notFetched);
  }

  /// [file] fetched onto the phone, or null when Telegram didn't hand it
  /// over: the download failed, or sent nothing in time and was called off.
  Future<String?> _fetch(TransferQueue queue, DriveFile file) async {
    try {
      return await queue.download(file).timeout(fetchWithin(file.size));
    } on TimeoutException {
      debugPrint('[Previews] ${file.name} wasn\'t fetched in time');
      for (final item in _ref.read(transferQueueProvider).items) {
        if (item.row.kind == TransferKind.download &&
            item.row.fileId == file.id &&
            item.status.isPending) {
          await queue.cancel(item.id);
        }
      }
      return null;
    } on TelegramException catch (e) {
      debugPrint('[Previews] ${file.name}: $e');
      return null;
    } on DriveException catch (e) {
      debugPrint('[Previews] ${file.name}: ${e.message}');
      return null;
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('[Previews] $e');
    }
  }
}

final previewMakerProvider = Provider<PreviewMaker>(PreviewMaker.new);
