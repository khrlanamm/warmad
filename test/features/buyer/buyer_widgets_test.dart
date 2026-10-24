import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/buyer/domain/public_warung.dart';
import 'package:warmad/features/buyer/ui/buyer_widgets.dart';
import 'package:warmad/features/warung/domain/warung.dart';

void main() {
  PublicWarung warung(String id, double distance) => PublicWarung(
    id: id,
    name: 'Warung $id',
    address: '',
    lat: 0,
    lng: 0,
    hours: const OpeningHours.allDay(),
    distance: distance,
  );

  group('describeNearby', () {
    final warungs = [warung('a', 350), warung('b', 1240)];

    test('counts the warungs and gives the nearest distance', () {
      expect(
        describeNearby(warungs, 5, located: true),
        '2 warung dalam 5\u00a0km · terdekat 350\u00a0m',
      );
    });

    test('says when only open warungs are counted', () {
      expect(
        describeNearby(warungs, 3, located: true, openOnly: true),
        '2 warung buka dalam 3\u00a0km · terdekat 350\u00a0m',
      );
    });

    test('names the fallback place when the position is unknown', () {
      expect(
        describeNearby(warungs, 5, located: false),
        '2 warung dalam 5\u00a0km dari Telang, Kamal',
      );
    });
  });
}
