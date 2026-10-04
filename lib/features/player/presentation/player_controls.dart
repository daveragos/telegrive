import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/format/formatters.dart';
import '../../drive/domain/drive_models.dart';
import '../../files/presentation/file_actions.dart';

/// The player's chrome: the title row with Back and More at the top, the
/// skip and play buttons in the middle, and the position, slider, length
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = value?.isInitialized ?? false;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final buffered = value?.buffered.lastOrNull?.end ?? Duration.zero;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.7);
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
                        FileActions.showFileSheet(context, ref, file!),
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
                ],
              ),
            const Spacer(),
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
