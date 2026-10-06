import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/products/domain/inventory.dart';

void main() {
  // The same vectors the Cloud Functions implementation is tested against.
  final vectors = (jsonDecode(
    File('functions/test/vectors/inventory.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  InventoryInput inputOf(Map<String, dynamic> vector) {
    final input = vector['input'] as Map<String, dynamic>;
    return InventoryInput(
      dailyQty: (input['dailyQty'] as List).cast<int>(),
      leadTimeDays: input['leadTimeDays'] as int,
      packSize: input['packSize'] as int,
      buyPrice: input['buyPrice'] as int,
      orderCost: input['orderCost'] as int,
      holdingRatePct: input['holdingRatePct'] as int,
    );
  }

  group('computeInventory matches the shared vectors', () {
    for (final vector in vectors) {
      test(vector['name'] as String, () {
        final figures = computeInventory(inputOf(vector));
        final expected = vector['expected'] as Map<String, dynamic>?;
        if (expected == null) {
          expect(figures, isNull);
          return;
        }
        expect(figures, isNotNull);
        expect(figures!.days, expected['days']);
        expect(figures.avgDailyTenths, expected['avgDailyTenths']);
        expect(figures.maxDaily, expected['maxDaily']);
        expect(figures.safetyStock, expected['safetyStock']);
        expect(figures.rop, expected['rop']);
        expect(figures.eoq, expected['eoq']);
      });
    }
  });

  test('reproduces the figures in the product detail design', () {
    // 12 sold per day on average, peak of 24, one day of lead time.
    final figures = computeInventory(inputOf(vectors.first))!;
    expect(figures.avgDailyTenths, 120);
    expect(figures.safetyStock, 12);
    expect(figures.rop, 24);
    expect(figures.eoq, 80); // 2 dus of 40
  });

  test('needs at least two weeks of history', () {
    expect(minHistoryDays, 14);
    expect(vectors.length, greaterThanOrEqualTo(10));
  });
}
