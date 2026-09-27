import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:handy_tdlib/api.dart' as td;

import '../../../core/files/file_kind.dart';
import '../../../infrastructure/database/app_database.dart';
import '../domain/manifest.dart';

/// What one channel message contributes to the index.
sealed class IndexEntry {
  const IndexEntry();
}

class FilePartEntry extends IndexEntry {
  const FilePartEntry(this.file, this.part, {this.albums = const []});

  final DriveFilesCompanion file;
  final FilePartsCompanion part;

  /// Albums the file is in, as its manifest says.
  final List<String> albums;
}

class FolderEntry extends IndexEntry {
  const FolderEntry(this.folder);

  final FoldersCompanion folder;
}

class AlbumEntry extends IndexEntry {
  const AlbumEntry(this.album);

  final AlbumsCompanion album;
}

/// The media carried by a message, whatever its Telegram type.
class _Media {
  const _Media({
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.caption,
    this.minithumbnail,
    this.thumbnailFileId,
  });

  final td.File file;
  final String fileName;
  final String mimeType;
  final String caption;
  final td.Minithumbnail? minithumbnail;
  final int? thumbnailFileId;
}

/// Turns channel messages into index rows.
///
/// Messages the app wrote carry a manifest and map exactly. Anything else
/// someone forwarded into the channel — a document, video, audio file or
/// photo — is adopted as a file at the root under a stable id derived from
/// its message, so forwarding from Telegram is a zero-upload way to add to
/// the drive. The first rename or move writes a proper manifest onto it.
abstract final class MessageIndexer {
  static IndexEntry? entryFor(td.Message message) {
    // Still sending: the permanent message will arrive separately.
    if (message.sendingState != null) return null;

    final content = message.content;
    if (content is td.MessageText) {
      final text = content.text.text;
      if (ManifestCodec.decodeAlbum(text) case final album?) {
        return AlbumEntry(
          AlbumsCompanion.insert(
            id: album.id,
            name: album.name,
            messageId: message.id,
            createdAt: album.createdAt,
            modifiedAt: album.modifiedAt,
          ),
        );
      }
      final folder = ManifestCodec.decodeFolder(text);
      if (folder == null) return null;
      return FolderEntry(
        FoldersCompanion.insert(
          id: folder.id,
          parentId: Value(folder.parentId),
          name: folder.name,
          messageId: message.id,
          createdAt: folder.createdAt,
          modifiedAt: folder.modifiedAt,
          trashedAt: Value(folder.trashedAt),
          manifestExtra: Value(ManifestCodec.encodeExtra(folder.extra)),
        ),
      );
    }

    final media = _mediaOf(message);
    if (media == null) return null;

    final manifest =
        ManifestCodec.decodeFile(media.caption) ?? _adoptedManifest(message, media);
    final kind = FileKind.detect(
      fileName: manifest.name,
      mimeType: manifest.mimeType,
    );
    final isFirstPart = manifest.partIndex == 0;

    return FilePartEntry(
      DriveFilesCompanion.insert(
        id: manifest.id,
        folderId: Value(manifest.folderId),
        name: manifest.name,
        mimeType: manifest.mimeType,
        kind: kind,
        size: manifest.size,
        createdAt: manifest.createdAt,
        modifiedAt: manifest.modifiedAt,
        partCount: Value(manifest.partCount),
        starred: Value(manifest.starred),
        takenAt: Value(manifest.takenAt),
        trashedAt: Value(manifest.trashedAt),
        manifestExtra: Value(ManifestCodec.encodeExtra(manifest.extra)),
        // Previews come from the first part only; later parts of a split
        // video have nothing meaningful to show.
        minithumbnail: isFirstPart
            ? Value(media.minithumbnail?.data)
            : const Value.absent(),
        thumbnailFileId: isFirstPart
            ? Value(media.thumbnailFileId)
            : const Value.absent(),
      ),
      FilePartsCompanion.insert(
        fileId: manifest.id,
        partIndex: manifest.partIndex,
        messageId: message.id,
        tdFileId: media.file.id,
        size: media.file.size != 0 ? media.file.size : media.file.expectedSize,
      ),
      albums: manifest.albums,
    );
  }

  /// A manifest for a message the app did not write.
  static FileManifest _adoptedManifest(td.Message message, _Media media) {
    final date = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
    final edited = message.editDate > 0
        ? DateTime.fromMillisecondsSinceEpoch(message.editDate * 1000)
        : date;
    return FileManifest(
      id: adoptedId(message.id),
      name: media.fileName,
      folderId: null,
      mimeType: media.mimeType.isEmpty
          ? mimeTypeFor(media.fileName)
          : media.mimeType,
      size: media.file.size != 0 ? media.file.size : media.file.expectedSize,
      createdAt: date,
      modifiedAt: edited,
    );
  }

  static String adoptedId(int messageId) => 'tg$messageId';

  /// The downloadable file inside [message], whatever kind of media it is.
  static td.File? mediaFile(td.Message message) => _mediaOf(message)?.file;

  static _Media? _mediaOf(td.Message message) {
    switch (message.content) {
      case td.MessageDocument(:final document, :final caption):
        return _Media(
          file: document.document,
          fileName: _nameOr(document.fileName, message, 'file'),
          mimeType: document.mimeType,
          caption: caption.text,
          minithumbnail: document.minithumbnail,
          thumbnailFileId: document.thumbnail?.file.id,
        );
      case td.MessageVideo(:final video, :final caption):
        return _Media(
          file: video.video,
          fileName: _nameOr(video.fileName, message, 'video', 'mp4'),
          mimeType: video.mimeType,
          caption: caption.text,
          minithumbnail: video.minithumbnail,
          thumbnailFileId: video.thumbnail?.file.id,
        );
      case td.MessageAudio(:final audio, :final caption):
        return _Media(
          file: audio.audio,
          fileName: _nameOr(audio.fileName, message, 'audio', 'mp3'),
          mimeType: audio.mimeType,
          caption: caption.text,
          minithumbnail: audio.albumCoverMinithumbnail,
          thumbnailFileId: audio.albumCoverThumbnail?.file.id,
        );
      case td.MessageAnimation(:final animation, :final caption):
        return _Media(
          file: animation.animation,
          fileName: _nameOr(animation.fileName, message, 'animation', 'mp4'),
          mimeType: animation.mimeType,
          caption: caption.text,
          minithumbnail: animation.minithumbnail,
          thumbnailFileId: animation.thumbnail?.file.id,
        );
      case td.MessagePhoto(:final photo, :final caption):
        if (photo.sizes.isEmpty) return null;
        final largest = photo.sizes.reduce(
          (a, b) => a.width * a.height >= b.width * b.height ? a : b,
        );
        // The preview: the smallest size that still fills a grid tile on a
        // dense screen (~480 px), not the 90 px one.
        final bySize = [...photo.sizes]
          ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
        final preview = bySize.firstWhere(
          (s) => math.max(s.width, s.height) >= 480,
          orElse: () => bySize.last,
        );
        return _Media(
          file: largest.photo,
          fileName: _nameOr('', message, 'photo', 'jpg'),
          mimeType: 'image/jpeg',
          caption: caption.text,
          minithumbnail: photo.minithumbnail,
          thumbnailFileId: preview.photo.id,
        );
      default:
        return null;
    }
  }

  static String _nameOr(
    String name,
    td.Message message,
    String fallback, [
    String? extension,
  ]) {
    if (name.trim().isNotEmpty) return name.trim();
    final suffix = extension == null ? '' : '.$extension';
    return '${fallback}_${message.id >> 20}$suffix';
  }
}
