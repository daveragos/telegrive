import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../backup/data/local_media.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/data/previews.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../photos/data/photos_visibility.dart';
import '../../player/data/stream_server.dart';
import '../../player/presentation/player_screen.dart';
import '../../transfers/data/transfer_queue.dart';
import 'vertical_swipe.dart';

/// Full-screen viewer. Opened from the Photos timeline or an album it swipes
/// through every photo and video there; opened on a single file it shows
/// just that.
/// The blurred inline preview shows instantly and the full image fades in
/// over it; pinch or double-tap to zoom. A video waits on its poster and
/// plays in place when tapped. Flick down to close, or up for the file's
/// details.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({super.key, required this.fileId, this.source});

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
      _chrome && !_dragging
          ? SystemUiMode.edgeToEdge
          : SystemUiMode.immersiveSticky,
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
    List<DriveFile> timeline() =>
        ref.watch(photosTimelineProvider).value ?? const [];
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
    if (current != null &&
        pages != null &&
        pages.hasClients &&
        pages.page?.round() != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pages.hasClients && pages.page?.round() != index) {
          pages.jumpToPage(index);
        }
      });
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: current == null
            ? AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
              )
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
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
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
                  final previewable =
                      file.kind == FileKind.image && !file.isSplit;
                  if (file.kind == FileKind.video) {
                    return _VideoPage(
                      key: ValueKey(file.id),
                      file: file,
                      isCurrent: i == index,
                      chrome: _chrome && !_dragging,
                      onTap: _toggleChrome,
                      onChrome: (visible) {
                        if (visible != _chrome) _toggleChrome();
                      },
                      onDragging: _setDragging,
                    );
                  }
                  return previewable
                      ? _ImagePage(
                          key: ValueKey(file.id),
                          file: file,
                          onTap: _toggleChrome,
                          onZoomChanged: (zoomed) {
                            if (zoomed != _zoomed) {
                              setState(() => _zoomed = zoomed);
                            }
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
  const _ViewerBar({
    required this.file,
    required this.position,
    required this.onTrash,
  });

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
          // count does. A small copy says so in the size's place, since its
          // size isn't the photo's.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  [
                    if (file.isSmallCopy)
                      'Small copy'
                    else if (position == null)
                      Formatters.bytes(file.size),
                    Formatters.date(file.momentAt),
                  ].join(' · '),
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
          onPressed: () => FileActions.setStarred(context, ref, [
            file,
          ], starred: !file.starred),
          icon: Icon(
            file.starred ? Icons.star_rounded : Icons.star_outline_rounded,
          ),
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
              onSwipeUp: () =>
                  FileActions.showDetails(context, ref, widget.file),
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
                      frameBuilder: (context, child, frame, sync) =>
                          AnimatedOpacity(
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
              child: _Message(
                icon: Icons.cloud_off_rounded,
                text: '${remote!.error}',
              ),
            )
          else if (path == null && !local.isLoading)
            IgnorePointer(
              child: Center(
                child: _ProgressRing(fraction: progress?.fraction ?? 0),
              ),
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
    final pixels =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final width = (pixels * 2).round().clamp(1080, 4096);
    return ResizeImage(
      FileImage(file),
      width: width,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }
}

/// Anything the viewer can't show in place, such as a photo too large to
/// preview: the poster frame with a button that fetches the file and hands
/// it to another app. A vertical flick closes the viewer or opens Details,
/// as on a photo.
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
            _OpenBadge(
              file: file,
              onTap: () => FileActions.open(context, ref, file),
            ),
          ],
        ),
      ),
    );
  }
}

