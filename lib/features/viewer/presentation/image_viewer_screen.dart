import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../backup/data/local_media.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/previews.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../photos/data/photos_visibility.dart';
import 'vertical_swipe.dart';

/// Full-screen viewer. Opened from the Photos timeline or an album it swipes
/// through every photo and video there; opened on a single file it shows
/// just that.
/// The blurred inline preview shows instantly and the full image fades in
/// over it; pinch or double-tap to zoom. Flick down to close, or up for the
/// file's details.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.fileId,
    this.source,
  });

  final String fileId;

  /// What to swipe through: `photos` (the timeline), `favorites`,
  /// `videos`, or `album:<id>`. Null shows the one file.
  final String? source;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  PageController? _pages;
  late String _currentId = widget.fileId;
  bool _chrome = true;
  bool _zoomed = false;

  /// Set while a page is being dragged up or down; the bars step aside.
  bool _dragging = false;

  @override
  void dispose() {
    _pages?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    _showSystemBars();
  }

  void _setDragging(bool dragging) {
    if (dragging == _dragging) return;
    setState(() => _dragging = dragging);
    _showSystemBars();
  }

  /// The status bar shows with the viewer's own bar.
  void _showSystemBars() {
    SystemChrome.setEnabledSystemUIMode(
      _chrome && !_dragging ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  /// Moves [file] to the Trash, with Undo. Its neighbour takes its place in
  /// the list and so on screen; when it was the [last] one the viewer
  /// closes, and the snack stays on the screen behind.
  Future<void> _trash(DriveFile file, {required bool last}) async {
    final moved = await FileActions.delete(context, ref, files: [file]);
    if (moved && last && mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    // The same list the grid showed, so a swipe never lands on a photo it
    // keeps out.
    List<DriveFile> timeline() => ref.watch(photosTimelineProvider).value ?? const [];
    final List<DriveFile> files = switch (widget.source) {
      'photos' => timeline(),
      'favorites' => timeline().where((f) => f.starred).toList(),
      'videos' => timeline().where((f) => f.kind == FileKind.video).toList(),
      final String source when source.startsWith('album:') =>
        ref.watch(albumFilesProvider(source.substring(6))).value ?? const [],
      _ => [?ref.watch(fileInfoProvider(widget.fileId)).value],
    };

    var index = files.indexWhere((f) => f.id == _currentId);
    if (index < 0 && files.isNotEmpty) {
      // The file was deleted or moved out of the list; stay near where it was.
      index = (_pages?.hasClients ?? false)
          ? (_pages!.page?.round() ?? 0).clamp(0, files.length - 1)
          : 0;
      _currentId = files[index].id;
    }
    _pages ??= files.isEmpty ? null : PageController(initialPage: index);
    final current = index >= 0 && index < files.length ? files[index] : null;
    // A file leaving or rejoining the list moves the ones after it along;
    // the page follows the one being looked at, so the bar always speaks
    // for the photo on screen.
    final pages = _pages;
    if (current != null && pages != null && pages.hasClients && pages.page?.round() != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pages.hasClients && pages.page?.round() != index) pages.jumpToPage(index);
      });
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: current == null
            ? AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white)
            : PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: AnimatedOpacity(
                  opacity: _chrome && !_dragging ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_chrome || _dragging,
                    child: _ViewerBar(
                      file: current,
                      position: widget.source == null
                          ? null
                          : (index: index, count: files.length),
                      onTrash: () => _trash(current, last: files.length <= 1),
                    ),
                  ),
                ),
              ),
        body: files.isEmpty || _pages == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: files.length,
                onPageChanged: (i) => setState(() {
                  _currentId = files[i].id;
                  _zoomed = false;
                }),
                itemBuilder: (context, i) {
                  final file = files[i];
                  final previewable = file.kind == FileKind.image && !file.isSplit;
                  return previewable
                      ? _ImagePage(
                          key: ValueKey(file.id),
                          file: file,
                          onTap: _toggleChrome,
                          onZoomChanged: (zoomed) {
                            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                          },
                          onDragging: _setDragging,
                        )
                      : _PosterPage(
                          key: ValueKey(file.id),
                          file: file,
                          onTap: _toggleChrome,
                          onDragging: _setDragging,
                        );
                },
              ),
      ),
    );
  }
}

class _ViewerBar extends ConsumerWidget {
  const _ViewerBar({required this.file, required this.position, required this.onTrash});

  final DriveFile file;

  /// Where [file] is in the list the viewer swipes through, or null when it
  /// was opened on the one file.
  final ({int index, int count})? position;

  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 12,
      fontFeatures: tabularFigures,
    );
    // The back arrow's own padding is gap enough before the title, which
    // needs the room with four actions beside it.
    final back = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    // The app's bars give their icons grey, which the dark bar would swallow;
    // the back arrow and the actions are white.
    return AppBar(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: back ? 0 : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          // The date is the short one the lists use, since Details has the
          // full one. With a count beside it the size is left out, since
          // Details has that too, so the date still fits on a narrow phone
          // next to four actions; if it must, the date gives way before the
          // count does.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  position == null
                      ? '${Formatters.bytes(file.size)} · ${Formatters.date(file.momentAt)}'
                      : Formatters.date(file.momentAt),
                  style: meta,
                ),
              ),
              if (position case final p?)
                Text(
                  ' · ${Formatters.number(p.index + 1)} of ${Formatters.number(p.count)}',
                  style: meta,
                ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () =>
              FileActions.setStarred(context, ref, [file], starred: !file.starred),
          icon: Icon(file.starred ? Icons.star_rounded : Icons.star_outline_rounded),
          tooltip: file.starred ? 'Unstar' : 'Star',
        ),
        IconButton(
          onPressed: () => FileActions.share(context, ref, file),
          icon: const Icon(Icons.ios_share_rounded),
          tooltip: 'Share',
        ),
        IconButton(
          onPressed: onTrash,
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Move to Trash',
        ),
        IconButton(
          onPressed: () => FileActions.showFileSheet(context, ref, file),
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'More',
        ),
      ],
    );
  }
}

