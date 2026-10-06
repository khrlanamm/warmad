import '../../../core/dates.dart';
import 'cart.dart';

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.price,
  });

  factory SaleItem.fromMap(Map<String, dynamic> data) => SaleItem(
    productId: data['productId'] as String? ?? '',
    name: data['name'] as String? ?? '',
    qty: (data['qty'] as num?)?.toInt() ?? 0,
    price: (data['price'] as num?)?.toInt() ?? 0,
  );

  final String productId;

  /// Name and price are copied at the time of sale, so history stays true
  /// when the product is later renamed or repriced.
  final String name;
  final int qty;
  final int price;

  int get subtotal => price * qty;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'name': name,
    'qty': qty,
    'price': price,
    'subtotal': subtotal,
  };
}

/// One sale (`warungs/{id}/sales/{id}`). All amounts are whole Rupiah.
class Sale {
  const Sale({
    required this.id,
    required this.items,
    required this.total,
    required this.paid,
    required this.cashierUid,
    required this.cashierName,
    required this.occurredAt,
    this.customerId,
    this.customerName,
    this.voided = false,
  });

  /// Builds the sale for what is in [cart].
  ///
  /// Pass [customerId] and [customerName] for a kasbon sale: nothing is paid
  /// now and the total is added to what that customer owes.
  ///
  /// Throws [ArgumentError] when the cart is empty or, for a cash sale, when
  /// [paid] does not cover the total, so an incomplete sale is never saved.
  factory Sale.fromCart({
    required String id,
    required Cart cart,
    required int paid,
    required String cashierUid,
    required String cashierName,
    required DateTime now,
    String? customerId,
    String? customerName,
  }) {
    final onCredit = customerId != null;
    if (cart.isEmpty) throw ArgumentError('The cart is empty.');
    if (!onCredit && paid < cart.total) {
      throw ArgumentError('Paid less than the total.');
    }
    return Sale(
      id: id,
      items: [
        for (final line in cart.lines)
          SaleItem(
            productId: line.product.id,
            name: line.product.name,
            qty: line.qty,
            price: line.product.sellPrice,
          ),
      ],
      total: cart.total,
      paid: onCredit ? 0 : paid,
      cashierUid: cashierUid,
      cashierName: cashierName,
      occurredAt: now,
      customerId: customerId,
      customerName: customerName,
    );
  }

  factory Sale.fromMap(
    String id,
    Map<String, dynamic> data, {
    required DateTime occurredAt,
  }) => Sale(
    id: id,
    items: [
      for (final item in data['items'] as List? ?? const [])
        SaleItem.fromMap(Map<String, dynamic>.from(item as Map)),
    ],
    total: (data['total'] as num?)?.toInt() ?? 0,
    paid: (data['paid'] as num?)?.toInt() ?? 0,
    cashierUid: data['cashierUid'] as String? ?? '',
    cashierName: data['cashierName'] as String? ?? '',
    occurredAt: occurredAt,
    customerId: data['payment'] == 'credit'
        ? data['customerId'] as String?
        : null,
    customerName: data['customerName'] as String?,
    voided: data['voided'] as bool? ?? false,
  );

  final String id;
  final List<SaleItem> items;
  final int total;
  final int paid;
  final String cashierUid;
  final String cashierName;

  /// When the sale happened according to the phone. The server adds its own
  /// `createdAt`, which is later when the sale was made offline.
  final DateTime occurredAt;

  /// Set for a kasbon sale.
  final String? customerId;
  final String? customerName;

  /// True once the owner has voided the sale. The sale itself is kept.
  final bool voided;

  /// Sold on credit (kasbon) instead of paid in cash.
  bool get onCredit => customerId != null;

  String get payment => onCredit ? 'credit' : 'cash';

  int get change => onCredit ? 0 : paid - total;

  /// Number of pieces sold.
  int get itemCount => items.fold(0, (sum, item) => sum + item.qty);

  /// Fields of the document, without the two timestamps the repository adds.
  Map<String, dynamic> toMap() => {
    'items': [for (final item in items) item.toMap()],
    'total': total,
    'paid': paid,
    'change': change,
    'payment': payment,
    if (onCredit) 'customerId': customerId,
    if (onCredit) 'customerName': customerName,
    'cashierUid': cashierUid,
    'cashierName': cashierName,
    'dayKey': dayKeyOf(occurredAt),
  };
}