/// The glyph in the middle of a poster, with a line under it saying what a
/// tap does and what the file is: 'Play · 1:24 · 84 MB' for a video, 'Open
/// · 84 MB' for anything else.
class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.file, required this.onTap});

  final DriveFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = file.kind == FileKind.video;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  isVideo
                      ? Icons.play_arrow_rounded
                      : Icons.open_in_new_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            [
              isVideo ? 'Play' : 'Open',
              if (file.duration case final d?) Formatters.length(d),
              Formatters.bytes(file.size),
            ].join(' · '),
            style: const TextStyle(
              color: Colors.white70,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// A video: the poster with a play glyph until it is tapped, then the video
/// itself, playing in place with sound. A tap on the video pauses it and
/// brings the bars back; another plays on. The bottom row scrubs and opens
/// the full player on the same file. Nothing is fetched until Play is
/// tapped, and leaving the page, by a swipe or by closing, stops the sound
/// and lets the player go. A vertical flick closes the viewer or opens
/// Details, as on a photo.
class _VideoPage extends ConsumerStatefulWidget {
  const _VideoPage({
    super.key,
    required this.file,
    required this.isCurrent,
    required this.chrome,
    required this.onTap,
    required this.onChrome,
    required this.onDragging,
  });

  final DriveFile file;

  /// Whether this is the page on screen; a page swiped away stops playing.
  final bool isCurrent;

  /// Whether the viewer's bars are showing; the bottom row follows them.
  final bool chrome;

  /// Toggles the viewer's bars.
  final VoidCallback onTap;

  /// Shows or hides the viewer's bars.
  final ValueChanged<bool> onChrome;
  final ValueChanged<bool> onDragging;

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _starting = false;
  Timer? _hide;

  bool get _playing => _controller?.value.isPlaying ?? false;
  bool get _ready => _controller?.value.isInitialized ?? false;

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent && !widget.isCurrent) _release();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// Stops playback and lets the player go; the poster is back next build.
  void _release() {
    _hide?.cancel();
    _hide = null;
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onTick);
    unawaited(_letGo(controller));
  }

  /// Quiets [controller] and disposes it, whether or not it ever started;
  /// a player that failed to initialise may refuse the pause.
  static Future<void> _letGo(VideoPlayerController controller) async {
    try {
      await controller.pause();
    } catch (_) {
      // There is nothing to pause; the dispose below still runs.
    } finally {
      await controller.dispose();
    }
  }

  /// Records [error] and drops the player, so the page is the poster again
  /// under the message: a tap works the bars as on any other page.
  void _fail(Object error) {
    _release();
    if (mounted) setState(() => _error = error);
  }

  Future<void> _play() async {
    if (_controller != null || _starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    final file = widget.file;
    VideoPlayerController? controller;
    try {
      final local = await ref
          .read(transferQueueProvider.notifier)
          .localPathIfAvailable(file);
      controller = local != null
          ? VideoPlayerController.file(File(local))
          : VideoPlayerController.networkUrl(
              await ref.read(streamServerProvider).urlFor(file),
            );
      if (!mounted || !widget.isCurrent) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      unawaited(learnLength(ref, file, controller.value.duration));
      await controller.play();
      _scheduleHide();
    } catch (e) {
      // A player let go while it was starting, by a swipe or by its own
      // error report, has already been dealt with.
      if (controller != null && _controller == controller) _fail(e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null || !mounted) return;
    if (value.hasError) {
      _fail(value.errorDescription ?? 'This video can\'t be played here.');
    } else {
      setState(() {});
    }
  }

  /// Hides the bars three seconds into playback, unless it stopped first.
  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) widget.onChrome(false);
    });
  }

  /// Pauses a playing video and shows the bars; plays a paused one on, from
  /// the start again once it has reached the end.
  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _hide?.cancel();
      await controller.pause();
      widget.onChrome(true);
    } else {
      final value = controller.value;
      if (value.duration > Duration.zero && value.position >= value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _scheduleHide();
    }
  }

  /// Hands the file to the full player, paused here so nothing plays twice.
  Future<void> _fullScreen() async {
    _hide?.cancel();
    await _controller?.pause();
    if (!mounted) return;
    widget.onChrome(true);
    await context.push('/play/${widget.file.id}');
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final controller = _controller;
    final value = controller?.value;
    final dim = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontFeatures: tabularFigures,
    );
    return VerticalSwipe(
      onDismiss: () => Navigator.of(context).maybePop(),
      onSwipeUp: () => FileActions.showDetails(context, ref, file),
      onDragging: widget.onDragging,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller == null ? widget.onTap : _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && value != null)
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
              )
            else
              _Placeholder(file: file),
            if (_starting || (_ready && value!.isBuffering && _error == null))
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            // The glyph and its line step aside while the video runs and
            // come back the moment it stops.
            AnimatedOpacity(
              opacity: !_playing && !_starting && _error == null ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: _playing || _starting || _error != null,
                child: _OpenBadge(
                  file: file,
                  onTap: controller == null ? _play : _toggle,
                ),
              ),
            ),
            if (_error != null)
              _Message(
                icon: Icons.error_outline_rounded,
                text: 'This video can\'t be played here.',
                action: FilledButton.tonal(
                  onPressed: () =>
                      FileActions.openExternally(context, ref, file),
                  child: const Text('Open with another app'),
                ),
              ),
            if (_ready && value != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: widget.chrome ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !widget.chrome,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(Formatters.length(value.position), style: dim),
                            Expanded(
                              child: VideoProgressIndicator(
                                controller!,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                colors: const VideoProgressColors(
                                  playedColor: Colors.white,
                                  bufferedColor: Colors.white54,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                            Text(Formatters.length(value.duration), style: dim),
                            IconButton(
                              onPressed: _fullScreen,
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                              ),
                              tooltip: 'Full screen',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
    final local = ref
        .watch(localThumbnailProvider((fileId: file.id, px: 512)))
        .value;
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
    final mini =
        file.minithumbnail ??
        (file.hasMinithumbnail
            ? ref.watch(minithumbnailProvider(file.id)).value
            : null);
    if (mini != null) {
      // Only ever a stand-in; blurred so it doesn't read as a broken photo.
      return ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 16,
          sigmaY: 16,
          tileMode: TileMode.clamp,
        ),
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

/// A sentence over the page, with a way out under it when there is one.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

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
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
