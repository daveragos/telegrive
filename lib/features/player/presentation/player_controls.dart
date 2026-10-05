import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';

/// The player's chrome: the title row with Back and More at the top, the
/// skip and play buttons in the middle, with Previous and Next around them
/// while a queue is playing, and the resume line, position, slider, length
/// and speed button along the bottom. Everything it shows comes from
/// [value], so it can be drawn without a player behind it.
class PlayerControls extends ConsumerWidget {
  const PlayerControls({
    super.key,
    required this.file,
    required this.value,
    required this.onPlay,
    required this.onSkip,
    required this.onSeek,
    required this.step,
    required this.speed,
    required this.onSpeed,
    this.resumedFrom,
    this.onStartOver,
    this.hasQueue = false,
    this.onPrevious,
    this.onNext,
  });

  final DriveFile? file;
  final VideoPlayerValue? value;
  final VoidCallback onPlay;

  /// Jumps [step] forward, or back when [forward] is false.
  final void Function(bool forward) onSkip;
  final void Function(Duration to) onSeek;

  /// How far the skip buttons jump, 10 or 30 seconds, which picks their
  /// glyphs.
  final Duration step;

  /// The speed the button shows, as '1.5×'.
  final double speed;
  final VoidCallback onSpeed;

  /// Where the file picked up from, shown as 'Resumed from 42:10' with
  /// Start over beside it while it is set.
  final Duration? resumedFrom;
  final VoidCallback? onStartOver;

  /// Whether the file is one of several playing through, which adds the
  /// Previous and Next buttons. Either is dimmed when its callback is null.
  final bool hasQueue;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = value?.isInitialized ?? false;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final buffered = value?.buffered.lastOrNull?.end ?? Duration.zero;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.7);
    final faint = Colors.white.withValues(alpha: 0.38);
    final max = duration.inMilliseconds.toDouble();
    final thirty = step.inSeconds == 30;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x99000000),
            Colors.transparent,
            Colors.transparent,
            Color(0x99000000),
          ],
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
                    onPressed: () =>
                        FileActions.showFileSheet(context, ref, file!, fromViewer: true),
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
                  if (hasQueue) ...[
                    IconButton(
                      onPressed: onPrevious,
                      disabledColor: faint,
                      icon: const Icon(Icons.skip_previous_rounded, size: 30),
                      color: white,
                      tooltip: 'Previous',
                    ),
                    const SizedBox(width: 12),
                  ],
                  IconButton(
                    onPressed: () => onSkip(false),
                    icon: Icon(
                      thirty
                          ? Icons.replay_30_rounded
                          : Icons.replay_10_rounded,
                      color: white,
                      size: 34,
                    ),
                    tooltip: thirty ? 'Back 30 seconds' : 'Back 10 seconds',
                  ),
                  const SizedBox(width: 24),
                  Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: IconButton(
                      padding: const EdgeInsets.all(14),
                      onPressed: onPlay,
                      icon: Icon(
                        value!.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: white,
                        size: 44,
                      ),
                      tooltip: value!.isPlaying ? 'Pause' : 'Play',
                    ),
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    onPressed: () => onSkip(true),
                    icon: Icon(
                      thirty
                          ? Icons.forward_30_rounded
                          : Icons.forward_10_rounded,
                      color: white,
                      size: 34,
                    ),
                    tooltip: thirty
                        ? 'Forward 30 seconds'
                        : 'Forward 10 seconds',
                  ),
                  if (hasQueue) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: onNext,
                      disabledColor: faint,
                      icon: const Icon(Icons.skip_next_rounded, size: 30),
                      color: white,
                      tooltip: 'Next',
                    ),
                  ],
                ],
              ),
            const Spacer(),
            if (ready)
              _ResumeLine(resumedFrom: resumedFrom, onStartOver: onStartOver),
            if (ready)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
                child: Row(
                  children: [
                    Text(
                      Formatters.length(position),
                      style: TextStyle(
                        color: dim,
                        fontFeatures: tabularFigures,
                      ),
                    ),
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
                          value: position.inMilliseconds
                              .clamp(0, max <= 0 ? 1 : max)
                              .toDouble(),
                          secondaryTrackValue: buffered.inMilliseconds
                              .clamp(0, max <= 0 ? 1 : max)
                              .toDouble(),
                          onChanged: max <= 0
                              ? null
                              : (ms) =>
                                    onSeek(Duration(milliseconds: ms.round())),
                        ),
                      ),
                    ),
                    Text(
                      Formatters.length(duration),
                      style: TextStyle(
                        color: dim,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Playback speed',
                      child: TextButton(
                        onPressed: onSpeed,
                        style: TextButton.styleFrom(
                          foregroundColor: white,
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularFigures,
                              ),
                        ),
                        child: Text(Formatters.rate(speed)),
                      ),
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

/// 'Resumed from 42:10' with Start over beside it, above the slider row.
/// When [resumedFrom] goes away the line keeps its last value while it
/// fades out over 180 ms, and only then gives up its height, so the slider
/// row moves up after the fade rather than jumping.
class _ResumeLine extends StatefulWidget {
  const _ResumeLine({required this.resumedFrom, required this.onStartOver});

  final Duration? resumedFrom;
  final VoidCallback? onStartOver;

  @override
  State<_ResumeLine> createState() => _ResumeLineState();
}

class _ResumeLineState extends State<_ResumeLine> {
  /// The last point shown, kept while the line fades.
  Duration? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.resumedFrom;
  }

  @override
  void didUpdateWidget(_ResumeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resumedFrom != null) _shown = widget.resumedFrom;
  }

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 180);
    final shown = _shown;
    final visible = widget.resumedFrom != null;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOut,
        onEnd: () {
          if (!visible && mounted) setState(() => _shown = null);
        },
        child: shown == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Text(
                      'Resumed from ${Formatters.length(shown)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: visible ? widget.onStartOver : null,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(48, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Start over'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
