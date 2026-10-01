import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A stretch of time named in a search, like "march 2024" or "last week".
@immutable
class DateRange {
  const DateRange(this.start, this.end, this.label);

  /// Inclusive.
  final DateTime start;

  /// Exclusive.
  final DateTime end;

  /// How to say it back: "March 2024", "Last week".
  final String label;

  bool contains(DateTime moment) => !moment.isBefore(start) && moment.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Reads a date out of a search query, so "march 2024", "2023", "5 march",
/// "2024-03-05" or "last week" find the photos and files from then.
abstract final class DateQuery {
  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
    'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10,
    'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };

  static final _word = RegExp(r'[^\s,]+');
  static final _ordinal = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$');
  static final _year = RegExp(r'^(19|20)\d{2}$');
  static final _iso = RegExp(r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$');
  static final _slashed = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})$');

  static const _relative = {
    'today', 'yesterday', 'this week', 'last week', 'this month', 'last month',
    'this year', 'last year',
  };

  static List<String> _words(String query) => [
    for (final match in _word.allMatches(query)) match[0]!.toLowerCase(),
  ];

  /// Splits [query] into the date at its start or end and the words left
  /// over, so "invoice march 2024" looks for "invoice" within March 2024.
  /// A query that is only a date leaves no words. A date in the middle of
  /// the words isn't looked for.
  ///
  /// Only a date that can't be part of a name is taken off a longer query:
  /// one with a year, a written-out date, a relative phrase like "last
  /// week", or a month and a day. A lone month or a small number stays one
  /// of the words, so "report may" and "invoice 5" are searched as typed.
  ///
  /// The words left over are cut out of [query] as typed, keeping its case,
  /// spaces and commas, so "total 1,250" finds a receipt that says so. Names
  /// are matched against them as they are, and the database ignores case
  /// only for plain Latin letters.
  static ({DateRange? range, String rest}) split(String query, {DateTime? now}) {
    final tokens = _word.allMatches(query).toList();
    final words = [for (final token in tokens) token[0]!.toLowerCase()];
    if (words.isEmpty) return (range: null, rest: '');
    if (parse(words.join(' '), now: now) case final range?) {
      return (range: range, rest: '');
    }
    for (var n = 3; n >= 1; n--) {
      if (n >= words.length) continue;
      final tail = words.sublist(words.length - n);
      if (_peel(tail, now) case final range?) {
        final last = tokens[tokens.length - n - 1];
        return (range: range, rest: query.substring(tokens.first.start, last.end));
      }
      final head = words.sublist(0, n);
      if (_peel(head, now) case final range?) {
        return (range: range, rest: query.substring(tokens[n].start, tokens.last.end));
      }
    }
    return (range: null, rest: query.trim());
  }

  static DateRange? _peel(List<String> words, DateTime? now) =>
      _unambiguous(words) ? parse(words.join(' '), now: now) : null;

  static bool _unambiguous(List<String> words) =>
      words.any((w) => _year.hasMatch(w) || _iso.hasMatch(w) || _slashed.hasMatch(w)) ||
      _relative.contains(words.join(' ')) ||
      (words.any(_months.containsKey) && words.any(_ordinal.hasMatch));

  /// The range [query] names, or null if it isn't a date.
  static DateRange? parse(String query, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final words = _words(query);
    if (words.isEmpty) return null;
    final text = words.join(' ');

    switch (text) {
      case 'today':
        return _days(today, 1, 'Today');
      case 'yesterday':
        return _days(today.subtract(const Duration(days: 1)), 1, 'Yesterday');
      case 'this week':
        return _days(_weekStart(today), 7, 'This week');
      case 'last week':
        return _days(_weekStart(today).subtract(const Duration(days: 7)), 7, 'Last week');
      case 'this month':
        return _month(today.year, today.month, label: 'This month');
      case 'last month':
        return _month(today.year, today.month - 1, label: 'Last month');
      case 'this year':
        return _wholeYear(today.year, label: 'This year');
      case 'last year':
        return _wholeYear(today.year - 1, label: 'Last year');
    }

    if (words.length == 1) {
      final word = words.single;
      if (_year.hasMatch(word)) return _wholeYear(int.parse(word));
      if (_months[word] case final month?) {
        // A month alone means the latest one: "march" in May is this March.
        final year = month <= today.month ? today.year : today.year - 1;
        return _month(year, month);
      }
      if (_iso.firstMatch(word) case final m?) {
        final year = int.parse(m[1]!);
        final month = int.parse(m[2]!);
        if (month < 1 || month > 12) return null;
        return m[3] == null ? _month(year, month) : _date(year, month, int.parse(m[3]!));
      }
      if (_slashed.firstMatch(word) case final m?) {
        var day = int.parse(m[1]!);
        var month = int.parse(m[2]!);
        // Day first, the way most of the world writes it, unless that
        // can't be right.
        if (month > 12 && day <= 12) (day, month) = (month, day);
        return _date(int.parse(m[3]!), month, day);
      }
      return null;
    }

    // "march 2024", "2024 march", "march 5", "5 march", "march 5 2024",
    // "5 march 2024".
    int? month;
    int? day;
    int? year;
    for (final word in words) {
      if (_months[word] case final m? when month == null) {
        month = m;
      } else if (_year.hasMatch(word) && year == null) {
        year = int.parse(word);
      } else if (_ordinal.firstMatch(word) case final d? when day == null) {
        day = int.parse(d[1]!);
      } else {
        return null;
      }
    }
    if (month == null) return null;
    if (day == null) {
      return year == null ? null : _month(year, month);
    }
    year ??= (month < today.month || (month == today.month && day <= today.day))
        ? today.year
        : today.year - 1;
    return _date(year, month, day);
  }

  static DateTime _day(DateTime moment) => DateTime(moment.year, moment.month, moment.day);

  static DateTime _weekStart(DateTime day) =>
      day.subtract(Duration(days: day.weekday - DateTime.monday));

  static DateRange _days(DateTime start, int days, String label) =>
      DateRange(start, DateTime(start.year, start.month, start.day + days), label);

  static DateRange _month(int year, int month, {String? label}) {
    final start = DateTime(year, month);
    return DateRange(
      start,
      DateTime(start.year, start.month + 1),
      label ?? DateFormat.yMMMM().format(start),
    );
  }

  static DateRange _wholeYear(int year, {String? label}) =>
      DateRange(DateTime(year), DateTime(year + 1), label ?? '$year');

  static DateRange? _date(int year, int month, int day) {
    final start = DateTime(year, month, day);
    // DateTime rolls 31 February over into March; that isn't a date.
    if (start.month != month || start.day != day) return null;
    return _days(start, 1, DateFormat.yMMMMd().format(start));
  }
}
