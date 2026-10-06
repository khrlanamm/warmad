import {
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc, doc, Firestore, getDoc, increment, serverTimestamp, setDoc,
  Timestamp, updateDoc, writeBatch,
} from "firebase/firestore";
import {afterAll, beforeAll, beforeEach, describe, expect, it} from "vitest";

import {buyer, cashier, createTestEnv, OTHER_WARUNG, owner, WARUNG} from "./setup";

let env: RulesTestEnvironment;

const cashPath = `warungs/${WARUNG}/cash/current`;
const productPath = `warungs/${WARUNG}/products/indomie`;

function sale(uid: string, overrides: Record<string, unknown> = {}) {
  return {
    items: [{productId: "indomie", name: "Indomie Goreng", qty: 2, price: 3500, subtotal: 7000}],
    total: 7000,
    paid: 10000,
    change: 3000,
    payment: "cash",
    cashierUid: uid,
    cashierName: "Rudi",
    occurredAt: Timestamp.now(),
    dayKey: "2026-10-06",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

/** The batch the app sends for one cash sale. Parts can be left out. */
function saleBatch(db: Firestore, uid: string, options: {
  id?: string;
  data?: Record<string, unknown>;
  withSale?: boolean;
  withCash?: boolean;
  cashAmount?: number;
  lastTxId?: string;
} = {}) {
  const id = options.id ?? "sale1";
  const data = sale(uid, options.data);
  const batch = writeBatch(db);
  if (options.withSale ?? true) {
    batch.set(doc(db, `warungs/${WARUNG}/sales/${id}`), data);
  }
  batch.update(doc(db, productPath), {stock: increment(-2), updatedAt: serverTimestamp()});
  if (options.withCash ?? true) {
    batch.update(doc(db, cashPath), {
      salesCash: increment(options.cashAmount ?? (data.total as number)),
      salesCount: increment(1),
      lastTx: {kind: "sales", id: options.lastTxId ?? id},
    });
  }
  return batch.commit();
}

beforeAll(async () => {
  env = await createTestEnv();
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, cashPath), {
      seq: 1, openingBalance: 500000, salesCash: 0, debtCollected: 0,
      purchasesCash: 0, expenses: 0, prive: 0, salesCount: 0,
    });
    await setDoc(doc(db, productPath), {
      name: "Indomie Goreng", sellPrice: 3500, lastBuyPrice: 2900, stock: 18, active: true,
    });
  });
});

async function read(path: string) {
  let data: Record<string, unknown> | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

describe("recording a cash sale", () => {
  it("lets the owner and a cashier save sale, stock and cash together", async () => {
    await assertSucceeds(saleBatch(owner(env), "owner", {id: "s1"}));
    await assertSucceeds(saleBatch(cashier(env), "cashier", {id: "s2"}));

    expect((await read(cashPath))?.salesCash).toBe(14000);
    expect((await read(cashPath))?.salesCount).toBe(2);
    expect((await read(productPath))?.stock).toBe(14);
  });

  it("rejects a sale saved without its cash", async () => {
    await assertFails(saleBatch(cashier(env), "cashier", {withCash: false}));
    // Nothing of the batch may stick, including the stock change.
    expect((await read(productPath))?.stock).toBe(18);
  });

  it("rejects cash added without a sale", async () => {
    await assertFails(saleBatch(cashier(env), "cashier", {withSale: false}));
    await assertFails(updateDoc(doc(cashier(env), cashPath), {salesCash: increment(50000)}));
    expect((await read(cashPath))?.salesCash).toBe(0);
  });

  it("rejects cash that does not equal the sale total", async () => {
    await assertFails(saleBatch(cashier(env), "cashier", {cashAmount: 5000}));
    await assertFails(saleBatch(cashier(env), "cashier", {cashAmount: 70000}));
  });

  it("rejects cash that points at an older sale", async () => {
    await assertSucceeds(saleBatch(cashier(env), "cashier", {id: "s1"}));
    await assertFails(saleBatch(cashier(env), "cashier", {id: "s2", lastTxId: "s1"}));
    // Replaying the counters against an existing sale adds no cash either.
    await assertFails(updateDoc(doc(cashier(env), cashPath), {
      salesCash: increment(7000), salesCount: increment(1), lastTx: {kind: "sales", id: "s1"},
    }));
    expect((await read(cashPath))?.salesCash).toBe(7000);
  });

  it("rejects touching other cash counters through a sale", async () => {
    const db = cashier(env);
    const batch = writeBatch(db);
    batch.set(doc(db, `warungs/${WARUNG}/sales/s1`), sale("cashier"));
    batch.update(doc(db, cashPath), {
      salesCash: increment(7000), salesCount: increment(1),
      lastTx: {kind: "sales", id: "s1"}, openingBalance: 0,
    });
    await assertFails(batch.commit());
  });

  it("rejects a sale recorded under someone else's name", async () => {
    await assertFails(saleBatch(cashier(env), "owner"));
  });

  it.each([
    ["change that does not add up", {change: 5000}],
    ["paying less than the total", {paid: 5000, change: -2000}],
    ["a fractional total", {total: 7000.5, paid: 10000, change: 2999.5}],
    ["a negative total", {total: -7000, paid: 0, change: 7000}],
    ["no items", {items: []}],
    ["a backdated server time", {createdAt: Timestamp.fromMillis(0)}],
  ])("rejects %s", async (_label, data) => {
    await assertFails(saleBatch(cashier(env), "cashier", {data}));
  });

  it("is closed to buyers and to other warungs", async () => {
    await assertFails(saleBatch(buyer(env), "buyer"));
    await assertFails(saleBatch(owner(env, OTHER_WARUNG), "owner"));
  });
});

describe("two phones selling at the same time", () => {
  it("keeps stock and cash exact", async () => {
    // Twelve sales of 2 pieces at Rp7.000, sent together from two accounts.
    const batches = [];
    for (let i = 0; i < 6; i++) {
      batches.push(saleBatch(owner(env), "owner", {id: `owner${i}`}));
      batches.push(saleBatch(cashier(env), "cashier", {id: `cashier${i}`}));
    }
    await Promise.all(batches.map((batch) => assertSucceeds(batch)));

    const cash = await read(cashPath);
    expect(cash?.salesCash).toBe(84000);
    expect(cash?.salesCount).toBe(12);
    // 18 in stock, 24 sold. Stock goes below zero instead of blocking a sale.
    expect((await read(productPath))?.stock).toBe(-6);
  });
});

describe("sales history", () => {
  beforeEach(() => saleBatch(cashier(env), "cashier", {id: "s1"}));

  it("can be read by members only", async () => {
    await assertSucceeds(getDoc(doc(owner(env), `warungs/${WARUNG}/sales/s1`)));
    await assertSucceeds(getDoc(doc(cashier(env), `warungs/${WARUNG}/sales/s1`)));
    await assertFails(getDoc(doc(buyer(env), `warungs/${WARUNG}/sales/s1`)));
  });

  it("cannot be edited or deleted, even by the owner", async () => {
    for (const db of [owner(env), cashier(env)]) {
      await assertFails(updateDoc(doc(db, `warungs/${WARUNG}/sales/s1`), {total: 1}));
      await assertFails(deleteDoc(doc(db, `warungs/${WARUNG}/sales/s1`)));
    }
  });
});
