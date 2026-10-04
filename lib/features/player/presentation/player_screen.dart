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
import '../../files/data/browse_preferences.dart';
import '../../files/presentation/file_actions.dart';
import '../../transfers/data/transfer_queue.dart';
import '../data/play_positions.dart';
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
/// phone when a copy is already here. A video or long recording picks up
/// where this phone last stopped it, and an audio file opened from a
/// folder plays on through that folder's audio files.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.fileId, this.source});

  final String fileId;

  /// Where the file was opened from: `folder:<id>`, with an empty id for
  /// the root, queues that folder's audio files. Null plays the file alone.
  final String? source;

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

  /// The folder's audio files in list order, or empty when the file plays
  /// alone.
  List<DriveFile> _queue = const [];

  /// Taken once at the start, so the last save in [dispose] never goes
  /// through [ref].
  late final PlayPositionStore _positions;
  Timer? _saveTimer;

  /// Where the current file picked up from, while the resume line shows.
  Duration? _resumedFrom;
  Timer? _resumedHide;

  /// Set once a file's end has moved on to the next, so one completion
  /// advances only once.
  bool _advancing = false;

  /// Counts each file opened, so an opening overtaken by Next or Previous
  /// lets go of its player instead of starting it.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _positions = ref.read(playPositionsProvider);
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
      await _buildQueue(file);
      if (!mounted) return;
      await _open(file);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Reads the folder [source] names and keeps its audio files in the
  /// order the list shows them, when [file] is an audio file among them.
  Future<void> _buildQueue(DriveFile file) async {
    const prefix = 'folder:';
    final source = widget.source;
    if (file.kind != FileKind.audio ||
        source == null ||
        !source.startsWith(prefix)) {
      return;
    }
    final id = source.substring(prefix.length);
    final contents = await ref
        .read(driveRepositoryProvider)
        .watchFolder(id.isEmpty ? null : id)
        .first;
    final queue = PlayQueue.fromFolder(
      contents,
      ref.read(browsePreferencesProvider).sort,
    );
    if (queue.any((f) => f.id == file.id)) _queue = queue;
  }

  /// Lets go of the file playing now, saving where it stopped, and starts
  /// [file] from its saved point when it has one.
  Future<void> _open(DriveFile file) async {
    final generation = ++_generation;
    final old = _controller;
    final oldFile = _file;
    _saveTimer?.cancel();
    _resumedHide?.cancel();
    old?.removeListener(_onTick);
    _controller = null;
    if (old != null && oldFile != null) {
      unawaited(_record(oldFile.id, old.value));
    }
    unawaited(old?.dispose());
    setState(() {
      _file = file;
      _error = null;
      _resumedFrom = null;
      _advancing = false;
    });

    VideoPlayerController? controller;
    try {
      final local = await ref
          .read(transferQueueProvider.notifier)
          .localPathIfAvailable(file);
      if (!mounted || generation != _generation) return;
      controller = local != null
          ? VideoPlayerController.file(File(local))
          : VideoPlayerController.networkUrl(
              await ref.read(streamServerProvider).urlFor(file),
            );
      if (!mounted || generation != _generation) {
        unawaited(controller.dispose());
        return;
      }
      _controller = controller;
      controller.addListener(_onTick);
      await controller.initialize();
      if (!mounted || generation != _generation) return;
      unawaited(learnLength(ref, file, controller.value.duration));
      _speed = Playback.sanitize(
        ref
            .read(preferencesProvider)
            .playbackSpeed(audio: file.kind == FileKind.audio),
      );
      await _applySpeed(_speed);
      final at = await _positions.resumePoint(
        file.id,
        controller.value.duration,
      );
      if (!mounted || generation != _generation) return;
      if (at != null) {
        await controller.seekTo(at);
        if (!mounted || generation != _generation) return;
        _resumedFrom = at;
        _resumedHide = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _resumedFrom = null);
        });
      }
      await controller.play();
      if (!mounted || generation != _generation) return;
      _startSaving();
      _scheduleHide();
      setState(() {});
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    }
  }

  /// Keeps where [value] is in [fileId], or forgets the file when the point
  /// isn't worth keeping. Nothing is written for a player that hasn't
  /// started or doesn't know its length.
  Future<void> _record(String fileId, VideoPlayerValue value) {
    if (!value.isInitialized || value.duration <= Duration.zero) {
      return Future.value();
    }
    return _positions.record(fileId, value.position, value.duration);
  }

  /// Writes the position every 5 seconds while the file plays. The timer
  /// stops when the file ends or another one opens, and starts again when
  /// play is pressed.
  void _startSaving() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persist());
  }

  /// Saves where the current file is, without waiting.
  void _persist() {
    final controller = _controller;
    final file = _file;
    if (controller == null || file == null) return;
    unawaited(_record(file.id, controller.value));
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.hasError && _error == null) {
      setState(
        () => _error =
            value.errorDescription ?? 'This file can\'t be played here.',
      );
      return;
    }
    if (!value.isCompleted) {
      _advancing = false;
    } else if (!_advancing) {
      _advancing = true;
      _saveTimer?.cancel();
      final file = _file;
      if (file != null) {
        unawaited(_positions.record(file.id, value.duration, value.duration));
      }
      final next = _neighbour(1);
      if (next != null) unawaited(_open(next));
    }
    setState(() {});
  }

  /// The file [step] places from the current one in the queue, or null at
  /// either end or when nothing is queued.
  DriveFile? _neighbour(int step) {
    final id = _file?.id;
    if (id == null) return null;
    final index = _queue.indexWhere((f) => f.id == id);
    if (index < 0) return null;
    final target = index + step;
    return target >= 0 && target < _queue.length ? _queue[target] : null;
  }

  Future<void> _next() async {
    final next = _neighbour(1);
    if (next != null) await _open(next);
  }

  /// Restarts the current file when it is more than 3 seconds in, and
  /// otherwise moves back to the one before it.
  Future<void> _previous() async {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.position > const Duration(seconds: 3)) {
      await controller.seekTo(Duration.zero);
      if (mounted) _scheduleHide();
      return;
    }
    final previous = _neighbour(-1);
    if (previous != null) await _open(previous);
  }

  /// Whether Previous has something to do: a restart or an earlier file.
  bool get _canGoBack =>
      _neighbour(-1) != null ||
      (_controller?.value.position ?? Duration.zero) >
          const Duration(seconds: 3);

  /// Plays the current file from its start and forgets its saved point.
  Future<void> _startOver() async {
    final controller = _controller;
    final file = _file;
    _resumedHide?.cancel();
    setState(() => _resumedFrom = null);
    if (file != null) unawaited(_positions.forget(file.id));
    await controller?.seekTo(Duration.zero);
    if (mounted) _scheduleHide();
  }

  void _scheduleHide() {
    _hideChrome?.cancel();
    if (_isAudio) return;
    _hideChrome = Timer(Duration(seconds: _resumedFrom != null ? 5 : 3), () {
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
    _saveTimer?.cancel();
    _resumedHide?.cancel();
    _persist();
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
      _persist();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (!mounted) return;
      _startSaving();
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
    final hasQueue = _queue.length > 1;

    Widget stage;
    if (_error != null) {
      stage = _Problem(
        message: '$_error'.contains('Exception') || '$_error'.contains('Error')
            ? 'This file can\'t be played here.'
            : '$_error',
        file: file,
      );
    } else if (_isAudio && file != null) {
      final track = _queue.indexWhere((f) => f.id == file.id);
      stage = _AudioArt(
        file: file,
        trackLine: hasQueue && track >= 0
            ? 'Track ${track + 1} of ${_queue.length} · '
                  '${Formatters.bytes(file.size)}'
            : null,
      );
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
                    resumedFrom: _resumedFrom,
                    onStartOver: _startOver,
                    hasQueue: hasQueue,
                    onPrevious: hasQueue && _canGoBack ? _previous : null,
                    onNext: _neighbour(1) != null ? _next : null,
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

/// Album art (the file's thumbnail) and the track's name, with its place
/// in the queue as 'Track 3 of 14 · 48.2 MB' when it is playing through a
/// folder, or its size alone.
class _AudioArt extends StatelessWidget {
  const _AudioArt({required this.file, this.trackLine});

  final DriveFile file;
  final String? trackLine;

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
              trackLine ?? Formatters.bytes(file.size),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontFeatures: tabularFigures,
              ),
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
