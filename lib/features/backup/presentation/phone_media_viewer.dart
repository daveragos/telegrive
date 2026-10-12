import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/common.dart';
import '../data/backup_controller.dart';
import '../data/local_media.dart';
import 'backup_queue_screen.dart';

/// What [PhoneMediaViewer] shows: the phone's photos [assetIds], opening
/// on [initial].
@immutable
class PhoneMediaArgs {
  const PhoneMediaArgs({required this.assetIds, required this.initial});

  final List<String> assetIds;
  final String initial;
}

/// Where a photo on the phone stands in backup, as the viewer's bar says.
enum _Standing { waiting, goingUp, backedUp, skipped, other }

/// Photos and videos on this phone, full screen, from the phone's own
/// copies, so ones not yet in the drive can be looked at: the Backup queue
/// opens one and swipes on through the rest it lists. Pinch or double-tap
/// zooms a photo, and a tap plays a video. The bar says where the one on
/// screen stands in backup, with Back up now and Don't back up while it
/// waits, and the way to the drive's copy once it is backed up.
class PhoneMediaViewer extends ConsumerStatefulWidget {
  const PhoneMediaViewer({super.key, required this.args});

  final PhoneMediaArgs args;

  @override
  ConsumerState<PhoneMediaViewer> createState() => _PhoneMediaViewerState();
}

class _PhoneMediaViewerState extends ConsumerState<PhoneMediaViewer> {
  late final List<String> _ids = widget.args.assetIds.isEmpty
      ? [widget.args.initial]
      : widget.args.assetIds;
  late int _index = _ids.indexOf(widget.args.initial).clamp(0, _ids.length - 1);
  late final _pages = PageController(initialPage: _index);
  bool _chrome = true;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(_chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    final id = _ids[_index];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedOpacity(
            opacity: _chrome ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_chrome,
              child: _Bar(assetId: id, index: _index, count: _ids.length),
            ),
          ),
        ),
        body: PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
          itemCount: _ids.length,
          onPageChanged: (i) => setState(() {
            _index = i;
            _zoomed = false;
          }),
          itemBuilder: (context, i) => _Page(
            key: ValueKey(_ids[i]),
            assetId: _ids[i],
            isCurrent: i == _index,
            onTap: _toggleChrome,
            onZoomChanged: (zoomed) {
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
          ),
        ),
      ),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar({required this.assetId, required this.index, required this.count});

  final String assetId;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupControllerProvider);
    final upload = ref
        .watch(backupUploadsProvider)
        .where((t) => t.row.assetId == assetId)
        .firstOrNull;
    final recent = backup.recent.where((r) => r.assetId == assetId).firstOrNull;
    final standing = recent != null
        ? _Standing.backedUp
        : upload != null
        ? _Standing.goingUp
        : backup.skippedIds.contains(assetId)
        ? _Standing.skipped
        : backup.waiting.any((a) => a.assetId == assetId)
        ? _Standing.waiting
        : _Standing.other;
    final taken = ref.watch(phoneAssetProvider(assetId)).value?.createDateTime;
    final name = ref.watch(assetTitleProvider(assetId)).value ?? '';
    final meta = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 12,
      fontFeatures: tabularFigures,
    );
    final controller = ref.read(backupControllerProvider.notifier);

    return AppBar(
      backgroundColor: Colors.black.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16)),
          Text(
            [
              switch (standing) {
                _Standing.waiting => 'Waiting',
                _Standing.goingUp => 'Going up · ${(upload!.progress * 100).floor()}%',
                _Standing.backedUp => 'Backed up',
                _Standing.skipped => 'Skipped',
                _Standing.other => 'On this phone',
              },
              if (taken != null) Formatters.date(taken),
              if (count > 1) '${Formatters.number(index + 1)} of ${Formatters.number(count)}',
            ].join(' · '),
            overflow: TextOverflow.ellipsis,
            style: meta,
          ),
        ],
      ),
      actions: [
        if (standing == _Standing.waiting)
          IconButton(
            // Nothing goes up while backup is held, so neither can one
            // photo first.
            onPressed: canBackUpNow(backup.phase)
                ? () {
                    controller.backUpNow(assetId);
                    showSnack(context, 'Goes up next');
                  }
                : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Back up now',
          ),
        if (standing == _Standing.waiting || standing == _Standing.goingUp)
          IconButton(
            onPressed: () => skipWaitingPhoto(context, ref, assetId),
            icon: const Icon(Icons.cloud_off_outlined),
            tooltip: 'Don\'t back up',
          ),
        if (recent != null)
          IconButton(
            onPressed: () => context.push('/viewer/${recent.fileId}'),
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Open in your drive',
          ),
      ],
    );
  }
}

