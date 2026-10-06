/// Default categories offered when adding a product.
const productCategories = [
  'Sembako',
  'Minuman',
  'Makanan ringan',
  'Rokok',
  'Kebutuhan rumah',
  'Lainnya',
];

enum StockStatus {
  /// Out of stock.
  habis,

  /// At or below the reorder point.
  hampirHabis,
  aman,
}

/// The unit a product is bought in, for example a "dus" holding 40 pieces.
class PackUnit {
  const PackUnit({required this.name, required this.size});

  static PackUnit? fromMap(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final size = (value['size'] as num?)?.toInt();
    if (name is! String || name.isEmpty || size == null || size < 1) {
      return null;
    }
    return PackUnit(name: name, size: size);
  }

  final String name;

  /// Number of base units in one pack.
  final int size;

  Map<String, dynamic> toMap() => {'name': name, 'size': size};
}

/// A product of a warung (`warungs/{id}/products/{id}`).
///
/// Stock is counted in the base unit (pieces). Prices are whole Rupiah per
/// base unit.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.sellPrice,
    required this.lastBuyPrice,
    required this.stock,
    this.barcode,
    this.catalogId,
    this.pack,
    this.manualRop,
    this.manualOrderQty,
    this.computedRop,
    this.computedSafetyStock,
    this.computedOrderQty,
    this.active = true,
  });

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    int? number(Object? value) => (value as num?)?.toInt();
    final computed = data['computed'];
    final figures = computed is Map ? computed : const {};
    return Product(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'Lainnya',
      sellPrice: number(data['sellPrice']) ?? 0,
      lastBuyPrice: number(data['lastBuyPrice']) ?? 0,
      stock: number(data['stock']) ?? 0,
      barcode: data['barcode'] as String?,
      catalogId: data['catalogId'] as String?,
      pack: PackUnit.fromMap(data['pack']),
      manualRop: number(data['manualRop']),
      manualOrderQty: number(data['manualOrderQty']),
      computedRop: number(figures['rop']),
      computedSafetyStock: number(figures['safetyStock']),
      computedOrderQty: number(figures['eoq']),
      active: data['active'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String category;
  final int sellPrice;

  /// Buy price per base unit of the latest restock. Zero when unknown.
  final int lastBuyPrice;

  /// Can go below zero when a sale is recorded for an item the records say
  /// is gone. The sale is real, so it is never blocked.
  final int stock;
  final String? barcode;

  /// Entry in the shared catalog, linked by Cloud Functions.
  final String? catalogId;
  final PackUnit? pack;

  /// Reorder point and order size typed in by the owner. Used until there is
  /// enough sales history to calculate them.
  final int? manualRop;
  final int? manualOrderQty;

  /// Figures calculated by Cloud Functions from real sales.
  final int? computedRop;
  final int? computedSafetyStock;
  final int? computedOrderQty;

  /// False when the owner has retired the product.
  final bool active;

  /// Stock level at or below which the product should be reordered.
  int get reorderPoint => computedRop ?? manualRop ?? 0;

  /// How much to order, in base units. Falls back to one pack.
  int? get suggestedOrderQty =>
      computedOrderQty ?? manualOrderQty ?? pack?.size;

  StockStatus get status {
    if (stock <= 0) return StockStatus.habis;
    if (stock <= reorderPoint) return StockStatus.hampirHabis;
    return StockStatus.aman;
  }

  int get profitPerUnit => sellPrice - lastBuyPrice;

  /// Whether this product matches what the cashier typed or scanned. Every
  /// word of [query] must appear in the name; a barcode must match exactly.
  bool matches(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    if (words.length == 1 && words.first.isEmpty) return true;
    if (barcode != null && barcode == query.trim()) return true;
    final haystack = name.toLowerCase();
    return words.every(haystack.contains);
  }
}

/// Orders products for the stock list: out of stock first, then low stock,
/// then the rest, each group from lowest stock up.
int compareByUrgency(Product a, Product b) {
  final byStatus = a.status.index.compareTo(b.status.index);
  if (byStatus != 0) return byStatus;
  final byStock = a.stock.compareTo(b.stock);
  if (byStock != 0) return byStock;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// What the owner fills in when adding or editing a product.
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.category,
    required this.sellPrice,
    required this.lastBuyPrice,
    this.initialStock = 0,
    this.barcode,
    this.catalogId,
    this.pack,
    this.manualRop,
    this.manualOrderQty,
  });

  final String name;
  final String category;
  final int sellPrice;
  final int lastBuyPrice;

  /// Only used when the product is created.
  final int initialStock;
  final String? barcode;
  final String? catalogId;
  final PackUnit? pack;
  final int? manualRop;
  final int? manualOrderQty;
}
