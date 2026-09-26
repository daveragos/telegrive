import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/stream_server.dart';

/// Plays a video or audio file as it streams from Telegram, or from the
/// phone when a copy is already here.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.fileId});

  final String fileId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  DriveFile? _file;
  Object? _error;
  bool _chrome = true;
  Timer? _hideChrome;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final file = await ref.read(driveRepositoryProvider).fileById(widget.fileId);
      if (file == null) throw const DriveException('This file is no longer in your drive.');
      if (!mounted) return;
      setState(() => _file = file);

      final local = await ref.read(transferQueueProvider.notifier).localPathIfAvailable(file);
      final controller = local != null
          ? VideoPlayerController.file(File(local))
          : VideoPlayerController.networkUrl(
              await ref.read(streamServerProvider).urlFor(file),
            );
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted) return;
      await controller.play();
      _scheduleHide();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.hasError && _error == null) {
      setState(() => _error = value.errorDescription ?? 'This file can\'t be played here.');
    } else {
      setState(() {});
    }
  }

  void _scheduleHide() {
    _hideChrome?.cancel();
    if (_isAudio) return;
    _hideChrome = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) _setChrome(false);
    });
  }

  void _setChrome(bool visible) {
    setState(() => _chrome = visible);
    SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
    if (visible) _scheduleHide();
  }

  bool get _isAudio => _file?.kind == FileKind.audio;

  @override
  void dispose() {
    _hideChrome?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    _scheduleHide();
  }

  Future<void> _skip(Duration by) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.seekTo(controller.value.position + by);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final controller = _controller;
    final value = controller?.value;
    final ready = value?.isInitialized ?? false;

    Widget stage;
    if (_error != null) {
      stage = _Problem(
        message: '$_error'.contains('Exception') || '$_error'.contains('Error')
            ? 'This file can\'t be played here.'
            : '$_error',
        file: file,
      );
    } else if (_isAudio && file != null) {
      stage = _AudioArt(file: file);
    } else if (ready) {
      stage = Center(
        child: AspectRatio(
          aspectRatio: value!.aspectRatio,
          child: VideoPlayer(controller!),
        ),
      );
    } else {
      stage = const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _setChrome(!_chrome),
          onDoubleTapDown: (details) {
            final half = MediaQuery.sizeOf(context).width / 2;
            _skip(Duration(seconds: details.localPosition.dx < half ? -10 : 10));
          },
          onDoubleTap: () {},
          child: Stack(
            fit: StackFit.expand,
            children: [
              stage,
              if (ready && (value!.isBuffering) && _error == null)
                const Center(child: CircularProgressIndicator(color: Colors.white70)),
              AnimatedOpacity(
                opacity: _chrome || _isAudio ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !(_chrome || _isAudio),
                  child: _Controls(
                    file: file,
                    value: value,
                    onPlay: _togglePlay,
                    onSkip: _skip,
                    onSeek: (to) async {
                      await controller?.seekTo(to);
                      _scheduleHide();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.file,
    required this.value,
    required this.onPlay,
    required this.onSkip,
    required this.onSeek,
  });

  final DriveFile? file;
  final VideoPlayerValue? value;
  final VoidCallback onPlay;
  final void Function(Duration by) onSkip;
  final void Function(Duration to) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = value?.isInitialized ?? false;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final buffered = value?.buffered.lastOrNull?.end ?? Duration.zero;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.7);
    final max = duration.inMilliseconds.toDouble();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Color(0x99000000)],
          stops: [0, 0.2, 0.75, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const BackButton(color: white),
                Expanded(
                  child: Text(
                    file?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: white, fontSize: 16),
                  ),
                ),
                if (file != null)
                  IconButton(
                    onPressed: () => FileActions.showFileSheet(context, ref, file!),
                    icon: const Icon(Icons.more_vert_rounded, color: white),
                    tooltip: 'More',
                  ),
              ],
            ),
            const Spacer(),
            if (ready)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => onSkip(const Duration(seconds: -10)),
                    icon: const Icon(Icons.replay_10_rounded, color: white, size: 34),
                    tooltip: 'Back 10 seconds',
                  ),
                  const SizedBox(width: 24),
                  Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: IconButton(
                      padding: const EdgeInsets.all(14),
                      onPressed: onPlay,
                      icon: Icon(
                        value!.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: white,
                        size: 44,
                      ),
                      tooltip: value!.isPlaying ? 'Pause' : 'Play',
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    onPressed: () => onSkip(const Duration(seconds: 10)),
                    icon: const Icon(Icons.forward_10_rounded, color: white, size: 34),
                    tooltip: 'Forward 10 seconds',
                  ),
                ],
              ),
            const Spacer(),
            if (ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Text(_clock(position), style: TextStyle(color: dim, fontFeatures: const [FontFeature.tabularFigures()])),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: white,
                          inactiveTrackColor: Colors.white24,
                          secondaryActiveTrackColor: Colors.white54,
                          thumbColor: white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          max: max <= 0 ? 1 : max,
                          value: position.inMilliseconds.clamp(0, max <= 0 ? 1 : max).toDouble(),
                          secondaryTrackValue:
                              buffered.inMilliseconds.clamp(0, max <= 0 ? 1 : max).toDouble(),
                          onChanged: max <= 0
                              ? null
                              : (ms) => onSeek(Duration(milliseconds: ms.round())),
                        ),
                      ),
                    ),
                    Text(_clock(duration), style: TextStyle(color: dim, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(hours > 0 ? 2 : 1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

/// Album art (the file's thumbnail) and the track's name.
class _AudioArt extends StatelessWidget {
  const _AudioArt({required this.file});

  final DriveFile file;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.square(
                dimension: 220,
                child: file.hasPreview
                    ? FileThumbnail(file: file, expand: true, radius: 0, size: 64)
                    : const ColoredBox(
                        color: Color(0xFF20242A),
                        child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 96),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              file.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              Formatters.bytes(file.size),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends ConsumerWidget {
  const _Problem({required this.message, required this.file});

  final String message;
  final DriveFile? file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (file != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => FileActions.openExternally(context, ref, file!),
                child: const Text('Open with another app'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
