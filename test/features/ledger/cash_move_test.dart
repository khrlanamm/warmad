import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/ledger/domain/cash_move.dart';
import 'package:warmad/features/pos/domain/cart.dart';
import 'package:warmad/features/pos/domain/sale.dart';
import 'package:warmad/features/products/domain/product.dart';

void main() {
  final now = DateTime(2026, 9, 29, 14, 32);

  group('countsInOpenPeriod', () {
    final openedAt = DateTime(2026, 9, 28, 23, 30);

    test('is true from the moment the period opened', () {
      expect(countsInOpenPeriod(openedAt, openedAt), isTrue);
      expect(countsInOpenPeriod(now, openedAt), isTrue);
    });

    test('is false for an entry dated before the period opened', () {
      expect(countsInOpenPeriod(DateTime(2026, 9, 28, 12), openedAt), isFalse);
      expect(countsInOpenPeriod(DateTime(2026, 9, 20), openedAt), isFalse);
    });

    test('is true when the opening time is unknown', () {
      expect(countsInOpenPeriod(DateTime(2020), null), isTrue);
    });
  });

  group('occurredAtFor', () {
    test('uses the current time for today', () {
      expect(occurredAtFor(DateTime(2026, 9, 29), now), now);
    });

    test('uses noon for another day', () {
      expect(
        occurredAtFor(DateTime(2026, 9, 27), now),
        DateTime(2026, 9, 27, 12),
      );
    });
  });

  group('CashMoveKind.counter', () {
    test('books stock bought and supplier debt paid as purchases', () {
      expect(CashMoveKind.purchase.counter, 'purchasesCash');
      expect(CashMoveKind.supplierPayment.counter, 'purchasesCash');
    });

    test('keeps prive apart from business expenses', () {
      expect(CashMoveKind.expense.counter, 'expenses');
      expect(CashMoveKind.prive.counter, 'prive');
      expect(CashMoveKind.prive.counter, isNot(CashMoveKind.expense.counter));
    });

    test('books kasbon paid back as cash in, the rest as cash out', () {
      expect(CashMoveKind.debtPayment.counter, 'debtCollected');
      expect(CashMoveKind.debtPayment.isCashIn, isTrue);
      for (final kind in CashMoveKind.values) {
        if (kind != CashMoveKind.debtPayment) expect(kind.isCashIn, isFalse);
      }
    });

    test('books refunds in their own counter', () {
      expect(CashMoveKind.refund.counter, 'refunds');
    });
  });

  group('CashMove.toMap', () {
    CashMove purchase({String paidFrom = 'cash', bool cash = true}) => CashMove(
      id: 'm1',
      kind: CashMoveKind.purchase,
      amount: 134400,
      cash: cash,
      occurredAt: now,
      createdByUid: 'u1',
      createdByName: 'Rudi',
      productId: 'aqua',
      productName: 'Aqua 600ml',
      qty: 48,
      paidFrom: paidFrom,
      supplierId: paidFrom == 'debt' ? 'sumber' : null,
    );

    test('writes the purchase from the "Barang masuk" design', () {
      // 48 pcs at Rp2.800 is Rp134.400.
      expect(48 * 2800, 134400);
      expect(purchase().toMap(), {
        'kind': 'purchase',
        'amount': 134400,
        'cash': true,
        'createdByUid': 'u1',
        'createdByName': 'Rudi',
        'productId': 'aqua',
        'productName': 'Aqua 600ml',
        'qty': 48,
        'paidFrom': 'cash',
      });
    });

    test('marks goods bought on debt as moving no cash', () {
      final move = purchase(paidFrom: 'debt', cash: false);
      expect(move.onDebt, isTrue);
      expect(move.toMap()['cash'], isFalse);
      expect(move.toMap()['supplierId'], 'sumber');
    });

    test('leaves out fields of other kinds and empty notes', () {
      final map = CashMove(
        id: 'm2',
        kind: CashMoveKind.prive,
        amount: 50000,
        cash: true,
        occurredAt: now,
        createdByUid: 'u1',
        createdByName: 'Pak Ahmad',
        category: 'Pribadi',
        note: '',
      ).toMap();
      expect(map.keys, [
        'kind',
        'amount',
        'cash',
        'createdByUid',
        'createdByName',
        'category',
      ]);
    });

    test('round trips through fromMap', () {
      final copy = CashMove.fromMap(
        'm1',
        purchase(paidFrom: 'debt', cash: false).toMap(),
        occurredAt: now,
      );
      expect(copy.kind, CashMoveKind.purchase);
      expect(copy.amount, 134400);
      expect(copy.qty, 48);
      expect(copy.onDebt, isTrue);
      expect(copy.cash, isFalse);
    });
  });

  group('kasbon sale', () {
    const aqua = Product(
      id: 'aqua',
      name: 'Aqua 600ml',
      category: 'Minuman',
      sellPrice: 4000,
      lastBuyPrice: 2800,
      stock: 10,
    );
    final cart = const Cart().add(aqua, 3);

    Sale credit() => Sale.fromCart(
      id: 's1',
      cart: cart,
      paid: 0,
      cashierUid: 'u1',
      cashierName: 'Rudi',
      now: now,
      customerId: 'bu-siti',
      customerName: 'Bu Siti',
    );

    test('takes no payment and gives no change', () {
      final sale = credit();
      expect(sale.onCredit, isTrue);
      expect(sale.total, 12000);
      expect(sale.paid, 0);
      expect(sale.change, 0);
    });

    test('writes fields the Security Rules check', () {
      final map = credit().toMap();
      expect(map['payment'], 'credit');
      expect(map['paid'], 0);
      expect(map['change'], 0);
      expect(map['customerId'], 'bu-siti');
    });

    test('a cash sale carries no customer', () {
      final map = Sale.fromCart(
        id: 's2',
        cart: cart,
        paid: 20000,
        cashierUid: 'u1',
        cashierName: 'Rudi',
        now: now,
      ).toMap();
      expect(map['payment'], 'cash');
      expect(map.containsKey('customerId'), isFalse);
      expect(map['change'], 8000);
    });

    test('still refuses an underpaid cash sale', () {
      expect(
        () => Sale.fromCart(
          id: 's3',
          cart: cart,
          paid: 0,
          cashierUid: 'u1',
          cashierName: 'Rudi',
          now: now,
        ),
        throwsArgumentError,
      );
    });

    test('reads voided and kasbon back from a stored sale', () {
      final stored = {...credit().toMap(), 'voided': true};
      final sale = Sale.fromMap('s1', stored, occurredAt: now);
      expect(sale.onCredit, isTrue);
      expect(sale.customerName, 'Bu Siti');
      expect(sale.voided, isTrue);
    });
  });
}
