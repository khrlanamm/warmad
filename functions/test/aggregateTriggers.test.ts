import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {beforeEach, describe, expect, it} from "vitest";

import {aggregateMove, aggregateSale} from "../src/reports/triggers";

// Runs the real aggregation transactions against the Firestore emulator
// (`npm run test:rules`).
const PROJECT = "demo-warmad";
if (getApps().length === 0) initializeApp({projectId: PROJECT});
const db = getFirestore();

const openedAt = Timestamp.fromMillis(Date.parse("2026-10-06T12:00:00Z"));
const during = Timestamp.fromMillis(openedAt.toMillis() + 3600 * 1000);
const before = Timestamp.fromMillis(openedAt.toMillis() - 600 * 1000);

const warung = db.doc("warungs/w1");
const summary = () => warung.collection("dailySummaries").doc("2026-10-06").get();
const productSales = () => warung.collection("dailyProductSales").doc("2026-10-06").get();

function sale(fields: Record<string, unknown> = {}) {
  return {
    items: [
      {productId: "indomie", name: "Indomie Goreng", qty: 2, price: 3500, subtotal: 7000},
      {productId: "aqua", name: "Aqua 600ml", qty: 1, price: 4000, subtotal: 4000},
    ],
    total: 11000, paid: 20000, change: 9000, payment: "cash",
    dayKey: "2026-10-06", occurredAt: during, ...fields,
  };
}

beforeEach(async () => {
  await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    {method: "DELETE"});
  await warung.set({name: "Warung Barokah", ownerUid: "owner"});
  await warung.collection("cash").doc("current").set({seq: 2, openedAt});
});

describe("aggregateSale", () => {
  it("adds a sale to its day and stamps it", async () => {
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale());
    await aggregateSale(db, ref);

    expect((await summary()).data()).toMatchObject({salesCash: 11000, salesCount: 1, itemsSold: 3});
    expect((await productSales()).get("qty")).toEqual({indomie: 2, aqua: 1});
    expect((await ref.get()).get("aggregatedAt")).toBeTruthy();
    expect((await ref.get()).get("late")).toBeUndefined();
  });

  it("counts a sale once, however often the trigger fires", async () => {
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale());
    await aggregateSale(db, ref);
    await aggregateSale(db, ref);
    await aggregateSale(db, ref);
    expect((await summary()).get("salesCash")).toBe(11000);
    expect((await productSales()).get("qty")).toEqual({indomie: 2, aqua: 1});
  });

  it("works when the warung is on the map and its last-active time is stale", async () => {
    // This path writes the public copy first; the reads must already be done.
    await db.doc("publicWarungs/w1").set({
      name: "Warung Barokah", lastActiveAt: Timestamp.fromMillis(Date.now() - 3600 * 1000),
    });
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale());
    await aggregateSale(db, ref);

    expect((await summary()).get("salesCash")).toBe(11000);
    const lastActive = (await db.doc("publicWarungs/w1").get()).get("lastActiveAt") as Timestamp;
    expect(Date.now() - lastActive.toMillis()).toBeLessThan(60 * 1000);
  });

  it("leaves a fresh last-active time alone and never creates a public copy", async () => {
    const fresh = Timestamp.fromMillis(Date.now() - 60 * 1000);
    await db.doc("publicWarungs/w1").set({name: "Warung Barokah", lastActiveAt: fresh});
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale());
    await aggregateSale(db, ref);
    expect((await db.doc("publicWarungs/w1").get()).get("lastActiveAt")).toEqual(fresh);

    await db.doc("publicWarungs/w1").delete();
    const second = warung.collection("sales").doc("s2");
    await second.set(sale());
    await aggregateSale(db, second);
    expect((await db.doc("publicWarungs/w1").get()).exists).toBe(false);
  });

  it("marks a cash sale made before the open period as late", async () => {
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale({occurredAt: before}));
    await aggregateSale(db, ref);
    expect((await ref.get()).get("late")).toBe(true);
    // It still counts in the report of its own day.
    expect((await summary()).get("salesCash")).toBe(11000);
  });

  it("never marks a kasbon sale as late, since it moves no cash", async () => {
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale({occurredAt: before, payment: "credit", paid: 0, change: 0}));
    await aggregateSale(db, ref);
    expect((await ref.get()).get("late")).toBeUndefined();
    expect((await summary()).data()).toMatchObject({salesCredit: 11000});
  });

  it("flags a sale whose numbers do not add up", async () => {
    const ref = warung.collection("sales").doc("s1");
    await ref.set(sale({total: 9999}));
    await aggregateSale(db, ref);
    expect((await ref.get()).get("auditProblem")).toMatch(/total/i);
  });
});

describe("aggregateMove", () => {
  const move = (fields: Record<string, unknown>) => ({
    cash: true, dayKey: "2026-10-06", occurredAt: during, ...fields,
  });

  it("adds an expense with its category, once", async () => {
    const ref = warung.collection("cashMoves").doc("m1");
    await ref.set(move({kind: "expense", amount: 25000, category: "Listrik"}));
    await aggregateMove(db, ref);
    await aggregateMove(db, ref);
    expect((await summary()).data()).toMatchObject(
      {expenses: 25000, expenseByCategory: {Listrik: 25000}});
  });

  it("takes a voided sale back out of the best sellers of its day", async () => {
    const saleRef = warung.collection("sales").doc("s1");
    await saleRef.set(sale());
    await aggregateSale(db, saleRef);

    const ref = warung.collection("cashMoves").doc("m1");
    await ref.set(move({kind: "refund", amount: 11000, saleId: "s1", salePayment: "cash"}));
    await aggregateMove(db, ref);

    expect((await summary()).data()).toMatchObject({salesCash: 11000, refunds: 11000, voidedCount: 1});
    expect((await productSales()).get("qty")).toEqual({indomie: 0, aqua: 0});
  });

  it("marks a late cash move, but not one that skipped the counters", async () => {
    const late = warung.collection("cashMoves").doc("m1");
    await late.set(move({kind: "expense", amount: 5000, category: "Lainnya", occurredAt: before}));
    await aggregateMove(db, late);
    expect((await late.get()).get("late")).toBe(true);

    // Backdated on purpose: it never touched the open period's cash.
    const backdated = warung.collection("cashMoves").doc("m2");
    await backdated.set(move(
      {kind: "expense", amount: 5000, category: "Lainnya", occurredAt: before, cash: false}));
    await aggregateMove(db, backdated);
    expect((await backdated.get()).get("late")).toBeUndefined();
  });
});
