import {
  DocumentReference, FieldValue, getFirestore, Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {
  auditSale, MoveDoc, productDeltaForSale, SaleDoc, summaryDeltaForMove,
  summaryDeltaForSale, SummaryDelta,
} from "./aggregate";

function increments(values: Record<string, number>): Record<string, FieldValue> {
  const result: Record<string, FieldValue> = {};
  for (const [key, value] of Object.entries(values)) {
    if (value !== 0) result[key] = FieldValue.increment(value);
  }
  return result;
}

function applySummary(tx: Transaction, warung: DocumentReference, dayKey: string, delta: SummaryDelta) {
  const data: Record<string, unknown> = {
    ...increments(delta.fields),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (delta.expenseCategory) {
    data.expenseByCategory = {
      [delta.expenseCategory.name]: FieldValue.increment(delta.expenseCategory.amount),
    };
  }
  tx.set(warung.collection("dailySummaries").doc(dayKey), data, {merge: true});
}

function applyProducts(
  tx: Transaction, warung: DocumentReference, dayKey: string,
  delta: Record<string, {qty: number; revenue: number}>,
) {
  const qty: Record<string, FieldValue> = {};
  const revenue: Record<string, FieldValue> = {};
  for (const [productId, entry] of Object.entries(delta)) {
    qty[productId] = FieldValue.increment(entry.qty);
    revenue[productId] = FieldValue.increment(entry.revenue);
  }
  if (Object.keys(qty).length === 0) return;
  tx.set(warung.collection("dailyProductSales").doc(dayKey),
    {qty, revenue, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
}

/**
 * Adds a new sale to the report of its day.
 *
 * Reports read these small per-day documents instead of re-adding every
 * transaction, which is what keeps them fast and cheap. A trigger can fire
 * more than once for the same event, so the sale is stamped inside the same
 * transaction and skipped when the stamp is already there.
 */
export const onSaleCreated = onDocumentCreated(
  "warungs/{wid}/sales/{saleId}",
  async (event) => {
    const ref = event.data?.ref;
    if (!ref) return;
    const warung = ref.parent.parent!;
    const db = getFirestore();

    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const sale = snapshot.data() as (SaleDoc & {aggregatedAt?: unknown}) | undefined;
      if (!sale || sale.aggregatedAt || !sale.dayKey) return;

      applySummary(tx, warung, sale.dayKey, summaryDeltaForSale(sale));
      applyProducts(tx, warung, sale.dayKey, productDeltaForSale(sale));

      const problem = auditSale(sale);
      if (problem) logger.warn("Sale failed its audit", {path: ref.path, problem});
      tx.update(ref, {
        aggregatedAt: FieldValue.serverTimestamp(),
        ...(problem ? {auditProblem: problem} : {}),
      });
    });
  },
);

/** Adds a new cash move to the report of its day. */
export const onCashMoveCreated = onDocumentCreated(
  "warungs/{wid}/cashMoves/{moveId}",
  async (event) => {
    const ref = event.data?.ref;
    if (!ref) return;
    const warung = ref.parent.parent!;
    const db = getFirestore();

    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const move = snapshot.data() as
        (MoveDoc & {aggregatedAt?: unknown; saleId?: string}) | undefined;
      if (!move || move.aggregatedAt || !move.dayKey) return;

      // A void takes the items back out of the best-seller figures of the
      // day the sale was made. All reads must come before the writes.
      let voided: SaleDoc | undefined;
      if (move.kind === "refund" && move.saleId) {
        voided = (await tx.get(warung.collection("sales").doc(move.saleId))).data() as SaleDoc;
      }

      applySummary(tx, warung, move.dayKey, summaryDeltaForMove(move));
      if (voided?.dayKey) {
        applyProducts(tx, warung, voided.dayKey, productDeltaForSale(voided, -1));
      }
      tx.update(ref, {aggregatedAt: FieldValue.serverTimestamp()});
    });
  },
);
