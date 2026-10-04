import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/files/file_kind.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/file_visuals.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/storage/preferences.dart';
import '../../drive/data/drive_repository.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/playback.dart';
import '../data/stream_server.dart';
import 'player_controls.dart';

/// Keeps the length a player found for [file] in the index when the drive
/// doesn't know it yet, so its rows and tiles can say it from now on. It
/// is written to this phone only; the caption picks it up on its next edit.
Future<void> learnLength(WidgetRef ref, DriveFile file, Duration known) async {
  if (file.durationSeconds != null || known <= Duration.zero) return;
  await ref
      .read(appDatabaseProvider)
      .updateFile(
        file.id,
        DriveFilesCompanion(durationSeconds: Value(known.inSeconds)),
      );
}

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

  /// The speed the person chose, the one playback returns to after a hold.
  double _speed = 1;

  /// Whether a press-and-hold on the stage is playing at [Playback.held].
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final file = await ref
          .read(driveRepositoryProvider)
          .fileById(widget.fileId);
      if (file == null) {
        throw const DriveException('This file is no longer in your drive.');
      }
      if (!mounted) return;
      setState(() => _file = file);

      final local = await ref
          .read(transferQueueProvider.notifier)
          .localPathIfAvailable(file);
      final controller = local != null
          ? VideoPlayerController.file(File(local))
          : VideoPlayerController.networkUrl(
              await ref.read(streamServerProvider).urlFor(file),
            );
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted) return;
      unawaited(learnLength(ref, file, controller.value.duration));
      _speed = Playback.sanitize(
        ref
            .read(preferencesProvider)
            .playbackSpeed(audio: file.kind == FileKind.audio),
      );
      await _applySpeed(_speed);
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
      setState(
        () => _error =
            value.errorDescription ?? 'This file can\'t be played here.',
      );
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

  /// Jumps [Playback.skipStep] forward or back, staying inside the file.
  Future<void> _skip(bool forward) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final step = Playback.skipStep(value.duration);
    final to = forward ? value.position + step : value.position - step;
    await controller.seekTo(
      to < Duration.zero
          ? Duration.zero
          : to > value.duration
          ? value.duration
          : to,
    );
    if (!mounted) return;
    _scheduleHide();
  }

  /// Asks the player for [speed]. A device that refuses a speed keeps
  /// playing at the one it has, so a refusal is nothing to show.
  Future<void> _applySpeed(double speed) async {
    try {
      await _controller?.setPlaybackSpeed(speed);
    } catch (_) {}
  }

  /// Moves to the next speed, applies it unless a hold is running at 2×,
  /// and remembers it for this kind of file.
  Future<void> _cycleSpeed() async {
    final file = _file;
    if (file == null) return;
    _speed = Playback.next(_speed);
    if (!_holding) await _applySpeed(_speed);
    unawaited(
      ref
          .read(preferencesProvider)
          .setPlaybackSpeed(_speed, audio: file.kind == FileKind.audio),
    );
    if (!mounted) return;
    setState(() {});
    _scheduleHide();
  }

  /// Starts or ends a press-and-hold at [Playback.held]. Holding does
  /// nothing while paused or when the chosen speed is already that fast.
  Future<void> _hold(bool on) async {
    final controller = _controller;
    if (controller == null) return;
    if (on && (!controller.value.isPlaying || _speed == Playback.held)) {
      return;
    }
    if (!on && !_holding) return;
    setState(() => _holding = on);
    await _applySpeed(on ? Playback.held : _speed);
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
      stage = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
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
            _skip(details.localPosition.dx >= half);
          },
          onDoubleTap: () {},
          onLongPressStart: (_) => _hold(true),
          onLongPressEnd: (_) => _hold(false),
          onLongPressCancel: () => _hold(false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              stage,
              if (ready && (value!.isBuffering) && _error == null)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
              AnimatedOpacity(
                opacity: _chrome || _isAudio ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !(_chrome || _isAudio),
                  child: PlayerControls(
                    file: file,
                    value: value,
                    onPlay: _togglePlay,
                    onSkip: _skip,
                    onSeek: (to) async {
                      await controller?.seekTo(to);
                      _scheduleHide();
                    },
                    step: Playback.skipStep(value?.duration ?? Duration.zero),
                    speed: _speed,
                    onSpeed: _cycleSpeed,
                  ),
                ),
              ),
              _HeldSpeedLabel(visible: _holding),
            ],
          ),
        ),
      ),
    );
  }
}

/// The '2×' label that sits under the title row while a press-and-hold
/// plays at double speed. It shows whether or not the chrome is up, and
/// never takes a touch.
class _HeldSpeedLabel extends StatelessWidget {
  const _HeldSpeedLabel({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight + 8),
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Formatters.rate(Playback.held),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                    ? FileThumbnail(
                        file: file,
                        expand: true,
                        radius: 0,
                        size: 64,
                      )
                    : const ColoredBox(
                        color: Color(0xFF20242A),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white54,
                          size: 96,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              file.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
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
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (file != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () =>
                    FileActions.openExternally(context, ref, file!),
                child: const Text('Open with another app'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
