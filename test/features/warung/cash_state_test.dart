import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/warung/domain/cash_state.dart';

void main() {
  // Figures from the "Tutup kas harian" design.
  const cash = CashState(
    seq: 1,
    openingBalance: 500000,
    salesCash: 979400,
    purchasesCash: 134400,
    expenses: 100000,
  );

  group('CashState', () {
    test('expected cash is opening plus cash in minus cash out', () {
      expect(cash.expected, 1245000);
    });

    test('customer credit paid back adds to cash', () {
      const withDebt = CashState(
        seq: 1,
        openingBalance: 100000,
        salesCash: 50000,
        debtCollected: 25000,
      );
      expect(withDebt.cashIn, 75000);
      expect(withDebt.expected, 175000);
    });

    test('prive leaves the drawer like any other cash out', () {
      const withPrive = CashState(
        seq: 1,
        openingBalance: 500000,
        expenses: 25000,
        prive: 50000,
      );
      expect(withPrive.cashOut, 75000);
      expect(withPrive.expected, 425000);
    });

    test('expected cash can go below zero without clamping', () {
      const short = CashState(seq: 1, openingBalance: 0, expenses: 10000);
      expect(short.expected, -10000);
    });

    test('difference is counted minus expected', () {
      expect(cash.differenceFor(1240000), -5000);
      expect(cash.differenceFor(1245000), 0);
      expect(cash.differenceFor(1250000), 5000);
    });

    test('fromMap treats missing counters as zero', () {
      final parsed = CashState.fromMap({'seq': 3, 'openingBalance': 200000});
      expect(parsed.seq, 3);
      expect(parsed.expected, 200000);
      expect(parsed.salesCount, 0);
    });
  });
}
