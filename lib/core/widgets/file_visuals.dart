import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/file_style.dart';
import '../../app/theme/tokens.dart';
import '../../features/backup/data/local_media.dart';
import '../../features/drive/data/previews.dart';
import '../../features/drive/domain/drive_models.dart';
import '../files/file_kind.dart';

/// A neutral slot with the kind glyph in it — the stand-in for a file that
/// has no picture of its own. Every row has one, so names line up.
class FileIconTile extends StatelessWidget {
  const FileIconTile({super.key, required this.style, this.size = 44, this.radius});

  final FileStyle style;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(radius ?? Radii.thumb),
      ),
      child: Icon(
        style.icon,
        color: style.resolve(context, colors.text2),
        size: size * 0.5,
      ),
    );
  }
}

class FolderIconTile extends StatelessWidget {
  const FolderIconTile({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) =>
      FileIconTile(style: FileStyle.folder, size: size);
}

/// The best picture available for [file]: the phone's own copy when the
/// file was backed up from here, otherwise Telegram's thumbnail once fetched,
/// with Telegram's tiny inline preview softly blurred underneath until then,
/// and the kind glyph for files with no picture at all.
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

  /// Fill the parent instead of a fixed square (grids).
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final style = FileStyle.forFile(file.name, file.kind);
    final corner = BorderRadius.circular(radius ?? Radii.thumb);
    final isMedia = file.kind == FileKind.image || file.kind == FileKind.video;

    Widget framed(Widget child) =>
        expand ? child : SizedBox.square(dimension: size, child: child);

    final local = isMedia ? ref.watch(localThumbnailProvider(file.id)).value : null;

    if (!file.hasPreview && local == null) {
      return framed(
        DecoratedBox(
          decoration: BoxDecoration(color: colors.surface2, borderRadius: corner),
          child: Center(
            child: Icon(
              style.icon,
              color: style.resolve(context, colors.text2),
              size: expand ? 32 : size * 0.5,
            ),
          ),
        ),
      );
    }

    // No need to fetch Telegram's copy when the phone has a better one.
    final thumbPath = local != null || file.thumbnailFileId == null
        ? null
        : ref.watch(thumbnailPathProvider(file.thumbnailFileId!)).value;

    return framed(
      ClipRRect(
        borderRadius: corner,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The slot colour first, so nothing flashes blank while decoding.
            ColoredBox(color: colors.surface2),
            if (file.minithumbnail != null && local == null)
              _Blurred(bytes: file.minithumbnail!, sigma: expand ? 10 : 3),
            if (local != null)
              _Fading(
                Image.memory(
                  local,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              )
            else if (thumbPath != null)
              _Fading(
                Image.file(
                  File(thumbPath),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Decoded at its own size (Telegram's are 320 px at most):
                  // shrinking a cache width below that is fine, forcing it
                  // above only blurs.
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (file.kind == FileKind.video)
              Positioned(
                right: expand ? 6 : 3,
                bottom: expand ? 6 : 3,
                child: Icon(
                  Icons.play_circle_filled_rounded,
                  color: Colors.white,
                  size: expand ? 22 : 16,
                  shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Telegram's inline preview is ~40 px; drawn sharp it is a mosaic. Blurred,
/// it reads as "the photo, loading", which is what it is.
class _Blurred extends StatelessWidget {
  const _Blurred({required this.bytes, required this.sigma});

  final Uint8List bytes;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    // Scaled a little past the clip so the blur's soft edges fall outside
    // the tile instead of fading into the gutter.
    return Transform.scale(
      scale: 1.2,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// Fades an image in once its first frame is ready.
class _Fading extends StatelessWidget {
  const _Fading(this.image);

  final Image image;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: image.image,
      fit: image.fit,
      gaplessPlayback: true,
      filterQuality: image.filterQuality,
      errorBuilder: image.errorBuilder,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null && !sync ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    );
  }
}
