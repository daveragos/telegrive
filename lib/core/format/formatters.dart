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
