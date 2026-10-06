import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/pos/domain/cart.dart';
import 'package:warmad/features/pos/domain/sale.dart';
import 'package:warmad/features/products/domain/product.dart';

Product product(String name, int price) => Product(
  id: name,
  name: name,
  category: 'Sembako',
  sellPrice: price,
  lastBuyPrice: 0,
  stock: 10,
);

void main() {
  final indomie = product('Indomie Goreng', 3500);
  final aqua = product('Aqua 600ml', 4000);
  final kopi = product('Kopi Kapal Api sachet', 1500);

  // The cart from the "Kasir" design: Rp15.500 for 3 products, 6 pieces.
  final cart = const Cart().add(indomie, 2).add(aqua).add(kopi, 3);

  group('Cart', () {
    test('totals match the design example', () {
      expect(cart.total, 15500);
      expect(cart.lineCount, 3);
      expect(cart.itemCount, 6);
    });

    test('starts empty', () {
      expect(const Cart().isEmpty, isTrue);
      expect(const Cart().total, 0);
    });

    test('adding the same product raises its quantity', () {
      final twice = const Cart().add(indomie).add(indomie);
      expect(twice.lineCount, 1);
      expect(twice.qtyOf(indomie.id), 2);
      expect(twice.total, 7000);
    });

    test('removing the last piece removes the product', () {
      final afterOne = cart.removeOne(aqua);
      expect(afterOne.qtyOf(aqua.id), 0);
      expect(afterOne.lineCount, 2);
      expect(afterOne.total, 11500);
    });

    test('removing a product that is not there changes nothing', () {
      final same = const Cart().removeOne(indomie);
      expect(same.isEmpty, isTrue);
    });

    test('keeps the order products were added in', () {
      expect(cart.lines.map((line) => line.product.name), [
        'Indomie Goreng',
        'Aqua 600ml',
        'Kopi Kapal Api sachet',
      ]);
    });

    test('does not change the cart it was derived from', () {
      cart.add(aqua, 5);
      expect(cart.total, 15500);
    });

    test('stays exact for large amounts', () {
      final big = const Cart().add(product('Rokok slop', 325000), 999);
      expect(big.total, 324675000);
    });
  });

  group('changeFor', () {
    test('is paid minus total', () {
      expect(changeFor(total: 15500, paid: 20000), 4500);
      expect(changeFor(total: 15500, paid: 15500), 0);
    });

    test('is negative when the customer still owes money', () {
      expect(changeFor(total: 15500, paid: 10000), -5500);
    });
  });

  group('quickCashOptions', () {
    test('rounds the total up to common banknotes', () {
      expect(quickCashOptions(15500), [16000, 20000, 50000]);
      expect(quickCashOptions(7000), [8000, 10000, 20000]);
    });

    test('never offers the exact total', () {
      expect(quickCashOptions(20000), [50000, 100000]);
      expect(quickCashOptions(20000), isNot(contains(20000)));
    });

    test('is empty for an empty cart', () {
      expect(quickCashOptions(0), isEmpty);
    });

    test('still offers the next hundred thousand above it', () {
      expect(quickCashOptions(134400), [135000, 136000, 140000]);
    });
  });

  group('Sale.fromCart', () {
    final now = DateTime(2026, 9, 29, 14, 32);
    Sale build({int paid = 20000, Cart? from}) => Sale.fromCart(
      id: 's1',
      cart: from ?? cart,
      paid: paid,
      cashierUid: 'u1',
      cashierName: 'Rudi',
      now: now,
    );

    test('copies totals and computes change', () {
      final sale = build();
      expect(sale.total, 15500);
      expect(sale.paid, 20000);
      expect(sale.change, 4500);
      expect(sale.itemCount, 6);
    });

    test('snapshots name and price of every item', () {
      final map = build().toMap();
      expect(map['items'], [
        {
          'productId': 'Indomie Goreng',
          'name': 'Indomie Goreng',
          'qty': 2,
          'price': 3500,
          'subtotal': 7000,
        },
        {
          'productId': 'Aqua 600ml',
          'name': 'Aqua 600ml',
          'qty': 1,
          'price': 4000,
          'subtotal': 4000,
        },
        {
          'productId': 'Kopi Kapal Api sachet',
          'name': 'Kopi Kapal Api sachet',
          'qty': 3,
          'price': 1500,
          'subtotal': 4500,
        },
      ]);
    });

    test('writes fields the Security Rules check', () {
      final map = build().toMap();
      expect(map['total'], 15500);
      expect(map['change'], map['paid'] - map['total']);
      expect(map['payment'], 'cash');
      expect(map['cashierUid'], 'u1');
      expect(map['dayKey'], '2026-09-29');
    });

    test('item subtotals add up to the total', () {
      final map = build().toMap();
      final sum = (map['items'] as List).fold<int>(
        0,
        (sum, item) => sum + (item as Map)['subtotal'] as int,
      );
      expect(sum, map['total']);
    });

    test('accepts exact payment', () {
      expect(build(paid: 15500).change, 0);
    });

    test('refuses an underpaid or empty sale', () {
      expect(() => build(paid: 15499), throwsArgumentError);
      expect(() => build(from: const Cart()), throwsArgumentError);
    });

    test('round trips through fromMap', () {
      final sale = build();
      final copy = Sale.fromMap('s1', sale.toMap(), occurredAt: now);
      expect(copy.total, sale.total);
      expect(copy.change, sale.change);
      expect(copy.items.length, 3);
      expect(copy.items.first.subtotal, 7000);
    });
  });
}
