import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/cash/domain/cash_closing.dart';
import 'package:warmad/features/warung/domain/cash_state.dart';

void main() {
  // Figures from the "Tutup kas harian" design.
  const cash = CashState(
    seq: 7,
    openingBalance: 500000,
    salesCash: 979400,
    purchasesCash: 134400,
    expenses: 100000,
    salesCount: 47,
  );
  final now = DateTime(2026, 9, 29, 23, 41);

  CashClosing close(int counted, {CashState state = cash}) => CashClosing.of(
    state,
    counted: counted,
    closedByUid: 'u1',
    closedByName: 'Rudi',
    now: now,
  );

  group('CashClosing', () {
    test('matches the design example: Rp5.000 short', () {
      final closing = close(1240000);
      expect(closing.expected, 1245000);
      expect(closing.difference, -5000);
    });

    test('has no difference when the count matches the records', () {
      expect(close(1245000).difference, 0);
    });

    test('shows a surplus as a positive difference', () {
      expect(close(1250000).difference, 5000);
    });

    test('expected cash agrees with the live cash state', () {
      expect(close(0).expected, cash.expected);
    });

    test('counts kasbon paid back and prive', () {
      const state = CashState(
        seq: 1,
        openingBalance: 200000,
        salesCash: 300000,
        debtCollected: 50000,
        purchasesCash: 100000,
        expenses: 20000,
        prive: 75000,
      );
      final closing = close(355000, state: state);
      expect(closing.expected, 355000);
      expect(closing.difference, 0);
    });

    test('closes the period it was built from', () {
      expect(close(1240000).seq, 7);
    });

    test('a missing drawer is a full shortfall, not an error', () {
      expect(close(0).difference, -1245000);
    });

    test('refuses a negative count', () {
      expect(() => close(-1), throwsArgumentError);
    });

    test('writes figures that satisfy the Security Rules', () {
      final map = close(1240000).toMap();
      expect(
        map['expected'],
        map['openingBalance'] +
            map['salesCash'] +
            map['debtCollected'] -
            map['purchasesCash'] -
            map['expenses'] -
            map['prive'],
      );
      expect(map['difference'], map['counted'] - map['expected']);
      expect(map['closedByUid'], 'u1');
      expect(map['seq'], 7);
    });

    test('round trips through fromMap', () {
      final closing = close(1240000);
      final copy = CashClosing.fromMap(closing.toMap(), closedAt: now);
      expect(copy.expected, closing.expected);
      expect(copy.difference, closing.difference);
      expect(copy.closedByName, 'Rudi');
    });
  });

  test('the counted cash opens the next period', () {
    // After closing Rp5.000 short, the next period starts from what is
    // really in the drawer, so the shortfall is not carried forward.
    final closing = close(1240000);
    final next = CashState(
      seq: closing.seq + 1,
      openingBalance: closing.counted,
    );
    expect(next.expected, 1240000);
  });
}
