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

import {buyer, cashier, createTestEnv, owner, WARUNG} from "./setup";

let env: RulesTestEnvironment;

const cashPath = `warungs/${WARUNG}/cash/current`;
const closingPath = (seq: number | string) => `warungs/${WARUNG}/cashClosings/${seq}`;

// The open period from the "Tutup kas harian" design.
const open = {
  seq: 1, openingBalance: 500000, salesCash: 979400, debtCollected: 0,
  purchasesCash: 134400, expenses: 100000, prive: 0, refunds: 0, salesCount: 47,
};

function closing(uid: string, counted: number, overrides: Record<string, unknown> = {}) {
  const figures = {
    seq: open.seq,
    openingBalance: open.openingBalance,
    salesCash: open.salesCash,
    debtCollected: open.debtCollected,
    purchasesCash: open.purchasesCash,
    expenses: open.expenses,
    prive: open.prive,
    refunds: open.refunds,
    salesCount: open.salesCount,
    ...overrides,
  } as Record<string, number>;
  const expected = figures.openingBalance + figures.salesCash + figures.debtCollected -
    figures.purchasesCash - figures.expenses - figures.prive - figures.refunds;
  return {
    ...figures,
    expected,
    counted,
    difference: counted - expected,
    closedByUid: uid,
    closedByName: "Rudi",
    closedAt: Timestamp.now(),
    createdAt: serverTimestamp(),
  };
}

/** The batch the app sends to close the open period. */
function closeBatch(db: Firestore, uid: string, counted = 1240000, options: {
  data?: Record<string, unknown>;
  overrides?: Record<string, unknown>;
  cash?: Record<string, unknown>;
  withClosing?: boolean;
  id?: string;
} = {}) {
  const data = {...closing(uid, counted, options.overrides), ...options.data} as Record<string, unknown>;
  const id = options.id ?? String(data.seq);
  const batch = writeBatch(db);
  if (options.withClosing ?? true) batch.set(doc(db, closingPath(id)), data);
  batch.update(doc(db, cashPath), {
    salesCash: increment(-(data.salesCash as number)),
    debtCollected: increment(-(data.debtCollected as number)),
    purchasesCash: increment(-(data.purchasesCash as number)),
    expenses: increment(-(data.expenses as number)),
    prive: increment(-(data.prive as number)),
    refunds: increment(-(data.refunds as number)),
    salesCount: increment(-(data.salesCount as number)),
    openingBalance: data.counted,
    seq: increment(1),
    openedAt: data.closedAt,
    lastTx: {kind: "cashClosings", id},
    ...options.cash,
  });
  return batch.commit();
}

beforeAll(async () => {
  env = await createTestEnv();
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), cashPath), open);
  });
});

async function read(path: string) {
  let data: Record<string, unknown> | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

describe("closing the cash period", () => {
  it("lets a cashier close with a shortfall and starts the next period", async () => {
    await assertSucceeds(closeBatch(cashier(env), "cashier", 1240000));

    const saved = await read(closingPath(1));
    expect(saved?.expected).toBe(1245000);
    expect(saved?.difference).toBe(-5000);

    // The counted cash, not the expected cash, opens the next period.
    expect(await read(cashPath)).toMatchObject({
      seq: 2, openingBalance: 1240000, salesCash: 0, purchasesCash: 0,
      expenses: 0, prive: 0, refunds: 0, salesCount: 0,
    });
  });

  it("lets the owner close too, with a surplus", async () => {
    await assertSucceeds(closeBatch(owner(env), "owner", 1250000));
    expect((await read(closingPath(1)))?.difference).toBe(5000);
  });

  it("cannot close the same period twice", async () => {
    await assertSucceeds(closeBatch(cashier(env), "cashier"));
    // A second phone that still thinks period 1 is open.
    await assertFails(closeBatch(owner(env), "owner", 1245000));
    expect((await read(cashPath))?.seq).toBe(2);
    expect((await read(closingPath(1)))?.closedByUid).toBe("cashier");
  });

  it("leaves what the closing phone had not seen for the next period", async () => {
    // Another phone synced a Rp20.000 sale that this phone never loaded.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), cashPath),
        {salesCash: increment(20000), salesCount: increment(1)});
    });
    await assertSucceeds(closeBatch(cashier(env), "cashier", 1240000));
    expect(await read(cashPath)).toMatchObject({seq: 2, salesCash: 20000, salesCount: 1});
  });

  it("rejects closing more than the counters hold", async () => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000,
      {overrides: {salesCash: open.salesCash + 1}}));
  });

  it("rejects a made-up opening balance", async () => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000,
      {overrides: {openingBalance: 0}}));
  });

  it.each([
    ["expected cash that does not add up", {expected: 2000000}],
    ["a difference that does not add up", {difference: 0}],
    ["a negative count", {counted: -1, difference: -1245001}],
    ["a fractional count", {counted: 1240000.5, difference: -4999.5}],
    ["someone else's name on it", {closedByUid: "owner"}],
    ["a backdated server time", {createdAt: Timestamp.fromMillis(0)}],
  ])("rejects %s", async (_label, data) => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000, {data}));
  });

  it("rejects an opening balance other than the counted cash", async () => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000,
      {cash: {openingBalance: 9999999}}));
  });

  it("rejects resetting the counters without a closing record", async () => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000, {withClosing: false}));
    await assertFails(updateDoc(doc(owner(env), cashPath), {salesCash: 0, seq: 2}));
  });

  it("rejects a closing record saved without resetting the counters", async () => {
    await assertFails(setDoc(doc(cashier(env), closingPath(1)), closing("cashier", 1240000)));
  });

  it("rejects skipping or reusing a period number", async () => {
    await assertFails(closeBatch(cashier(env), "cashier", 1240000,
      {overrides: {seq: 2}, id: "2"}));
    await assertFails(closeBatch(cashier(env), "cashier", 1240000, {id: "extra"}));
  });

  it("is closed to buyers", async () => {
    await assertFails(closeBatch(buyer(env), "buyer"));
  });
});

describe("closing history", () => {
  beforeEach(() => closeBatch(cashier(env), "cashier"));

  it("can be read by members only", async () => {
    await assertSucceeds(getDoc(doc(owner(env), closingPath(1))));
    await assertSucceeds(getDoc(doc(cashier(env), closingPath(1))));
    await assertFails(getDoc(doc(buyer(env), closingPath(1))));
  });

  it("cannot be edited or deleted, even by the owner", async () => {
    await assertFails(updateDoc(doc(owner(env), closingPath(1)), {difference: 0}));
    await assertFails(deleteDoc(doc(owner(env), closingPath(1))));
  });
});
