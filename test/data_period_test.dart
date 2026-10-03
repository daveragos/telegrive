import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/network/domain/data_period.dart';

void main() {
  group('DataPeriod', () {
    test('the day before renewal still counts in the month before', () {
      final start = DataPeriod.startFor(DateTime(2026, 9, 2, 10), 3);
      expect(start, DateTime(2026, 8, 3));
      expect(DataPeriod.endFor(start, 3), DateTime(2026, 9, 3));
    });

    test('a new period starts at midnight on the renewal day', () {
      final start = DataPeriod.startFor(DateTime(2026, 9, 3), 3);
      expect(start, DateTime(2026, 9, 3));
      expect(DataPeriod.endFor(start, 3), DateTime(2026, 10, 3));
    });

    test('renewing on the 28th works across February', () {
      final inFebruary = DataPeriod.startFor(DateTime(2027, 2, 27, 23), 28);
      expect(inFebruary, DateTime(2027, 1, 28));
      expect(DataPeriod.endFor(inFebruary, 28), DateTime(2027, 2, 28));

      final inMarch = DataPeriod.startFor(DateTime(2027, 3, 1), 28);
      expect(inMarch, DateTime(2027, 2, 28));
      expect(DataPeriod.endFor(inMarch, 28), DateTime(2027, 3, 28));
    });

    test('a period runs from December into January', () {
      final start = DataPeriod.startFor(DateTime(2027, 1, 4, 8), 5);
      expect(start, DateTime(2026, 12, 5));
      expect(DataPeriod.endFor(start, 5), DateTime(2027, 1, 5));

      final december = DataPeriod.startFor(DateTime(2026, 12, 20), 5);
      expect(DataPeriod.endFor(december, 5), DateTime(2027, 1, 5));
    });

    test('a renewal day past the 28th is taken as the 28th', () {
      expect(DataPeriod.startFor(DateTime(2026, 9, 30), 31), DateTime(2026, 9, 28));
      expect(DataPeriod.endFor(DateTime(2026, 9, 28), 31), DateTime(2026, 10, 28));
    });

    test('spent is the carry plus what the counter moved past its baseline', () {
      expect(DataPeriod.spent(counter: 900, baseline: 600, carry: 0), 300);
      expect(DataPeriod.spent(counter: 900, baseline: 600, carry: 50), 350);
      expect(DataPeriod.spent(counter: 200, baseline: 0, carry: 300), 500);
      // A counter below its baseline adds nothing.
      expect(DataPeriod.spent(counter: 100, baseline: 600, carry: 40), 40);
    });
  });
}
