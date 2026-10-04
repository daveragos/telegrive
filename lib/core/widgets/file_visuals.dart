import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/file_style.dart';
import '../../app/theme/tokens.dart';
import '../../features/backup/data/local_media.dart';
import '../../features/drive/data/previews.dart';
import '../../features/drive/domain/drive_models.dart';
import '../../infrastructure/storage/device_profile.dart';
import '../files/file_kind.dart';
import '../format/formatters.dart';

/// A neutral slot with the kind glyph in it — the stand-in for a file that
/// has no picture of its own. Every row has one, so names line up.
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
/// with Telegram's tiny inline preview softly blurred in its place until
/// then, and the kind glyph for files with no picture at all. Pictures are
/// decoded at about the size they are drawn at, not at the size they come.
class FileThumbnail extends StatelessWidget {
  const FileThumbnail({
    super.key,
    required this.file,
    this.size = 44,
    this.radius,
    this.expand = false,
  });

  final DriveFile file;

  /// The square's side. With [expand], the least side the picture is
  /// decoded for: a grid tile drawn smaller for a moment, as a selected one
  /// is, passes its whole side and keeps the picture it has.
  final double size;
  final double? radius;

  /// Fill the parent instead of a fixed square (grids).
  final bool expand;

  /// Telegram's thumbnail at [path] for a slot [px] physical pixels across.
  /// A slot under 160 px decodes it into a box twice its side, which keeps
  /// the short side sharp for pictures up to twice as wide as they are tall
  /// and never enlarges it; a bigger one takes it at its own size, which is
  /// 320 px at most.
  static ImageProvider telegramImage(String path, int px) {
    final image = FileImage(File(path));
    return px < 160
        ? ResizeImage(
            image,
            width: 2 * px,
            height: 2 * px,
            policy: ResizeImagePolicy.fit,
          )
        : image;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    _ThumbnailBody body(double side) => _ThumbnailBody(
      file: file,
      size: size,
      radius: radius,
      expand: expand,
      px: (side * ratio).ceil(),
    );
    if (!expand) return body(size);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fills = constraints.biggest.shortestSide;
        return body(fills.isFinite ? math.max(fills, size) : size);
      },
    );
  }
}

class _ThumbnailBody extends ConsumerWidget {
  const _ThumbnailBody({
    required this.file,
    required this.size,
    required this.radius,
    required this.expand,
    required this.px,
  });

  final DriveFile file;
  final double size;
  final double? radius;
  final bool expand;

  /// The side the picture is drawn at, in physical pixels.
  final int px;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final style = FileStyle.forFile(file.name, file.kind);
    final corner = BorderRadius.circular(radius ?? Radii.thumb);
    final isMedia = file.kind == FileKind.image || file.kind == FileKind.video;

    Widget framed(Widget child) =>
        expand ? child : SizedBox.square(dimension: size, child: child);

    final local = isMedia
        ? ref
              .watch(
                localThumbnailProvider((fileId: file.id, px: thumbBucket(px))),
              )
              .value
        : null;

    if (!file.hasPreview && local == null) {
      return framed(
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: corner,
          ),
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
        : _thumbPath(context, ref, file.thumbnailFileId!);
    final ImageProvider? sharp = local != null
        ? MemoryImage(local)
        : thumbPath != null
        ? FileThumbnail.telegramImage(thumbPath, px)
        : null;

    // A row read without its inline preview reads it on its own, unless the
    // phone's copy is already here.
    final mini =
        file.minithumbnail ??
        (file.hasMinithumbnail && local == null
            ? ref.watch(minithumbnailProvider(file.id)).value
            : null);
    // Drawn plain while saving memory, since a blur is one more layer to
    // paint and keep.
    final Widget? placeholder = mini == null
        ? null
        : ref.watch(saveMemoryProvider)
        ? Image.memory(
            mini,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          )
        : _Blurred(bytes: mini, sigma: expand ? 10 : 3);

    return framed(
      ClipRRect(
        borderRadius: corner,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The slot colour first, so nothing flashes blank while decoding.
            ColoredBox(color: colors.surface2),
            if (sharp != null)
              _Fading(image: sharp, placeholder: placeholder)
            else
              ?placeholder,
            if (file.kind == FileKind.video)
              if (expand)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _VideoBand(duration: file.duration),
                )
              else
                const Positioned(
                  right: 3,
                  bottom: 3,
                  child: Icon(
                    Icons.play_circle_filled_rounded,
                    color: Colors.white,
                    size: 16,
                    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Telegram's thumbnail [id], once it is on the phone. While the list is
  /// being flung, a tile that hasn't asked for its thumbnail yet waits and
  /// looks again next frame, so tiles that only fly past fetch nothing and
  /// keep the blurred preview; one already fetched or on its way shows at
  /// once. The frame-by-frame look is how Flutter's own images wait out a
  /// fling.
  static String? _thumbPath(BuildContext context, WidgetRef ref, int id) {
    final provider = thumbnailPathProvider(id);
    if (!ref.exists(provider) &&
        Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (context.mounted) (context as Element).markNeedsBuild();
      });
      return null;
    }
    return ref.watch(provider).value;
  }
}

/// The band along the bottom of a video tile: a play glyph at the left and,
/// when the length is known and the tile is wide enough to hold it, the
/// length at the right. A tile under 72 px, as in a dense grid on a small
/// phone, shows the glyph alone.
class _VideoBand extends StatelessWidget {
  const _VideoBand({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: 22,
        color: Colors.black.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
            const Spacer(),
            if (duration case final d? when constraints.maxWidth >= 72)
              Text(
                Formatters.length(d),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: tabularFigures,
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
        imageFilter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
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

/// Shows [placeholder] until [image] has its first frame, then fades the
/// image in over it, after which the placeholder leaves the tree. A picture
/// already decoded shows at once, with no fade.
class _Fading extends StatelessWidget {
  const _Fading({required this.image, this.placeholder});

  final ImageProvider image;
  final Widget? placeholder;

  static const _shown = ValueKey(true);

  @override
  Widget build(BuildContext context) {
    final waiting = placeholder ?? const SizedBox.shrink();
    return Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Decoded at about the size it is drawn, so shrinking it a little
      // more is all the filter does.
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => waiting,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              // Only the picture fades; the placeholder stays whole beneath
              // it until the fade ends, so the slot never shows through.
              transitionBuilder: (entry, animation) => entry.key == _shown
                  ? FadeTransition(opacity: animation, child: entry)
                  : entry,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: frame == null
                  ? KeyedSubtree(key: const ValueKey(false), child: waiting)
                  : KeyedSubtree(key: _shown, child: child),
            ),
    );
  }
}
