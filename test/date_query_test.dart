import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/format/date_query.dart';

void main() {
  // A Thursday.
  final now = DateTime(2026, 9, 24, 15, 30);
  DateRange? parse(String q) => DateQuery.parse(q, now: now);

  void expectRange(String query, DateTime start, DateTime end, [String? label]) {
    final range = parse(query);
    expect(range, isNotNull, reason: query);
    expect(range!.start, start, reason: query);
    expect(range.end, end, reason: query);
    if (label != null) expect(range.label, label, reason: query);
  }

  test('relative words', () {
    expectRange('today', DateTime(2026, 9, 24), DateTime(2026, 9, 25), 'Today');
    expectRange('Yesterday', DateTime(2026, 9, 23), DateTime(2026, 9, 24));
    expectRange('this week', DateTime(2026, 9, 21), DateTime(2026, 9, 28));
    expectRange('last  week', DateTime(2026, 9, 14), DateTime(2026, 9, 21));
    expectRange('last month', DateTime(2026, 8), DateTime(2026, 9));
    expectRange('last year', DateTime(2025), DateTime(2026));
  });

  test('years and months', () {
    expectRange('2023', DateTime(2023), DateTime(2024), '2023');
    expectRange('march 2024', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
    expectRange('2024 Mar', DateTime(2024, 3), DateTime(2024, 4));
    // A month alone is the latest one.
    expectRange('march', DateTime(2026, 3), DateTime(2026, 4));
    expectRange('december', DateTime(2025, 12), DateTime(2026));
    expectRange('2024-03', DateTime(2024, 3), DateTime(2024, 4));
  });

  test('days', () {
    expectRange('5 march 2024', DateTime(2024, 3, 5), DateTime(2024, 3, 6), 'March 5, 2024');
    expectRange('March 5th, 2024', DateTime(2024, 3, 5), DateTime(2024, 3, 6));
    expectRange('sept 1', DateTime(2026, 9, 1), DateTime(2026, 9, 2));
    expectRange('oct 1', DateTime(2025, 10, 1), DateTime(2025, 10, 2));
    expectRange('2024-03-05', DateTime(2024, 3, 5), DateTime(2024, 3, 6));
    expectRange('05/03/2024', DateTime(2024, 3, 5), DateTime(2024, 3, 6));
    expectRange('03/25/2024', DateTime(2024, 3, 25), DateTime(2024, 3, 26));
  });

  test('anything else is not a date', () {
    for (final q in ['', 'receipt', 'march madness', '31 feb 2024', '12345', 'may the fourth', '2024-13']) {
      expect(parse(q), isNull, reason: q);
    }
  });

  group('split', () {
    ({DateRange? range, String rest}) split(String q) => DateQuery.split(q, now: now);

    void expectSplit(String query, String rest, DateTime start, DateTime end, [String? label]) {
      final result = split(query);
      expect(result.rest, rest, reason: query);
      expect(result.range, isNotNull, reason: query);
      expect(result.range!.start, start, reason: query);
      expect(result.range!.end, end, reason: query);
      if (label != null) expect(result.range!.label, label, reason: query);
    }

    test('a date at the end leaves the words before it', () {
      expectSplit('invoice march 2024', 'invoice', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
      expectSplit('screenshot last year', 'screenshot', DateTime(2025), DateTime(2026), 'Last year');
      expectSplit('tax 2023', 'tax', DateTime(2023), DateTime(2024), '2023');
    });

    test('a date at the start leaves the words after it', () {
      expectSplit('2024-03 receipts', 'receipts', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
      expectSplit('march 5 receipts', 'receipts', DateTime(2026, 3, 5), DateTime(2026, 3, 6), 'March 5, 2026');
    });

    test('a query that is only a date leaves no words', () {
      expectSplit('5 march', '', DateTime(2026, 3, 5), DateTime(2026, 3, 6));
    });

    test('a lone month or a small number stays a word', () {
      for (final q in ['report may', 'invoice 5']) {
        expect(split(q).range, isNull, reason: q);
        expect(split(q).rest, q, reason: q);
      }
    });

    test('the words keep the case they were typed in', () {
      expectSplit('Invoice MARCH 2024', 'Invoice', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
      expect(split('Über Report').rest, 'Über Report');
    });

    test('the words keep the commas they were typed with', () {
      expect(split('total 1,250'), (range: null, rest: 'total 1,250'));
      expectSplit('Smith, John march 2024', 'Smith, John', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
      expectSplit('march 2024, Smith, John', 'Smith, John', DateTime(2024, 3), DateTime(2024, 4), 'March 2024');
    });

    test('an empty query is neither', () {
      expect(split(''), (range: null, rest: ''));
    });
  });
}
