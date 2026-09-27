import 'package:intl/intl.dart';

/// Human-readable sizes, dates and durations, in one place so every screen
/// speaks the same units.
abstract final class Formatters {
  static const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  /// `1536` → `1.5 KB`. Binary multiples, the way file managers show them.
  static String bytes(int value, {int decimals = 1}) {
    if (value <= 0) return '0 B';
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < _units.length - 1) {
      size /= 1024;
      unit++;
    }
    final digits = unit == 0 || size >= 100 ? 0 : decimals;
    return '${size.toStringAsFixed(digits)} ${_units[unit]}';
  }

  /// Transfer speed, e.g. `2.4 MB/s`.
  static String speed(double bytesPerSecond) =>
      '${bytes(bytesPerSecond.round())}/s';

  /// `75` → `1 min 15 s`; short enough for a progress row.
  static String eta(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s left';
    final minutes = duration.inMinutes;
    if (minutes < 60) return '${minutes}m ${seconds % 60}s left';
    return '${duration.inHours}h ${minutes % 60}m left';
  }

  /// `72 s` → `1:12`, `3723 s` → `1:02:03`: time left on a wait that counts
  /// down. A part-second counts as a whole one, so the clock never reads
  /// 0:00 while there is still time to go.
  static String countdown(Duration duration) {
    final total = duration.isNegative
        ? 0
        : (duration.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    String two(int value) => value.toString().padLeft(2, '0');
    final hours = total ~/ 3600;
    final minutes = total % 3600 ~/ 60;
    final seconds = total % 60;
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '$minutes:${two(seconds)}';
  }

  /// `37 s` → `37 seconds`, `7200 s` → `2 hours`: a length of time rounded
  /// the way a person would say it.
  static String inWords(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 90) return count(seconds, 'second');
    if (seconds < 5400) return count((seconds / 60).round(), 'minute');
    return count((seconds / 3600).round(), 'hour');
  }

  /// Today → time, this year → day and month, otherwise the full date.
  static String date(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final sameDay =
        value.year == reference.year &&
        value.month == reference.month &&
        value.day == reference.day;
    if (sameDay) return DateFormat.jm().format(value);
    if (value.year == reference.year) return DateFormat.MMMd().format(value);
    return DateFormat.yMMMd().format(value);
  }

  static String fullDate(DateTime value) =>
      DateFormat.yMMMd().add_jm().format(value);

  /// `12345` → `12,345`.
  static String number(int value) => NumberFormat.decimalPattern().format(value);

  static String count(int value, String singular, [String? plural]) {
    final word = value == 1 ? singular : (plural ?? '${singular}s');
    return '${NumberFormat.decimalPattern().format(value)} $word';
  }
}
