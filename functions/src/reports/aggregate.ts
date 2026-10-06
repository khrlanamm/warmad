// Pure helpers that turn one sale or one cash move into the amounts to add
// to the daily report documents. Kept free of Firestore so they can be unit
// tested and reused by the backfill script.

/** Amounts to add to `dailySummaries/{dayKey}`. All whole Rupiah or counts. */
export interface SummaryDelta {
  fields: Record<string, number>;
  /** Business expenses also add up per category. */
  expenseCategory?: {name: string; amount: number};
}

export interface SaleItem {
  productId: string;
  qty: number;
  price: number;
  subtotal: number;
}

export interface SaleDoc {
  items?: SaleItem[];
  total?: number;
  payment?: string;
  dayKey?: string;
}

export interface MoveDoc {
  kind?: string;
  amount?: number;
  paidFrom?: string;
  salePayment?: string;
  category?: string;
  dayKey?: string;
}

function itemsOf(sale: SaleDoc): SaleItem[] {
  return Array.isArray(sale.items) ? sale.items : [];
}

/** What a new sale adds to the summary of its day. */
export function summaryDeltaForSale(sale: SaleDoc): SummaryDelta {
  const total = sale.total ?? 0;
  const pieces = itemsOf(sale).reduce((sum, item) => sum + (item.qty ?? 0), 0);
  const onCredit = sale.payment === "credit";
  return {
    fields: {
      [onCredit ? "salesCredit" : "salesCash"]: total,
      salesCount: 1,
      itemsSold: pieces,
    },
  };
}

/**
 * What a cash move adds to the summary of its day.
 *
 * The report follows the date the money actually moved, so a purchase paid
 * in cash counts as cash out on its own date even when it was recorded late
 * and skipped the open period's counters. Only goods bought on debt and
 * refunds of kasbon sales move no cash at all.
 */
export function summaryDeltaForMove(move: MoveDoc): SummaryDelta {
  const amount = move.amount ?? 0;
  switch (move.kind) {
    case "purchase":
      return {fields: {[move.paidFrom === "debt" ? "purchasesDebt" : "purchasesCash"]: amount}};
    case "supplierPayment":
      return {fields: {supplierPayments: amount}};
    case "expense":
      return {
        fields: {expenses: amount},
        expenseCategory: {name: move.category || "Lainnya", amount},
      };
    case "prive":
      return {fields: {prive: amount}};
    case "debtPayment":
      return {fields: {debtCollected: amount}};
    case "refund":
      return {
        fields: {
          [move.salePayment === "credit" ? "refundsCredit" : "refunds"]: amount,
          voidedCount: 1,
        },
      };
    default:
      return {fields: {}};
  }
}

/** Pieces and revenue per product for one sale. `sign` is -1 for a void. */
export function productDeltaForSale(
  sale: SaleDoc, sign: 1 | -1 = 1,
): Record<string, {qty: number; revenue: number}> {
  const delta: Record<string, {qty: number; revenue: number}> = {};
  for (const item of itemsOf(sale)) {
    if (!item.productId) continue;
    const entry = delta[item.productId] ?? {qty: 0, revenue: 0};
    entry.qty += sign * (item.qty ?? 0);
    entry.revenue += sign * (item.subtotal ?? 0);
    delta[item.productId] = entry;
  }
  return delta;
}

/**
 * Checks the arithmetic of a sale, which Security Rules cannot do because
 * they cannot loop over the items. Returns a description of what is wrong,
 * or null when everything adds up.
 */
export function auditSale(sale: SaleDoc): string | null {
  const items = itemsOf(sale);
  if (items.length === 0) return "Sale has no items.";
  let sum = 0;
  for (const item of items) {
    if (!Number.isInteger(item.qty) || item.qty <= 0) return "An item has an invalid quantity.";
    if (!Number.isInteger(item.price) || item.price < 0) return "An item has an invalid price.";
    if (item.subtotal !== item.qty * item.price) return "An item subtotal is not quantity times price.";
    sum += item.subtotal;
  }
  if (sum !== sale.total) return "The total is not the sum of the items.";
  return null;
}
