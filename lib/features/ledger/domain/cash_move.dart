/// Every movement of money or goods that is not a sale.
enum CashMoveKind {
  /// Stock bought from a supplier (barang masuk).
  purchase,

  /// Supplier debt paid off.
  supplierPayment,

  /// A business expense.
  expense,

  /// Money the owner took for personal use. It leaves the drawer but is not
  /// a business cost.
  prive,

  /// A customer paying back kasbon.
  debtPayment,

  /// Stock and money given back for a voided sale.
  refund;

  static CashMoveKind? parse(Object? value) =>
      CashMoveKind.values.where((kind) => kind.name == value).firstOrNull;

  /// The counter of the open cash period this kind belongs to. Must match
  /// `counterOf` in firestore.rules.
  String get counter => switch (this) {
    purchase || supplierPayment => 'purchasesCash',
    expense => 'expenses',
    prive => 'prive',
    debtPayment => 'debtCollected',
    refund => 'refunds',
  };

  /// True when cash comes into the drawer rather than leaving it.
  bool get isCashIn => this == debtPayment;
}

const expenseCategories = [
  'Listrik',
  'Sewa',
  'Gaji',
  'Transport',
  'Plastik & kemasan',
  'Lainnya',
];

/// Whether an entry at [occurredAt] moves the cash of the period that opened
/// at [openedAt].
///
/// An entry dated before the period started does not: that money left the
/// drawer earlier and already showed up as a difference at an older closing.
/// Counting it again now would make the current closing look wrong.
bool countsInOpenPeriod(DateTime occurredAt, DateTime? openedAt) =>
    openedAt == null || !occurredAt.isBefore(openedAt);

/// The moment to record for an entry the user dated [day]: right now for
/// today, noon for any other day (the exact time is not known).
DateTime occurredAtFor(DateTime day, DateTime now) {
  final sameDay =
      day.year == now.year && day.month == now.month && day.day == now.day;
  return sameDay ? now : DateTime(day.year, day.month, day.day, 12);
}

/// One document in `warungs/{id}/cashMoves`. Amounts are whole Rupiah.
class CashMove {
  const CashMove({
    required this.id,
    required this.kind,
    required this.amount,
    required this.cash,
    required this.occurredAt,
    required this.createdByUid,
    required this.createdByName,
    this.note,
    this.productId,
    this.productName,
    this.qty,
    this.paidFrom,
    this.supplierId,
    this.supplierName,
    this.category,
    this.customerId,
    this.customerName,
    this.saleId,
    this.salePayment,
  }) : assert(amount > 0);

  factory CashMove.fromMap(
    String id,
    Map<String, dynamic> data, {
    required DateTime occurredAt,
  }) => CashMove(
    id: id,
    kind: CashMoveKind.parse(data['kind']) ?? CashMoveKind.expense,
    amount: (data['amount'] as num?)?.toInt() ?? 1,
    cash: data['cash'] as bool? ?? true,
    occurredAt: occurredAt,
    createdByUid: data['createdByUid'] as String? ?? '',
    createdByName: data['createdByName'] as String? ?? '',
    note: data['note'] as String?,
    productId: data['productId'] as String?,
    productName: data['productName'] as String?,
    qty: (data['qty'] as num?)?.toInt(),
    paidFrom: data['paidFrom'] as String?,
    supplierId: data['supplierId'] as String?,
    supplierName: data['supplierName'] as String?,
    category: data['category'] as String?,
    customerId: data['customerId'] as String?,
    customerName: data['customerName'] as String?,
    saleId: data['saleId'] as String?,
    salePayment: data['salePayment'] as String?,
  );

  final String id;
  final CashMoveKind kind;
  final int amount;

  /// Whether [amount] moved in the drawer during the open cash period. False
  /// for goods bought on debt, a refund of a kasbon sale, and entries dated
  /// before the period started.
  final bool cash;
  final DateTime occurredAt;
  final String createdByUid;
  final String createdByName;
  final String? note;

  // Purchase.
  final String? productId;
  final String? productName;
  final int? qty;

  /// "cash" or "debt".
  final String? paidFrom;
  final String? supplierId;
  final String? supplierName;

  // Expense and prive.
  final String? category;

  // Kasbon paid back.
  final String? customerId;
  final String? customerName;

  // Refund.
  final String? saleId;
  final String? salePayment;

  bool get onDebt => kind == CashMoveKind.purchase && paidFrom == 'debt';

  /// Fields of the document, without the timestamps the repository adds.
  /// Only the fields that belong to [kind] are written.
  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'amount': amount,
    'cash': cash,
    'createdByUid': createdByUid,
    'createdByName': createdByName,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (productId != null) 'productId': productId,
    if (productName != null) 'productName': productName,
    if (qty != null) 'qty': qty,
    if (paidFrom != null) 'paidFrom': paidFrom,
    if (supplierId != null) 'supplierId': supplierId,
    if (supplierName != null) 'supplierName': supplierName,
    if (category != null) 'category': category,
    if (customerId != null) 'customerId': customerId,
    if (customerName != null) 'customerName': customerName,
    if (saleId != null) 'saleId': saleId,
    if (salePayment != null) 'salePayment': salePayment,
  };
}

/// A supplier and what the warung owes them.
class Supplier {
  const Supplier({required this.id, required this.name, this.debt = 0});

  factory Supplier.fromMap(String id, Map<String, dynamic> data) => Supplier(
    id: id,
    name: data['name'] as String? ?? '',
    debt: (data['debt'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final int debt;
}

/// A customer who buys on credit (kasbon) and what they owe.
class Customer {
  const Customer({required this.id, required this.name, this.balance = 0});

  factory Customer.fromMap(String id, Map<String, dynamic> data) => Customer(
    id: id,
    name: data['name'] as String? ?? '',
    balance: (data['balance'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final int balance;
}
