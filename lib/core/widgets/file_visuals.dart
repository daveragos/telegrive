import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/file_style.dart';
import '../files/file_kind.dart';
import '../../features/drive/data/previews.dart';
import '../../features/drive/domain/drive_models.dart';

/// Rounded tile with a tinted icon — the fallback look for any file.
class FileIconTile extends StatelessWidget {
  const FileIconTile({
    super.key,
    required this.style,
    this.size = 44,
    this.radius,
  });

  final FileStyle style;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.background(brightness),
        borderRadius: BorderRadius.circular(radius ?? size * 0.3),
      ),
      child: Icon(style.icon, color: style.color, size: size * 0.52),
    );
  }
}

/// The best preview available for [file]: the real thumbnail once fetched,
/// Telegram's blurred inline one until then, and the type icon otherwise.
class FileThumbnail extends ConsumerWidget {
  const FileThumbnail({
    super.key,
    required this.file,
    this.size = 44,
    this.radius,
    this.expand = false,
  });

  final DriveFile file;
  final double size;
  final double? radius;

  /// Fill the parent instead of a fixed square (grid cards).
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = FileStyle.forFile(file.name, file.kind);
    final corner = BorderRadius.circular(radius ?? size * 0.3);

    if (!file.hasPreview) {
      final tile = FileIconTile(style: style, size: size, radius: radius);
      return expand
          ? Container(
              decoration: BoxDecoration(
                color: style.background(Theme.of(context).brightness),
                borderRadius: corner,
              ),
              alignment: Alignment.center,
              child: Icon(style.icon, color: style.color, size: size * 0.6),
            )
          : tile;
    }

    final thumbPath = file.thumbnailFileId == null
        ? null
        : ref.watch(thumbnailPathProvider(file.thumbnailFileId!)).value;

    final layers = <Widget>[
      // Tinted ground first, so there is never a blank square while an
      // image decodes.
      ColoredBox(color: style.background(Theme.of(context).brightness)),
      if (file.minithumbnail != null)
        Image.memory(
          file.minithumbnail!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      if (thumbPath != null)
        Image.file(
          File(thumbPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: expand ? 480 : (size * 3).round(),
          frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            child: child,
          ),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
    ];

    final content = ClipRRect(
      borderRadius: corner,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ...layers,
          if (file.kind == FileKind.video)
            Center(
              child: Container(
                padding: EdgeInsets.all(expand ? 8 : 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: expand ? 26 : size * 0.36,
                ),
              ),
            ),
        ],
      ),
    );

    return expand ? content : SizedBox.square(dimension: size, child: content);
  }
}

class FolderIconTile extends StatelessWidget {
  const FolderIconTile({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) =>
      FileIconTile(style: FileStyle.folder, size: size);
}
