import {
  DocumentReference, FieldValue, Firestore, getFirestore, Timestamp, Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {
  auditSale, isLateSync, MoveDoc, productDeltaForSale, SaleDoc, summaryDeltaForMove,
  summaryDeltaForSale, SummaryDelta,
} from "./aggregate";

function millisOf(value: unknown): number | undefined {
  return value instanceof Timestamp ? value.toMillis() : undefined;
}

/** When the open cash period of a warung started. */
async function periodOpenedAt(tx: Transaction, warung: DocumentReference) {
  const cash = await tx.get(warung.collection("cash").doc("current"));
  return millisOf(cash.get("openedAt"));
}

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
export async function aggregateSale(db: Firestore, ref: DocumentReference): Promise<void> {
  const warung = ref.parent.parent!;
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const sale = snapshot.data() as (SaleDoc & {aggregatedAt?: unknown}) | undefined;
    if (!sale || sale.aggregatedAt || !sale.dayKey) return;

    // A transaction must finish all its reads before its first write.
    const publicRef = db.doc(`publicWarungs/${warung.id}`);
    const shown = await tx.get(publicRef);
    const openedAt = await periodOpenedAt(tx, warung);

    // Buyers see when the warung last recorded something. Refreshing it
    // at most every ten minutes keeps that honest without a write per sale.
    const lastActive = shown.get("lastActiveAt") as Timestamp | undefined;
    const stale = !lastActive || Date.now() - lastActive.toMillis() > 10 * 60 * 1000;
    if (shown.exists && stale) {
      tx.update(publicRef, {lastActiveAt: FieldValue.serverTimestamp()});
    }

    // Only cash sales move the drawer, so only they can arrive "late".
    const late = sale.payment !== "credit" &&
      isLateSync(millisOf(snapshot.get("occurredAt")), openedAt);

    applySummary(tx, warung, sale.dayKey, summaryDeltaForSale(sale));
    applyProducts(tx, warung, sale.dayKey, productDeltaForSale(sale));

    const problem = auditSale(sale);
    if (problem) logger.warn("Sale failed its audit", {path: ref.path, problem});
    tx.update(ref, {
      aggregatedAt: FieldValue.serverTimestamp(),
      ...(problem ? {auditProblem: problem} : {}),
      ...(late ? {late: true} : {}),
    });
  });
}

export const onSaleCreated = onDocumentCreated(
  "warungs/{wid}/sales/{saleId}",
  async (event) => {
    if (event.data) await aggregateSale(getFirestore(), event.data.ref);
  },
);

/** Adds a new cash move to the report of its day. */
export async function aggregateMove(db: Firestore, ref: DocumentReference): Promise<void> {
  const warung = ref.parent.parent!;
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
    const late = snapshot.get("cash") === true &&
      isLateSync(millisOf(snapshot.get("occurredAt")), await periodOpenedAt(tx, warung));

    applySummary(tx, warung, move.dayKey, summaryDeltaForMove(move));
    if (voided?.dayKey) {
      applyProducts(tx, warung, voided.dayKey, productDeltaForSale(voided, -1));
    }
    tx.update(ref, {
      aggregatedAt: FieldValue.serverTimestamp(),
      ...(late ? {late: true} : {}),
    });
  });
}

export const onCashMoveCreated = onDocumentCreated(
  "warungs/{wid}/cashMoves/{moveId}",
  async (event) => {
    if (event.data) await aggregateMove(getFirestore(), event.data.ref);
  },
);
