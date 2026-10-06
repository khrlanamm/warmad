import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/core/date_labels.dart';
import 'package:warmad/core/dates.dart';

void main() {
  group('formatRelative', () {
    final now = DateTime(2026, 9, 29, 14, 32);

    test('uses minutes, then hours', () {
      expect(formatRelative(now, now), 'Baru saja');
      expect(
        formatRelative(now.subtract(const Duration(minutes: 10)), now),
        '10 menit lalu',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 3)), now),
        '3 jam lalu',
      );
    });
  });

  group('dayGroupOf', () {
    final now = DateTime(2026, 9, 29, 0, 30);

    test('groups by calendar day, not by hours elapsed', () {
      expect(dayGroupOf(DateTime(2026, 9, 29, 0, 5), now), 'Hari ini');
      // Only an hour ago, but on the previous day.
      expect(dayGroupOf(DateTime(2026, 9, 28, 23, 41), now), 'Kemarin');
      expect(dayGroupOf(DateTime(2026, 9, 27, 7), now), 'Sebelumnya');
    });
  });

  test('dayKeyOf pads month and day', () {
    expect(dayKeyOf(DateTime(2026, 9, 29, 14, 32)), '2026-09-29');
    expect(dayKeyOf(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('dayKeyOf uses the local calendar day, not the hour', () {
    expect(dayKeyOf(DateTime(2026, 10, 6, 0, 0)), '2026-10-06');
    expect(dayKeyOf(DateTime(2026, 10, 6, 23, 59, 59)), '2026-10-06');
  });

  test('day keys sort in date order as plain text', () {
    final keys = [
      dayKeyOf(DateTime(2026, 10, 1)),
      dayKeyOf(DateTime(2026, 9, 30)),
      dayKeyOf(DateTime(2025, 12, 31)),
    ]..sort();
    expect(keys, ['2025-12-31', '2026-09-30', '2026-10-01']);
  });

  test('formatClock uses a dot and two digits', () {
    expect(formatClock(DateTime(2026, 9, 29, 14, 32)), '14.32');
    expect(formatClock(DateTime(2026, 9, 29, 7, 5)), '07.05');
  });
}
