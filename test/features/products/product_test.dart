import 'package:flutter_test/flutter_test.dart';
import 'package:warmad/features/products/data/catalog_repository.dart';
import 'package:warmad/features/products/domain/product.dart';

Product product({
  String name = 'Indomie Goreng',
  int stock = 18,
  int? manualRop,
  int? computedRop,
  int? manualOrderQty,
  int? computedOrderQty,
  PackUnit? pack,
  String? barcode,
}) => Product(
  id: name,
  name: name,
  category: 'Sembako',
  sellPrice: 3500,
  lastBuyPrice: 2900,
  stock: stock,
  manualRop: manualRop,
  computedRop: computedRop,
  manualOrderQty: manualOrderQty,
  computedOrderQty: computedOrderQty,
  pack: pack,
  barcode: barcode,
);

void main() {
  group('stock status', () {
    test('is habis at zero and below', () {
      expect(product(stock: 0).status, StockStatus.habis);
      expect(product(stock: -3).status, StockStatus.habis);
    });

    test('is hampir habis at or below the reorder point', () {
      expect(product(stock: 24, manualRop: 24).status, StockStatus.hampirHabis);
      expect(product(stock: 1, manualRop: 24).status, StockStatus.hampirHabis);
    });

    test('is aman above the reorder point', () {
      expect(product(stock: 25, manualRop: 24).status, StockStatus.aman);
    });

    test('is aman at any positive stock when no reorder point is set', () {
      expect(product(stock: 1).status, StockStatus.aman);
    });
  });

  group('reorder figures', () {
    test('calculated values win over what the owner typed', () {
      final p = product(manualRop: 10, computedRop: 24);
      expect(p.reorderPoint, 24);
    });

    test('fall back to the manual value, then to zero', () {
      expect(product(manualRop: 10).reorderPoint, 10);
      expect(product().reorderPoint, 0);
    });

    test('suggested order falls back to one pack', () {
      const dus = PackUnit(name: 'dus', size: 40);
      expect(product(computedOrderQty: 80, pack: dus).suggestedOrderQty, 80);
      expect(product(manualOrderQty: 60, pack: dus).suggestedOrderQty, 60);
      expect(product(pack: dus).suggestedOrderQty, 40);
      expect(product().suggestedOrderQty, isNull);
    });
  });

  test('profit per unit is sell price minus buy price', () {
    expect(product().profitPerUnit, 600);
  });

  group('matches', () {
    final indomie = product(barcode: '0899123456789');

    test('an empty search matches everything', () {
      expect(indomie.matches(''), isTrue);
      expect(indomie.matches('   '), isTrue);
    });

    test('ignores case and needs every word', () {
      expect(indomie.matches('indo'), isTrue);
      expect(indomie.matches('GORENG indomie'), isTrue);
      expect(indomie.matches('indomie soto'), isFalse);
    });

    test('matches a scanned barcode exactly', () {
      expect(indomie.matches('0899123456789'), isTrue);
      expect(indomie.matches('089912345678'), isFalse);
    });
  });

  test('compareByUrgency puts empty, then low, then lowest stock first', () {
    final list = [
      product(name: 'Kopi', stock: 64, manualRop: 30),
      product(name: 'Aqua', stock: 9, manualRop: 20),
      product(name: 'Beras', stock: 14, manualRop: 6),
      product(name: 'Minyak', stock: 0, manualRop: 24),
      product(name: 'Indomie', stock: 18, manualRop: 24),
    ]..sort(compareByUrgency);
    expect(list.map((p) => p.name), [
      'Minyak',
      'Aqua',
      'Indomie',
      'Beras',
      'Kopi',
    ]);
  });

  group('Product.fromMap', () {
    test('reads stored and calculated figures', () {
      final p = Product.fromMap('p1', {
        'name': 'Aqua 600ml',
        'category': 'Minuman',
        'sellPrice': 4000,
        'lastBuyPrice': 2800,
        'stock': 9,
        'pack': {'name': 'dus', 'size': 24},
        'manualRop': 12,
        'computed': {'rop': 20, 'safetyStock': 8, 'eoq': 48},
        'active': true,
      });
      expect(p.reorderPoint, 20);
      expect(p.computedSafetyStock, 8);
      expect(p.suggestedOrderQty, 48);
      expect(p.pack?.size, 24);
    });

    test('tolerates missing optional fields', () {
      final p = Product.fromMap('p2', {'name': 'Kerupuk', 'sellPrice': 1000});
      expect(p.stock, 0);
      expect(p.pack, isNull);
      expect(p.active, isTrue);
      expect(p.category, 'Lainnya');
    });

    test('ignores a pack without a usable size', () {
      expect(PackUnit.fromMap({'name': 'dus', 'size': 0}), isNull);
      expect(PackUnit.fromMap({'name': '', 'size': 12}), isNull);
      expect(PackUnit.fromMap(null), isNull);
    });
  });

  test('searchWords splits like the catalog index', () {
    expect(searchWords('Kopi  Kapal-Api 165g'), [
      'kopi',
      'kapal',
      'api',
      '165g',
    ]);
    expect(searchWords(' ! '), isEmpty);
  });
}
