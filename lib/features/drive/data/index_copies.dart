import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/network/network_status.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../domain/manifest.dart';
import 'channel_messenger.dart';

/// The rows a copy of the index holds, ready to go into the database.
typedef IndexContents = ({
  List<FoldersCompanion> folders,
  List<AlbumsCompanion> albums,
  List<DriveFilesCompanion> files,
  List<FilePartsCompanion> parts,
  List<AlbumFilesCompanion> albumFiles,
});

/// A copy of the drive's index kept in its channel, so a new phone, or a
/// reinstall, opens a big drive at once instead of after reading every
/// message.
///
/// The copy is one document, `telegrive-index.json.gz`, captioned with an
/// [IndexRecord], and the pinned drive message points to it. Each new copy
/// replaces the document in the same message. It is only a head start:
/// the captions stay what the drive is, so a phone that opens from a copy
/// still reads the channel in full behind Home, and settles whatever
/// changed since the copy was written.
///
/// A copy is written after a full read of the channel, at most every
/// [interval], over a connection that isn't metered, and only when the
/// index has changed since the last one.
class IndexCopies {
  IndexCopies(this._ref);

  final Ref _ref;

  /// Bump when what a copy holds changes in a way an older version can't
  /// read; a copy of another format is passed over.
  static const int format = 1;

  static const Duration interval = Duration(days: 3);
  static const String fileName = 'telegrive-index.json.gz';

  AppDatabase get _db => _ref.read(appDatabaseProvider);
  Preferences get _prefs => _ref.read(preferencesProvider);
  TelegramClient get _client => _ref.read(telegramClientProvider);
  ChannelMessenger get _messenger => _ref.read(channelMessengerProvider);

