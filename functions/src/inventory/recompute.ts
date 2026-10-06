import {
  DocumentReference, FieldPath, FieldValue, Firestore, getFirestore,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {computeInventory} from "./formulas";

/** Days of sales history the figures look back over. */
const WINDOW_DAYS = 30;

/** Used until the owner sets their own in the warung settings. */
export const DEFAULTS = {leadTimeDays: 1, orderCost: 2000, holdingRatePct: 10};

/** Calendar day in Jakarta as "2026-10-06", matching the app's day keys. */
export function jakartaDayKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {timeZone: "Asia/Jakarta"}).format(date);
}

/** The `count` day keys before the day of `now`, oldest first. */
export function previousDayKeys(now: Date, count: number): string[] {
  const keys: string[] = [];
  for (let back = count; back >= 1; back--) {
    keys.push(jakartaDayKey(new Date(now.getTime() - back * 24 * 3600 * 1000)));
  }
  return keys;
}

/**
 * Pieces sold per day for one product: from its first sale in the window up
 * to the last day, with zeros for days without a sale. Empty when it did not
 * sell at all. A day that went negative through voids counts as zero.
 */
export function seriesFor(dayKeys: string[], qtyByDay: Map<string, number>): number[] {
  const first = dayKeys.findIndex((key) => (qtyByDay.get(key) ?? 0) > 0);
  if (first < 0) return [];
  return dayKeys.slice(first).map((key) => Math.max(0, qtyByDay.get(key) ?? 0));
}

/**
 * Recalculates reorder point, safety stock and order size for every active
 * product of one warung from its recent sales. Returns how many products
 * changed. Only changed products are written, so a quiet warung costs
 * nothing but the reads.
 */
export async function recomputeWarung(
  db: Firestore, warung: DocumentReference, now: Date,
): Promise<number> {
  const dayKeys = previousDayKeys(now, WINDOW_DAYS);
  const settings = {...DEFAULTS, ...((await warung.get()).get("inventory") ?? {})};

  const sales = await warung.collection("dailyProductSales")
    .orderBy(FieldPath.documentId())
    .startAt(dayKeys[0]).endAt(dayKeys[dayKeys.length - 1]).get();
  const qtyByProduct = new Map<string, Map<string, number>>();
  for (const day of sales.docs) {
    const qty = (day.get("qty") ?? {}) as Record<string, number>;
    for (const [productId, pieces] of Object.entries(qty)) {
      if (!qtyByProduct.has(productId)) qtyByProduct.set(productId, new Map());
      qtyByProduct.get(productId)!.set(day.id, pieces);
    }
  }

  const products = await warung.collection("products")
    .where("active", "==", true)
    .select("pack", "lastBuyPrice", "leadTimeDays", "computed").get();

  let batch = db.batch();
  let pending = 0;
  let changed = 0;
  for (const product of products.docs) {
    const figures = computeInventory({
      dailyQty: seriesFor(dayKeys, qtyByProduct.get(product.id) ?? new Map()),
      leadTimeDays: product.get("leadTimeDays") ?? settings.leadTimeDays,
      packSize: product.get("pack")?.size ?? 1,
      buyPrice: product.get("lastBuyPrice") ?? 0,
      orderCost: settings.orderCost,
      holdingRatePct: settings.holdingRatePct,
    });
    const before = product.get("computed") ?? null;
    const same = figures === null ? before === null :
      before !== null && before.rop === figures.rop &&
      before.safetyStock === figures.safetyStock && before.eoq === figures.eoq &&
      before.avgDailyTenths === figures.avgDailyTenths && before.days === figures.days;
    if (same) continue;

    batch.update(product.ref, {
      computed: figures ?? FieldValue.delete(),
      // The phones sync products changed since their last sync.
      updatedAt: FieldValue.serverTimestamp(),
    });
    changed++;
    if (++pending === 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return changed;
}

/** Runs every night at 02:00 Jakarta time, when warungs are quietest. */
export const recomputeInventory = onSchedule(
  {schedule: "0 2 * * *", timeZone: "Asia/Jakarta", timeoutSeconds: 540},
  async () => {
    const db = getFirestore();
    const now = new Date();
    const warungs = await db.collection("warungs").select().get();
    for (const warung of warungs.docs) {
      try {
        const changed = await recomputeWarung(db, warung.ref, now);
        logger.info("Recomputed inventory", {warung: warung.id, changed});
      } catch (error) {
        // One broken warung must not stop the others.
        logger.error("Inventory recompute failed", {warung: warung.id, error});
      }
    }
  },
);
