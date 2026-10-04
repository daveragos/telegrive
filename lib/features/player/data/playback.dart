/// The rules the player follows for speed and skipping, kept apart from the
/// widgets so they can be tested on their own.
abstract final class Playback {
  /// The speeds the speed button cycles through, slowest first.
  static const List<double> speeds = [0.75, 1, 1.25, 1.5, 1.75, 2];

  /// The speed a press-and-hold on the stage plays at.
  static const double held = 2;

  /// The first speed above [current], wrapping round to the slowest after
  /// the fastest.
  static double next(double current) {
    for (final speed in speeds) {
      if (speed > current) return speed;
    }
    return speeds.first;
  }

  /// [stored] when it is one of [speeds], otherwise 1, so a value this
  /// build doesn't offer never reaches the player.
  static double sanitize(double? stored) =>
      stored != null && speeds.contains(stored) ? stored : 1;

  /// How far the skip buttons and a double tap jump: 30 seconds on a file
  /// of ten minutes or longer, 10 seconds on anything shorter or of unknown
  /// length.
  static Duration skipStep(Duration length) =>
      length >= const Duration(minutes: 10)
      ? const Duration(seconds: 30)
      : const Duration(seconds: 10);
}
