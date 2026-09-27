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
        ? (lookupMime(fileName) ?? '')
        : mimeType;
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');

    if (mime.startsWith('image/')) return FileKind.image;
    if (mime.startsWith('video/')) return FileKind.video;
    if (mime.startsWith('audio/') || mime == 'application/ogg') {
      return FileKind.audio;
    }
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

/// Audio formats phones record or sell that the mime package doesn't
/// know: call recordings (.amr, .awb, .3ga), audiobooks (.m4b) and
/// ringtones (.m4r). Without them these files would count as Other and
/// open in no app.
const Map<String, String> _appMimeTypes = {
  'amr': 'audio/amr',
  'awb': 'audio/amr-wb',
  '3ga': 'audio/3gpp',
  'm4b': 'audio/mp4',
  'm4r': 'audio/mp4',
};

/// The MIME type [fileName]'s extension stands for, or null when it is
/// unknown.
String? lookupMime(String fileName) {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  return _appMimeTypes[ext] ?? lookupMimeType(fileName);
}

/// Best-effort MIME type for a file about to be uploaded.
String mimeTypeFor(String fileName) =>
    lookupMime(fileName) ?? 'application/octet-stream';

/// How the app shows a file itself, without handing it to another app.
enum Preview {
  /// The photo viewer.
  image,

  /// The player, streaming.
  media,
  pdf,
  text,

  /// Only another app can open it.
  none;

  /// Text files larger than this are opened elsewhere.
  static const int textLimit = 5 * 1024 * 1024;

  static Preview of({
    required String name,
    required String mimeType,
    required FileKind kind,
    required int size,
    bool isSplit = false,
  }) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (kind == FileKind.image && !isSplit) return Preview.image;
    if (kind == FileKind.video || kind == FileKind.audio) return Preview.media;
    if (isSplit) return Preview.none;
    if (ext == 'pdf' || mimeType == 'application/pdf') return Preview.pdf;
    final texty =
        _textExtensions.contains(ext) ||
        mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml';
    if (texty && size <= textLimit) return Preview.text;
    return Preview.none;
  }

  static const Set<String> _textExtensions = {
    'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml', 'log',
    'ini', 'conf', 'cfg', 'toml', 'env', 'properties', 'html', 'htm', 'css',
    'js', 'ts', 'jsx', 'tsx', 'dart', 'py', 'java', 'kt', 'kts', 'swift', 'c',
    'h', 'cpp', 'hpp', 'cc', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'bash',
    'zsh', 'bat', 'ps1', 'sql', 'srt', 'vtt', 'gradle', 'lua', 'r', 'tex',
  };
}

