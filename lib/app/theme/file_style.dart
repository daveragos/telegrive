import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/files/file_kind.dart';

/// The glyph for a kind of file and the hue it is drawn in. The hue only
/// ever colours the glyph itself (DESIGN.md: kind hues never fill a surface),
/// so a list reads as "three videos and a PDF" without turning into confetti.
@immutable
class FileStyle {
  const FileStyle(this.icon, [this.color]);

  final IconData icon;

  /// Null means neutral: drawn in `text-2`, like folders.
  final Color? color;

  static const FileStyle folder = FileStyle(Icons.folder_outlined);

  static FileStyle forKind(FileKind kind) => switch (kind) {
    FileKind.image => const FileStyle(Icons.image_outlined, Color(0xFF7353C9)),
    FileKind.video => const FileStyle(Icons.movie_outlined, Color(0xFFC4435F)),
    FileKind.audio => const FileStyle(Icons.music_note_outlined, Color(0xFFB86E0E)),
    FileKind.document => const FileStyle(Icons.description_outlined, Color(0xFF2A63CF)),
    FileKind.archive => const FileStyle(Icons.folder_zip_outlined, Color(0xFFA95A25)),
    FileKind.app => const FileStyle(Icons.android_outlined, Color(0xFF2B8657)),
    FileKind.other => const FileStyle(Icons.insert_drive_file_outlined),
  };

  /// A few extensions deserve their own mark within their family.
  static FileStyle forFile(String name, FileKind kind) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.pdf' => const FileStyle(Icons.picture_as_pdf_outlined, Color(0xFFC23636)),
      '.xls' || '.xlsx' || '.csv' || '.ods' || '.numbers' =>
        const FileStyle(Icons.table_chart_outlined, Color(0xFF2B8657)),
      '.ppt' || '.pptx' || '.key' || '.odp' =>
        const FileStyle(Icons.slideshow_outlined, Color(0xFFA95A25)),
      '.txt' || '.md' => const FileStyle(Icons.article_outlined),
      '.json' || '.xml' || '.yaml' || '.yml' || '.html' || '.js' || '.dart' || '.py' =>
        const FileStyle(Icons.code_rounded, Color(0xFF1F7F86)),
      '.epub' => const FileStyle(Icons.menu_book_outlined, Color(0xFF7353C9)),
      _ => forKind(kind),
    };
  }

  /// In dark mode the hues are lifted so they keep their contrast.
  Color resolve(BuildContext context, Color neutral) {
    final hue = color;
    if (hue == null) return neutral;
    if (Theme.of(context).brightness == Brightness.light) return hue;
    return Color.lerp(hue, Colors.white, 0.35)!;
  }
}