/// A photo: preview first, full image when fetched, zoomable. Unzoomed, a
/// vertical flick closes the viewer or opens Details; zoomed, a drag pans.
class _ImagePage extends ConsumerStatefulWidget {
  const _ImagePage({
    super.key,
    required this.file,
    required this.onTap,
    required this.onZoomChanged,
    required this.onDragging,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onDragging;

  @override
  ConsumerState<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<_ImagePage> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTap;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    final position = _doubleTap?.localPosition ?? Offset.zero;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    // The phone's own copy, when the photo was backed up from here, opens at
    // once; only photos that live nowhere else come down from Telegram.
    final local = ref.watch(localOriginalProvider(widget.file.id));
    final localPath = local.value;
    final remote = local.isLoading || localPath != null
        ? null
        : ref.watch(filePreviewProvider(widget.file.id));
    final progress = remote?.value;
    final path = localPath ?? progress?.path;

    // The swipe sits inside InteractiveViewer, so its drag is claimed at
    // touch slop before the viewer's pan would be; zoomed, it steps aside.
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 6,
            child: VerticalSwipe(
              enabled: !_zoomed,
              onDismiss: () => Navigator.of(context).maybePop(),
              onSwipeUp: () => FileActions.showDetails(context, ref, widget.file),
              onDragging: widget.onDragging,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Placeholder(file: widget.file),
                  if (path != null)
                    Image(
                      image: _screenSized(context, File(path)),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                        opacity: frame == null && !sync ? 0 : 1,
                        duration: const Duration(milliseconds: 250),
                        child: child,
                      ),
                      errorBuilder: (_, _, _) => const _Message(
                        icon: Icons.broken_image_outlined,
                        text: 'This image can\'t be shown here. Try opening it in another app.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (remote?.hasError ?? false)
            IgnorePointer(
              child: _Message(icon: Icons.cloud_off_rounded, text: '${remote!.error}'),
            )
          else if (path == null && !local.isLoading)
            IgnorePointer(
              child: Center(child: _ProgressRing(fraction: progress?.fraction ?? 0)),
            ),
        ],
      ),
    );
  }

  /// Decodes big originals at twice the screen's width: sharp when zoomed
  /// in, without holding a 50-megapixel bitmap. Never upscales. Reads only
  /// the size and pixel ratio, so the status bar hiding during a drag
  /// doesn't rebuild the page.
  static ImageProvider _screenSized(BuildContext context, File file) {
    final pixels = MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
    final width = (pixels * 2).round().clamp(1080, 4096);
    return ResizeImage(
      FileImage(file),
      width: width,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }
}

/// Videos (and anything too large to preview): the poster frame with a play
/// button that fetches the file and hands it to a player app. A vertical
/// flick closes the viewer or opens Details, as on a photo.
class _PosterPage extends ConsumerWidget {
  const _PosterPage({
    super.key,
    required this.file,
    required this.onTap,
    required this.onDragging,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final ValueChanged<bool> onDragging;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVideo = file.kind == FileKind.video;
    return GestureDetector(
      onTap: onTap,
      child: VerticalSwipe(
        onDismiss: () => Navigator.of(context).maybePop(),
        onSwipeUp: () => FileActions.showDetails(context, ref, file),
        onDragging: onDragging,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Placeholder(file: file),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => FileActions.open(context, ref, file),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Icon(
                          isVideo ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${isVideo ? 'Play' : 'Open'} · ${Formatters.bytes(file.size)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: CircularProgressIndicator(
          value: fraction > 0 ? fraction : null,
          strokeWidth: 3,
          color: Colors.white,
          backgroundColor: Colors.white24,
        ),
      ),
    );
  }
}

class _Placeholder extends ConsumerWidget {
  const _Placeholder({required this.file});

  final DriveFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localThumbnailProvider((fileId: file.id, px: 512))).value;
    if (local != null) {
      return Image.memory(
        local,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    final thumb = file.thumbnailFileId == null
        ? null
        : ref.watch(thumbnailPathProvider(file.thumbnailFileId!)).value;
    if (thumb != null) {
      return Image.file(
        File(thumb),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    // A file from the timeline or an album comes without its inline
    // preview, which is read on its own.
    final mini = file.minithumbnail ??
        (file.hasMinithumbnail ? ref.watch(minithumbnailProvider(file.id)).value : null);
    if (mini != null) {
      // Only ever a stand-in; blurred so it doesn't read as a broken photo.
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.clamp),
        child: Image.memory(
          mini,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
