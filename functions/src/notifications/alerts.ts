// Pure helpers that decide whether something deserves a notification and
// what it should say. Kept free of Firestore so they can be unit tested.

export interface Alert {
  type: "lowStock" | "outOfStock" | "cashClosed" | "closingReminder";
  title: string;
  body: string;
}

export interface ProductState {
  name?: string;
  stock?: number;
  active?: boolean;
  manualRop?: number | null;
  manualOrderQty?: number | null;
  pack?: {size?: number} | null;
  computed?: {rop?: number; eoq?: number | null} | null;
}

type StockStatus = "ok" | "low" | "out";

function reorderPoint(product: ProductState): number {
  return product.computed?.rop ?? product.manualRop ?? 0;
}

export function stockStatus(product: ProductState): StockStatus {
  const stock = product.stock ?? 0;
  if (stock <= 0) return "out";
  return stock <= reorderPoint(product) ? "low" : "ok";
}

/** Whole Rupiah with dots, the way the app shows it. */
export function formatRupiah(amount: number): string {
  const digits = Math.abs(amount).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${amount < 0 ? "-" : ""}Rp${digits}`;
}

/**
 * The alert for a product that just became low or ran out, or null.
 *
 * It fires only on the change itself, so the owner gets one notification per
 * event instead of one for every sale while the product stays low. A product
 * coming back up, or going from empty to merely low, is not news.
 */
export function stockAlert(
  before: ProductState | undefined, after: ProductState, showOnMap: boolean,
): Alert | null {
  if (!before || after.active === false) return null;
  const was = stockStatus(before);
  const now = stockStatus(after);
  if (now === was || now === "ok") return null;

  const name = after.name ?? "Barang";
  if (now === "out") {
    return {
      type: "outOfStock",
      title: `${name} habis`,
      body: showOnMap ?
        "Pembeli melihat status Habis di peta sampai stok diisi." :
        "Stok tercatat habis. Catat barang masuk saat stok diisi.",
    };
  }
  if (was === "out") return null;

  const suggested = after.computed?.eoq ?? after.manualOrderQty ?? after.pack?.size;
  return {
    type: "lowStock",
    title: `${name} tinggal ${after.stock} pcs`,
    body: `Sudah di bawah batas pesan (${reorderPoint(after)}).` +
      (suggested ? ` Saran pesan ${suggested} pcs.` : ""),
  };
}

export interface ClosingState {
  difference?: number;
  closedByUid?: string;
  closedByName?: string;
}

/**
 * The alert for a cash closing the owner should know about: one with a
 * difference, or one closed by someone else. The owner closing their own
 * drawer with nothing missing needs no message.
 */
export function closingAlert(closing: ClosingState, ownerUid: string): Alert | null {
  const difference = closing.difference ?? 0;
  const byOwner = closing.closedByUid === ownerUid;
  if (difference === 0 && byOwner) return null;

  const who = closing.closedByName || "kasir";
  return {
    type: "cashClosed",
    title: difference === 0 ?
      "Kas ditutup, tidak ada selisih" :
      `Kas ditutup, selisih ${formatRupiah(difference)}`,
    body: difference < 0 ?
      `Uang di laci kurang dari catatan. Ditutup oleh ${who}.` :
      difference > 0 ?
        `Uang di laci lebih dari catatan. Ditutup oleh ${who}.` :
        `Ditutup oleh ${who}.`,
  };
}

/** Jakarta wall-clock time as "23:30", rounded down to a quarter hour. */
export function reminderSlot(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Jakarta", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(now);
  const hour = parts.find((part) => part.type === "hour")!.value;
  const minute = Number(parts.find((part) => part.type === "minute")!.value);
  const quarter = Math.floor(minute / 15) * 15;
  return `${hour}:${String(quarter).padStart(2, "0")}`;
}