  /// Writes a copy of the index into [chatId] if one is due. True when it
  /// did. It never throws: the copy only saves time.
  Future<bool> writeIfDue(int chatId) async {
    File? file;
    try {
      final cardId = _prefs.driveCardId(chatId);
      if (cardId == null) return false;
      final network = _ref.read(networkStatusProvider);
      if (!network.online || network.metered) return false;
      final now = DateTime.now();
      final last = _prefs.indexCopyAt(chatId);
      if (last != null && now.difference(last) < interval) return false;

      final json = await snapshot(_db);
      final body = utf8.encode(jsonEncode(json));
      final print = fingerprint(body);
      if (last != null && print == _prefs.indexCopyPrint(chatId)) return false;
      final card = await _driveManifest(chatId, cardId);
      if (card == null) return false;

      file = File('${(await getTemporaryDirectory()).path}/$fileName');
      await file.writeAsBytes(gzip.encode(body), flush: true);
      final caption = ManifestCodec.encodeIndex(
        IndexRecord(
          driveId: card.id,
          throughMessageId: _prefs.lastSyncedMessageId(chatId),
          files: (json['files']! as List).length,
          createdAt: now,
        ),
      );
      final existing = card.indexMessageId;
      if (existing != null && await _indexCopyAt(chatId, existing) != null) {
        await _messenger.replaceDocument(chatId, existing, path: file.path, caption: caption);
      } else {
        final sent = await _messenger.sendDocument(chatId, path: file.path, caption: caption);
        await _messenger.editText(
          chatId,
          cardId,
          ManifestCodec.encodeDrive(card.copyWith(indexMessageId: sent.id)),
        );
      }
      await _prefs.setIndexCopy(chatId, now, print);
      return true;
    } catch (e) {
      debugPrint('[IndexCopies] Could not write the copy: $e');
      return false;
    } finally {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Fills the index from the copy the drive message in [chatId] points to.
  /// True when it did; false leaves the index as it was, for a full read.
  Future<bool> restore(int chatId) async {
    try {
      final cardId = _prefs.driveCardId(chatId);
      if (cardId == null) return false;
      final card = await _driveManifest(chatId, cardId);
      final indexId = card?.indexMessageId;
      if (card == null || indexId == null) return false;
      final copy = await _indexCopyAt(chatId, indexId);
      if (copy == null || copy.record.driveId != card.id) return false;

      final file = await _client.send<td.File>(
        td.DownloadFile(fileId: copy.fileId, priority: 32, offset: 0, limit: 0, synchronous: true),
        timeout: const Duration(minutes: 5),
      );
      final path = file.local.path;
      if (!file.local.isDownloadingCompleted || path.isEmpty) return false;
      final contents = read(await File(path).readAsBytes());
      if (contents == null) return false;
      await _db.replaceIndex(
        folderRows: contents.folders,
        albumRows: contents.albums,
        fileRows: contents.files,
        partRows: contents.parts,
        albumFileRows: contents.albumFiles,
      );
      return true;
    } catch (e) {
      debugPrint('[IndexCopies] Could not open the drive from its copy: $e');
      return false;
    }
  }

  /// The drive message [cardId] of [chatId], read afresh.
  Future<DriveManifest?> _driveManifest(int chatId, int cardId) async {
    final message = await _client.send<td.Message>(
      td.GetMessage(chatId: chatId, messageId: cardId),
    );
    return switch (message.content) {
      td.MessageText(:final text) => ManifestCodec.decodeDrive(text.text),
      _ => null,
    };
  }

  /// Message [messageId] of [chatId] if it still holds a copy of the index:
  /// its record and TDLib's id for the document in this run. Null when it
  /// is gone or something else.
  Future<({IndexRecord record, int fileId})?> _indexCopyAt(int chatId, int messageId) async {
    try {
      final message = await _client.send<td.Message>(
        td.GetMessage(chatId: chatId, messageId: messageId),
      );
      if (message.content case td.MessageDocument(:final document, :final caption)) {
        if (ManifestCodec.decodeIndex(caption.text) case final record?) {
          return (record: record, fileId: document.document.id);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The index as a copy holds it. Nothing about this phone goes in: no
  /// TDLib file ids, which last one run, and no previews, which the full
  /// read after a restore brings back from the messages.
  static Future<Map<String, Object?>> snapshot(AppDatabase db) async {
    final parts = <String, List<PartRow>>{};
    for (final part in await db.select(db.fileParts).get()) {
      (parts[part.fileId] ??= []).add(part);
    }
    final albumsOf = <String, List<String>>{};
    for (final row in await db.select(db.albumFiles).get()) {
      (albumsOf[row.fileId] ??= []).add(row.albumId);
    }
    int? ms(DateTime? time) => time?.millisecondsSinceEpoch;
    return {
      'format': format,
      'folders': [
        for (final f in await db.select(db.folders).get())
          {
            'id': f.id,
            'p': f.parentId,
            'n': f.name,
            'msg': f.messageId,
            'ct': ms(f.createdAt),
            'mt': ms(f.modifiedAt),
            'tr': ms(f.trashedAt),
            'st': f.starred,
            'x': f.manifestExtra,
            'ly': f.captionLayout,
          },
      ],
      'albums': [
        for (final a in await db.select(db.albums).get())
          {
            'id': a.id,
            'n': a.name,
            'msg': a.messageId,
            'ct': ms(a.createdAt),
            'mt': ms(a.modifiedAt),
            'ly': a.captionLayout,
          },
      ],
      'files': [
        for (final f in await db.select(db.driveFiles).get())
          {
            'id': f.id,
            'f': f.folderId,
            'n': f.name,
            'm': f.mimeType,
            's': f.size,
            'ct': ms(f.createdAt),
            'mt': ms(f.modifiedAt),
            'pc': f.partCount,
            'st': f.starred,
            'tk': ms(f.takenAt),
            'tr': ms(f.trashedAt),
            'x': f.manifestExtra,
            'du': f.durationSeconds,
            'rb': f.replacedBy,
            'ad': f.adopted,
            'lt': f.originalSize,
            'al': [...?albumsOf[f.id]]..sort(),
            'parts': [
              for (final p in [...?parts[f.id]]..sort((a, b) => a.partIndex - b.partIndex))
                {'i': p.partIndex, 'msg': p.messageId, 's': p.size, 'ly': p.captionLayout},
            ],
          },
      ],
    };
  }

  /// The rows a copy holds, or null when it can't be read: another format,
  /// or not a copy at all.
  static IndexContents? read(List<int> gzipped) {
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(gzipped)));
      if (json is! Map<String, dynamic> || json['format'] != format) return null;
      DateTime time(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms! as int);
      DateTime? maybe(Object? ms) => ms == null ? null : time(ms);
      final files = <DriveFilesCompanion>[];
      final parts = <FilePartsCompanion>[];
      final albumFiles = <AlbumFilesCompanion>[];
      for (final f in (json['files'] as List).cast<Map<String, dynamic>>()) {
        final id = f['id'] as String;
        final name = f['n'] as String;
        final mimeType = f['m'] as String;
        final fileParts = (f['parts'] as List).cast<Map<String, dynamic>>();
        files.add(
          DriveFilesCompanion.insert(
            id: id,
            folderId: Value(f['f'] as String?),
            name: name,
            mimeType: mimeType,
            kind: FileKind.detect(fileName: name, mimeType: mimeType),
            size: f['s'] as int,
            createdAt: time(f['ct']),
            modifiedAt: time(f['mt']),
            partCount: Value(f['pc'] as int),
            partsPresent: Value(fileParts.length),
            starred: Value(f['st'] as bool),
            takenAt: Value(maybe(f['tk'])),
            trashedAt: Value(maybe(f['tr'])),
            manifestExtra: Value(f['x'] as String?),
            durationSeconds: Value(f['du'] as int?),
            replacedBy: Value(f['rb'] as String?),
            adopted: Value(f['ad'] as bool),
            originalSize: Value(f['lt'] as int?),
          ),
        );
        for (final p in fileParts) {
          parts.add(
            FilePartsCompanion.insert(
              fileId: id,
              partIndex: p['i'] as int,
              messageId: p['msg'] as int,
              tdFileId: 0,
              size: p['s'] as int,
              captionLayout: Value(p['ly'] as int?),
            ),
          );
        }
        for (final albumId in (f['al'] as List).cast<String>()) {
          albumFiles.add(AlbumFilesCompanion.insert(albumId: albumId, fileId: id));
        }
      }
      return (
        folders: [
          for (final f in (json['folders'] as List).cast<Map<String, dynamic>>())
            FoldersCompanion.insert(
              id: f['id'] as String,
              parentId: Value(f['p'] as String?),
              name: f['n'] as String,
              messageId: f['msg'] as int,
              createdAt: time(f['ct']),
              modifiedAt: time(f['mt']),
              trashedAt: Value(maybe(f['tr'])),
              starred: Value(f['st'] as bool),
              manifestExtra: Value(f['x'] as String?),
              captionLayout: Value(f['ly'] as int?),
            ),
        ],
        albums: [
          for (final a in (json['albums'] as List).cast<Map<String, dynamic>>())
            AlbumsCompanion.insert(
              id: a['id'] as String,
              name: a['n'] as String,
              messageId: a['msg'] as int,
              createdAt: time(a['ct']),
              modifiedAt: time(a['mt']),
              captionLayout: Value(a['ly'] as int?),
            ),
        ],
        files: files,
        parts: parts,
        albumFiles: albumFiles,
      );
    } catch (e) {
      debugPrint('[IndexCopies] Unreadable copy: $e');
      return null;
    }
  }

  /// A 32-bit FNV-1a hash of [bytes], the same in every run, to tell
  /// whether the index changed since the last copy.
  static int fingerprint(List<int> bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

final indexCopiesProvider = Provider<IndexCopies>(IndexCopies.new);
