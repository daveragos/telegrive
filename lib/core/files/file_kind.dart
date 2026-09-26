import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// The broad family a file belongs to. Drives the icon, the colour, the home
/// screen categories and which viewer opens it.
enum FileKind {
  image('Images'),
  video('Videos'),
  audio('Audio'),
  document('Documents'),
  archive('Archives'),
  app('Apps'),
  other('Other');

  const FileKind(this.label);

  final String label;

  static FileKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => FileKind.other);

  /// Classifies by MIME type first and falls back to the extension, because
  /// Telegram reports `application/octet-stream` for anything it does not
  /// recognise.
  static FileKind detect({required String fileName, String? mimeType}) {
    final mime = (mimeType == null || mimeType == _octetStream)
        ? (lookupMimeType(fileName) ?? '')
        : mimeType;
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');

    if (mime.startsWith('image/')) return FileKind.image;
    if (mime.startsWith('video/')) return FileKind.video;
    if (mime.startsWith('audio/')) return FileKind.audio;
    if (_archiveExtensions.contains(ext) || _archiveMimes.contains(mime)) {
      return FileKind.archive;
    }
    if (ext == 'apk' || ext == 'aab' || ext == 'ipa' || ext == 'xapk') {
      return FileKind.app;
    }
    if (_documentExtensions.contains(ext) ||
        mime.startsWith('text/') ||
        mime == 'application/pdf' ||
        mime.contains('document') ||
        mime.contains('sheet') ||
        mime.contains('presentation')) {
      return FileKind.document;
    }
    return FileKind.other;
  }

  static const String _octetStream = 'application/octet-stream';

  static const Set<String> _archiveExtensions = {
    'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'zst', 'iso', 'dmg',
  };

  static const Set<String> _archiveMimes = {
    'application/zip',
    'application/x-7z-compressed',
    'application/x-rar-compressed',
    'application/vnd.rar',
    'application/gzip',
    'application/x-tar',
  };

  static const Set<String> _documentExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
    'txt', 'md', 'rtf', 'csv', 'json', 'xml', 'yaml', 'yml', 'epub', 'pages',
    'numbers', 'key', 'html', 'htm',
  };
}

/// Best-effort MIME type for a file about to be uploaded.
String mimeTypeFor(String fileName) =>
    lookupMimeType(fileName) ?? 'application/octet-stream';