/// Whether one photo can go up ahead of the rest in [phase]: not while
/// backup is off or held up (no Wi-Fi, the monthly data limit, no photo
/// access, the drive still opening), when nothing goes up at all.
bool canBackUpNow(BackupPhase phase) => switch (phase) {
  BackupPhase.waitingForWifi ||
  BackupPhase.waitingForBudget ||
  BackupPhase.needsPermission ||
  BackupPhase.off ||
  BackupPhase.waitingForDrive => false,
  _ => true,
};

/// One photo or video, the phone's copy, over its thumbnail until that has
/// loaded.
class _Page extends ConsumerWidget {
  const _Page({
    super.key,
    required this.assetId,
    required this.isCurrent,
    required this.onTap,
    required this.onZoomChanged,
  });

  final String assetId;
  final bool isCurrent;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(phoneAssetProvider(assetId));
    final path = ref.watch(phoneAssetPathProvider(assetId));
    final thumbnail = ref.watch(assetThumbnailProvider(assetId)).value;
    final poster = thumbnail == null
        ? const SizedBox.expand()
        : Image.memory(thumbnail, fit: BoxFit.contain, gaplessPlayback: true);

    if (asset.isLoading || path.isLoading) {
      return GestureDetector(onTap: onTap, child: poster);
    }
    final file = path.value;
    if (asset.value == null || file == null) {
      return GestureDetector(
        onTap: onTap,
        child: const _Message('This photo is no longer on this phone.'),
      );
    }
    if (asset.value!.type == AssetType.video) {
      return _VideoPage(path: file, poster: poster, isCurrent: isCurrent, onTap: onTap);
    }
    return _PhotoPage(path: file, poster: poster, onTap: onTap, onZoomChanged: onZoomChanged);
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    required this.path,
    required this.poster,
    required this.onTap,
    required this.onZoomChanged,
  });

  final String path;
  final Widget poster;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTap;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      _zoomed = zoomed;
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
    // Big originals decode at twice the screen's width: sharp when zoomed
    // in, without holding a 50-megapixel bitmap.
    final pixels = MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
    final width = (pixels * 2).round().clamp(1080, 4096);
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.poster,
            Image(
              image: ResizeImage(
                FileImage(File(widget.path)),
                width: width,
                policy: ResizeImagePolicy.fit,
                allowUpscaling: false,
              ),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                opacity: frame == null && !sync ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: child,
              ),
              errorBuilder: (_, _, _) => const _Message('This photo can\'t be shown here.'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A video: its poster with a play button, playing in place once tapped.
/// A tap pauses it again, and a page swiped away stops.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.path,
    required this.poster,
    required this.isCurrent,
    required this.onTap,
  });

  final String path;
  final Widget poster;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

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

  void _release() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onTick);
    unawaited(controller.pause().catchError((_) {}).whenComplete(controller.dispose));
  }

  void _onTick() {
    if (!mounted) return;
    if (_controller?.value.hasError ?? false) {
      _release();
      setState(() => _failed = true);
    } else {
      setState(() {});
    }
  }

  Future<void> _tap() async {
    final controller = _controller;
    if (controller == null) {
      final started = VideoPlayerController.file(File(widget.path));
      setState(() {
        _controller = started;
        _failed = false;
      });
      started.addListener(_onTick);
      try {
        await started.initialize();
        if (_controller == started) await started.play();
      } catch (_) {
        if (_controller == started) {
          _release();
          if (mounted) setState(() => _failed = true);
        }
      }
      return;
    }
    if (!controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final value = controller.value;
      if (value.duration > Duration.zero && value.position >= value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller?.value.isInitialized ?? false;
    final playing = controller?.value.isPlaying ?? false;
    return GestureDetector(
      onTap: controller == null ? widget.onTap : _tap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else
            widget.poster,
          if (_failed)
            const _Message('This video can\'t be played here.')
          else if (!playing)
            Center(
              child: IconButton.filled(
                onPressed: _tap,
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                icon: controller != null && !ready
                    ? const SizedBox.square(
                        dimension: 40,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                tooltip: 'Play',
              ),
            ),
          if (ready)
            Positioned(
              left: Space.gutter,
              right: Space.gutter,
              bottom: MediaQuery.paddingOf(context).bottom + Space.l,
              child: VideoProgressIndicator(
                controller!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white.withValues(alpha: 0.4),
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xxl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    ),
  );
}
