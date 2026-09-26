import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/files/file_kind.dart';

/// Icon and accent colour for a kind of file. One hue per family, so a
/// glance at a list says "three videos and a PDF" before any name is read.
@immutable
class FileStyle {
  const FileStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const FileStyle folder = FileStyle(Icons.folder_rounded, Color(0xFF4C7EF3));

  static FileStyle forKind(FileKind kind) => switch (kind) {
    FileKind.image => const FileStyle(Icons.image_rounded, Color(0xFF8B5CF6)),
    FileKind.video => const FileStyle(Icons.movie_rounded, Color(0xFFE5486A)),
    FileKind.audio => const FileStyle(Icons.graphic_eq_rounded, Color(0xFFF59E0B)),
    FileKind.document => const FileStyle(Icons.description_rounded, Color(0xFF2F80ED)),
    FileKind.archive => const FileStyle(Icons.folder_zip_rounded, Color(0xFFEA7A2C)),
    FileKind.app => const FileStyle(Icons.android_rounded, Color(0xFF1FA971)),
    FileKind.other => const FileStyle(Icons.insert_drive_file_rounded, Color(0xFF64748B)),
  };

  /// A few extensions deserve their own mark within their family.
  static FileStyle forFile(String name, FileKind kind) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.pdf' => const FileStyle(Icons.picture_as_pdf_rounded, Color(0xFFE5484D)),
      '.xls' || '.xlsx' || '.csv' || '.ods' || '.numbers' =>
        const FileStyle(Icons.table_chart_rounded, Color(0xFF1FA971)),
      '.ppt' || '.pptx' || '.key' || '.odp' =>
        const FileStyle(Icons.slideshow_rounded, Color(0xFFEA7A2C)),
      '.txt' || '.md' => const FileStyle(Icons.article_rounded, Color(0xFF64748B)),
      '.json' || '.xml' || '.yaml' || '.yml' || '.html' || '.js' || '.dart' || '.py' =>
        const FileStyle(Icons.code_rounded, Color(0xFF0EA5A4)),
      '.epub' => const FileStyle(Icons.menu_book_rounded, Color(0xFF7C3AED)),
      _ => forKind(kind),
    };
  }

  /// Soft tinted background for the icon tile, tuned for either theme.
  Color background(Brightness brightness) => color.withValues(
    alpha: brightness == Brightness.dark ? 0.18 : 0.12,
  );
}
