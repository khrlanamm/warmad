import '../../products/domain/product.dart';

class CartLine {
  const CartLine({required this.product, required this.qty});

  final Product product;
  final int qty;

  int get subtotal => product.sellPrice * qty;
}

/// What the cashier has rung up so far. Immutable: every change returns a
/// new cart.
class Cart {
  const Cart([this._lines = const {}]);

  // Keyed by product ID. Keeps the order in which products were added.
  final Map<String, CartLine> _lines;

  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;

  /// Number of different products.
  int get lineCount => _lines.length;

  /// Number of pieces across all products.
  int get itemCount => _lines.values.fold(0, (sum, line) => sum + line.qty);

  int get total => _lines.values.fold(0, (sum, line) => sum + line.subtotal);

  int qtyOf(String productId) => _lines[productId]?.qty ?? 0;

  Cart add(Product product, [int qty = 1]) =>
      setQty(product, qtyOf(product.id) + qty);

  Cart removeOne(Product product) => setQty(product, qtyOf(product.id) - 1);

  /// Sets the quantity of [product]. Zero or less removes it.
  Cart setQty(Product product, int qty) {
    final next = Map<String, CartLine>.of(_lines);
    if (qty <= 0) {
      next.remove(product.id);
    } else {
      next[product.id] = CartLine(product: product, qty: qty);
    }
    return Cart(next);
  }
}

/// Change to hand back. Negative when the customer has not paid enough.
int changeFor({required int total, required int paid}) => paid - total;

/// Likely amounts a customer hands over for [total], smallest first: the
/// total rounded up to common banknotes. Lets the cashier tap instead of type.
List<int> quickCashOptions(int total, {int count = 3}) {
  if (total <= 0) return const [];
  const notes = [1000, 2000, 5000, 10000, 20000, 50000, 100000];
  final options = <int>{
    for (final note in notes) ((total + note - 1) ~/ note) * note,
  }..remove(total);
  return (options.toList()..sort()).take(count).toList();
}
