import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/buyer/domain/geo.dart';
import 'package:warmad/features/buyer/domain/public_warung.dart';
import 'package:warmad/features/warung/domain/warung.dart';

void main() {
  group('encodeGeohash', () {
    test('matches the reference hashes the server is tested with', () {
      expect(encodeGeohash(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
      expect(encodeGeohash(-25.382708, -49.265506), '6gkzwgjzn');
    });

    test('gives nearby places a shared prefix', () {
      final a = encodeGeohash(-7.12890, 112.72430);
      final b = encodeGeohash(-7.12895, 112.72436);
      expect(a.substring(0, 7), b.substring(0, 7));
    });
  });

  group('nearbyGeohashCells', () {
    final cells = nearbyGeohashCells(-7.1289, 112.7243);

    test('returns the cell of the point and its neighbours', () {
      expect(cells.length, 9);
      expect(cells, contains(encodeGeohash(-7.1289, 112.7243, precision: 5)));
      expect(cells.every((cell) => cell.length == 5), isTrue);
    });

    test('covers places a few kilometres away in every direction', () {
      for (final (lat, lng) in [
        (-7.1289 + 0.03, 112.7243),
        (-7.1289 - 0.03, 112.7243),
        (-7.1289, 112.7243 + 0.03),
        (-7.1289, 112.7243 - 0.03),
        (-7.1289 + 0.03, 112.7243 - 0.03),
      ]) {
        expect(cells, contains(encodeGeohash(lat, lng, precision: 5)));
      }
    });
  });

  group('distanceMeters', () {
    test('is zero for the same point', () {
      expect(distanceMeters(-7.1289, 112.7243, -7.1289, 112.7243), 0);
    });

    test('is about 111 km per degree of latitude', () {
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('measures a short hop between two warungs', () {
      // Roughly 400 m apart near Jl. Telang Raya.
      final d = distanceMeters(-7.1289, 112.7243, -7.1262, 112.7268);
      expect(d, closeTo(407, 15));
    });

    test('is the same in both directions', () {
      expect(
        distanceMeters(-7.1289, 112.7243, -7.1351, 112.7198),
        closeTo(distanceMeters(-7.1351, 112.7198, -7.1289, 112.7243), 0.001),
      );
    });
  });

  group('formatDistance', () {
    test('uses metres below a kilometre, rounded to ten', () {
      expect(formatDistance(250), '250 m');
      expect(formatDistance(247), '250 m');
      expect(formatDistance(4), '0 m');
    });

    test('uses kilometres with one decimal above', () {
      expect(formatDistance(1000), '1 km');
      expect(formatDistance(1240), '1,2 km');
      expect(formatDistance(999), '1 km');
      expect(formatDistance(12640), '12,6 km');
    });
  });

  group('isOpenAt', () {
    DateTime at(int hour, int minute) => DateTime(2026, 9, 29, hour, minute);

    test('a 24 hour warung is always open', () {
      expect(isOpenAt(const OpeningHours.allDay(), at(3, 0)), isTrue);
    });

    test('daytime hours are open from opening until closing', () {
      const hours = OpeningHours.custom(open: '06:00', close: '21:00');
      expect(isOpenAt(hours, at(5, 59)), isFalse);
      expect(isOpenAt(hours, at(6, 0)), isTrue);
      expect(isOpenAt(hours, at(20, 59)), isTrue);
      expect(isOpenAt(hours, at(21, 0)), isFalse);
    });

    test('hours that run past midnight wrap around', () {
      const hours = OpeningHours.custom(open: '16:00', close: '02:00');
      expect(isOpenAt(hours, at(15, 59)), isFalse);
      expect(isOpenAt(hours, at(23, 30)), isTrue);
      expect(isOpenAt(hours, at(1, 59)), isTrue);
      expect(isOpenAt(hours, at(2, 0)), isFalse);
      expect(isOpenAt(hours, at(10, 0)), isFalse);
    });

    test('unreadable hours are not reported as closed', () {
      const hours = OpeningHours.custom(open: 'pagi', close: 'malam');
      expect(isOpenAt(hours, at(3, 0)), isTrue);
    });
  });

  test('Availability falls back to habis for an unknown value', () {
    expect(Availability.parse('tersedia'), Availability.tersedia);
    expect(Availability.parse('terbatas').label, 'Terbatas');
    expect(Availability.parse('lots'), Availability.habis);
    expect(Availability.parse(null), Availability.habis);
  });
}
