import 'dart:math' as math;

// Inventory control figures from the spec:
//   Safety Stock = (max daily demand - average daily demand) x lead time
//   Reorder Point = average daily demand x lead time + Safety Stock
//   EOQ = sqrt(2DS / H)
//
// Cloud Functions hold the same code in TypeScript (functions/src/inventory/
// formulas.ts) and write the stored figures. This copy exists for previews
// in the app. Both run against functions/test/vectors/inventory.json, so
// they cannot drift apart.

class InventoryInput {
  const InventoryInput({
    required this.dailyQty,
    required this.leadTimeDays,
    required this.packSize,
    required this.buyPrice,
    required this.orderCost,
    required this.holdingRatePct,
  });

  /// Pieces sold per day, oldest first, from the product's first sale in the
  /// window up to yesterday. Days without a sale are zeros.
  final List<int> dailyQty;

  /// Days between ordering and the goods arriving.
  final int leadTimeDays;

  /// Pieces in one purchase unit, 1 when bought per piece.
  final int packSize;

  /// Latest buy price per piece, in Rupiah. Zero when unknown.
  final int buyPrice;

  /// S: cost of placing one order, in Rupiah.
  final int orderCost;

  /// H as a percentage of the buy price per piece per month.
  final int holdingRatePct;
}

class InventoryFigures {
  const InventoryFigures({
    required this.days,
    required this.avgDailyTenths,
    required this.maxDaily,
    required this.safetyStock,
    required this.rop,
    required this.eoq,
  });

  /// Days of history the figures are based on.
  final int days;

  /// Average pieces sold per day, times ten (123 means 12.3).
  final int avgDailyTenths;
  final int maxDaily;
  final int safetyStock;
  final int rop;

  /// Suggested order size in pieces, or null when it cannot be worked out.
  final int? eoq;
}

/// Fewer days of history than this is too little to trust.
const minHistoryDays = 14;

/// Demand period for EOQ: one month.
const _periodDays = 30;

/// Works out the figures, or returns null when there is not enough history.
/// The caller then falls back to the values the owner typed in.
InventoryFigures? computeInventory(InventoryInput input) {
  final days = input.dailyQty.length;
  if (days < minHistoryDays) return null;

  final total = input.dailyQty.fold(0, (sum, qty) => sum + qty);
  if (total <= 0) return null;
  final maxDaily = input.dailyQty.reduce(math.max);
  final lead = math.max(1, input.leadTimeDays);
  final pack = math.max(1, input.packSize);

  // (max - total/days) x lead, rounded up.
  final safetyStock = ((maxDaily * days - total) * lead / days).ceil();
  // total/days x lead + (max - total/days) x lead simplifies to max x lead.
  final rop = maxDaily * lead;

  int? eoq;
  if (input.buyPrice > 0 && input.orderCost > 0 && input.holdingRatePct > 0) {
    // D = total/days x 30, H = rate/100 x buy price.
    final numerator = 2 * total * _periodDays * input.orderCost * 100;
    final denominator = days * input.holdingRatePct * input.buyPrice;
    final raw = math.sqrt(numerator / denominator);
    // Order whole purchase units, and at least one.
    eoq = math.max(1, (raw / pack).ceil()) * pack;
  }

  return InventoryFigures(
    days: days,
    avgDailyTenths: (total * 10 / days).round(),
    maxDaily: maxDaily,
    safetyStock: safetyStock,
    rop: rop,
    eoq: eoq,
  );
}
