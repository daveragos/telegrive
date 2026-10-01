import 'package:intl/intl.dart';
import 'package:mime/mime.dart' show extensionFromMime;
import 'package:path/path.dart' as p;

import '../../../core/files/file_kind.dart';

/// What a file copied from a chat is called in the drive.
///
/// The same name is what the import list compares with the drive, as
/// `name|size`, to leave out what was saved before, so a message must give
/// the same name every time.
abstract final class ImportNaming {
  /// In one fixed locale, so the phone's language never changes a name.
  static final DateFormat _stamp = DateFormat('yyyy-MM-dd HH.mm.ss', 'en_US');

  /// What Telegram reports for a type it doesn't recognise, which says
  /// nothing about the file.
  static const String _unknownType = 'application/octet-stream';

  /// [fileName] when the message has a name of its own. A photo sent as a
  /// photo, and other media sent without a name, is named after its kind
  /// and the message's [date], as in 'Photo 2023-03-03 18.04.12.jpg'. Any
  /// other file keeps the extension it came with, or else takes the one its
  /// [mimeType] stands for.
  ///
  /// The stamp is [date] as given, which the import list passes in the
  /// phone's local time, the way the person reads it. The `name|size` check
  /// depends on it: once the phone is in another time zone, files saved
  /// without a name of their own get a different stamp and are offered
  /// again.
  static String nameFor({
    required String fileName,
    required bool hasOwnName,
    required FileKind kind,
    required String mimeType,
    required DateTime date,
  }) {
    if (hasOwnName) return fileName;
    final stamp = _stamp.format(date);
    return switch (kind) {
      FileKind.image => 'Photo $stamp.jpg',
      FileKind.video => 'Video $stamp.mp4',
      FileKind.audio => 'Audio $stamp.mp3',
      _ => 'File $stamp${_extension(fileName, mimeType)}',
    };
  }

  /// [fileName]'s extension, or else the one [mimeType] stands for, or
  /// none when neither says.
  static String _extension(String fileName, String mimeType) {
    final own = p.extension(fileName);
    if (own.isNotEmpty || mimeType.isEmpty || mimeType == _unknownType) return own;
    final fromType = extensionFromMime(mimeType);
    return fromType == null ? '' : '.$fromType';
  }
}
