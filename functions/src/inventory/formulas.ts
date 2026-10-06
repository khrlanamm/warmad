// Inventory control figures from the spec:
//   Safety Stock = (max daily demand - average daily demand) x lead time
//   Reorder Point = average daily demand x lead time + Safety Stock
//   EOQ = sqrt(2DS / H)
//
// The app has the same code in Dart (lib/features/products/domain/
// inventory.dart) for previews. Both are run against the same test vectors
// in functions/test/vectors/inventory.json, so they cannot drift apart.

export interface InventoryInput {
  /**
   * Pieces sold per day, oldest first, from the product's first sale in the
   * window up to yesterday. Days without a sale are zeros.
   */
  dailyQty: number[];
  /** Days between ordering and the goods arriving. */
  leadTimeDays: number;
  /** Pieces in one purchase unit, 1 when the product is bought per piece. */
  packSize: number;
  /** Latest buy price per piece, in Rupiah. Zero when unknown. */
  buyPrice: number;
  /** S: cost of placing one order, in Rupiah. */
  orderCost: number;
  /** H as a percentage of the buy price per piece per month. */
  holdingRatePct: number;
}

export interface InventoryFigures {
  /** Days of history the figures are based on. */
  days: number;
  /** Average pieces sold per day, times ten (123 means 12.3). */
  avgDailyTenths: number;
  maxDaily: number;
  safetyStock: number;
  rop: number;
  /** Suggested order size in pieces, or null when it cannot be worked out. */
  eoq: number | null;
}

/** Fewer days of history than this is too little to trust. */
export const MIN_DAYS = 14;

/** Demand period for EOQ: one month. */
const PERIOD_DAYS = 30;

function ceilDiv(a: number, b: number): number {
  return Math.ceil(a / b);
}

/**
 * Works out the figures, or returns null when there is not enough history.
 * The caller then falls back to the values the owner typed in.
 *
 * Whole-number arithmetic is used wherever possible so the result is exact:
 * the averages are kept as total/days until the last step.
 */
export function computeInventory(input: InventoryInput): InventoryFigures | null {
  const days = input.dailyQty.length;
  if (days < MIN_DAYS) return null;

  const total = input.dailyQty.reduce((sum, qty) => sum + qty, 0);
  if (total <= 0) return null;
  const maxDaily = Math.max(...input.dailyQty);
  const lead = Math.max(1, input.leadTimeDays);
  const pack = Math.max(1, input.packSize);

  // (max - total/days) x lead, rounded up.
  const safetyStock = ceilDiv((maxDaily * days - total) * lead, days);
  // total/days x lead + (max - total/days) x lead simplifies to max x lead.
  const rop = maxDaily * lead;

  let eoq: number | null = null;
  if (input.buyPrice > 0 && input.orderCost > 0 && input.holdingRatePct > 0) {
    // D = total/days x 30, H = rate/100 x buy price.
    const numerator = 2 * total * PERIOD_DAYS * input.orderCost * 100;
    const denominator = days * input.holdingRatePct * input.buyPrice;
    const raw = Math.sqrt(numerator / denominator);
    // Order whole purchase units, and at least one.
    eoq = Math.max(1, Math.ceil(raw / pack)) * pack;
  }

  return {
    days,
    avgDailyTenths: Math.round((total * 10) / days),
    maxDaily,
    safetyStock,
    rop,
    eoq,
  };
}
