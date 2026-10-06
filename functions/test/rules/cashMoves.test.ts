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

const root = `warungs/${WARUNG}`;
const cashPath = `${root}/cash/current`;
const productPath = `${root}/products/aqua`;
const supplierPath = `${root}/suppliers/sumber`;
const customerPath = `${root}/customers/bu-siti`;
const movePath = (id: string) => `${root}/cashMoves/${id}`;
const salePath = (id: string) => `${root}/sales/${id}`;

// The open period started yesterday at noon.
const openedAt = Timestamp.fromMillis(Date.now() - 36 * 3600 * 1000);
const now = () => Timestamp.now();
const lastWeek = () => Timestamp.fromMillis(Date.now() - 7 * 24 * 3600 * 1000);

function move(uid: string, fields: Record<string, unknown>) {
  return {
    cash: true,
    occurredAt: now(),
    dayKey: "2026-10-06",
    createdByUid: uid,
    createdByName: "Rudi",
    createdAt: serverTimestamp(),
    ...fields,
  };
}

/** Writes a move plus whatever else the app puts in the same batch. */
function commit(db: Firestore, id: string, data: Record<string, unknown>, also: {
  cash?: Record<string, unknown> | null;
  product?: Record<string, unknown>;
  supplier?: Record<string, unknown>;
  customer?: Record<string, unknown>;
  withMove?: boolean;
} = {}) {
  const batch = writeBatch(db);
  if (also.withMove ?? true) batch.set(doc(db, movePath(id)), data);
  if (also.product) batch.update(doc(db, productPath), also.product);
  if (also.cash) batch.update(doc(db, cashPath), {...also.cash, lastTx: {kind: "cashMoves", id}});
  if (also.supplier) {
    batch.update(doc(db, supplierPath), {...also.supplier, lastTx: {kind: "cashMoves", id}});
  }
  if (also.customer) {
    batch.update(doc(db, customerPath), {...also.customer, lastTx: {kind: "cashMoves", id}});
  }
  return batch.commit();
}

const restock = {stock: increment(48), lastBuyPrice: 2800, updatedAt: serverTimestamp()};

function purchase(uid: string, fields: Record<string, unknown> = {}) {
  return move(uid, {
    kind: "purchase", amount: 134400, productId: "aqua", productName: "Aqua 600ml",
    qty: 48, paidFrom: "cash", ...fields,
  });
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
      seq: 3, openedAt, openingBalance: 500000, salesCash: 979400, debtCollected: 0,
      purchasesCash: 0, expenses: 0, prive: 0, refunds: 0, salesCount: 47,
    });
    await setDoc(doc(db, productPath), {
      name: "Aqua 600ml", sellPrice: 4000, lastBuyPrice: 2700, stock: 9, active: true,
    });
    await setDoc(doc(db, supplierPath), {name: "Grosir Sumber Rejeki", debt: 200000});
    await setDoc(doc(db, customerPath), {name: "Bu Siti", balance: 50000});
  });
});

async function read(path: string) {
  let data: Record<string, unknown> | undefined;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

describe("stock bought with cash", () => {
  it("adds stock and takes the money out of cash in one step", async () => {
    await assertSucceeds(commit(cashier(env), "m1", purchase("cashier"),
      {product: restock, cash: {purchasesCash: increment(134400)}}));
    expect((await read(productPath))?.stock).toBe(57);
    expect((await read(cashPath))?.purchasesCash).toBe(134400);
  });

  it("rejects the purchase without its cash", async () => {
    await assertFails(commit(cashier(env), "m1", purchase("cashier"), {product: restock}));
    expect((await read(productPath))?.stock).toBe(9);
  });

  it("rejects cash that differs from the purchase or lands in another counter", async () => {
    await assertFails(commit(cashier(env), "m1", purchase("cashier"),
      {product: restock, cash: {purchasesCash: increment(100000)}}));
    await assertFails(commit(cashier(env), "m1", purchase("cashier"),
      {product: restock, cash: {expenses: increment(134400)}}));
  });

  it("rejects taking cash out with no record behind it", async () => {
    await assertFails(commit(cashier(env), "m1", purchase("cashier"),
      {withMove: false, cash: {purchasesCash: increment(134400)}}));
  });
});

describe("stock bought on debt", () => {
  const onDebt = (uid: string) => purchase(uid, {
    paidFrom: "debt", cash: false, supplierId: "sumber", supplierName: "Grosir Sumber Rejeki",
  });

  it("adds stock and supplier debt but leaves cash alone", async () => {
    await assertSucceeds(commit(cashier(env), "m1", onDebt("cashier"),
      {product: restock, supplier: {debt: increment(134400)}}));
    expect((await read(supplierPath))?.debt).toBe(334400);
    expect((await read(cashPath))?.purchasesCash).toBe(0);
  });

  it("rejects the purchase when the debt is not recorded", async () => {
    await assertFails(commit(cashier(env), "m1", onDebt("cashier"), {product: restock}));
  });

  it("rejects a debt that differs from the purchase", async () => {
    await assertFails(commit(cashier(env), "m1", onDebt("cashier"),
      {product: restock, supplier: {debt: increment(1000)}}));
  });

  it("rejects claiming a cash purchase moved no cash today", async () => {
    await assertFails(commit(cashier(env), "m1", purchase("cashier", {cash: false}),
      {product: restock}));
  });

  it("rejects changing supplier debt directly", async () => {
    await assertFails(updateDoc(doc(owner(env), supplierPath), {debt: 0}));
    await assertFails(updateDoc(doc(cashier(env), supplierPath), {debt: increment(-200000)}));
  });
});

describe("paying a supplier", () => {
  const payment = (uid: string, amount = 150000) => move(uid, {
    kind: "supplierPayment", amount, supplierId: "sumber", supplierName: "Grosir Sumber Rejeki",
  });

  it("lowers the debt and takes cash out together", async () => {
    await assertSucceeds(commit(owner(env), "m1", payment("owner"), {
      supplier: {debt: increment(-150000)}, cash: {purchasesCash: increment(150000)},
    }));
    expect((await read(supplierPath))?.debt).toBe(50000);
    expect((await read(cashPath))?.purchasesCash).toBe(150000);
  });

  it("rejects lowering the debt without paying", async () => {
    await assertFails(commit(owner(env), "m1", payment("owner"),
      {supplier: {debt: increment(-150000)}}));
  });

  it("rejects paying without lowering the debt", async () => {
    await assertFails(commit(owner(env), "m1", payment("owner"),
      {cash: {purchasesCash: increment(150000)}}));
  });
});

describe("expenses and prive", () => {
  const expense = (uid: string, fields: Record<string, unknown> = {}) => move(uid, {
    kind: "expense", amount: 25000, category: "Plastik & kemasan", note: "Kantong plastik 2 pak",
    ...fields,
  });

  it("records a business expense in the expenses counter", async () => {
    await assertSucceeds(commit(cashier(env), "m1", expense("cashier"),
      {cash: {expenses: increment(25000)}}));
    expect(await read(cashPath)).toMatchObject({expenses: 25000, prive: 0});
  });

  it("keeps prive apart from business expenses", async () => {
    const prive = expense("owner", {kind: "prive", amount: 50000, category: "Pribadi"});
    await assertSucceeds(commit(owner(env), "m1", prive, {cash: {prive: increment(50000)}}));
    expect(await read(cashPath)).toMatchObject({expenses: 0, prive: 50000});
    // Prive booked as a business expense is refused.
    await assertFails(commit(owner(env), "m2", prive, {cash: {expenses: increment(50000)}}));
  });

  it("rejects an expense without its cash, and cash without an expense", async () => {
    await assertFails(commit(cashier(env), "m1", expense("cashier")));
    await assertFails(commit(cashier(env), "m1", expense("cashier"),
      {withMove: false, cash: {expenses: increment(25000)}}));
  });

  it("lets an entry dated before the open period skip the cash counters", async () => {
    const old = expense("owner", {cash: false, occurredAt: lastWeek(), dayKey: "2026-09-29"});
    await assertSucceeds(commit(owner(env), "m1", old));
    expect((await read(cashPath))?.expenses).toBe(0);
  });

  it("still accepts a late entry that counts cash in the open period", async () => {
    // Recorded offline before the last closing, synced after it.
    const late = expense("cashier", {occurredAt: lastWeek()});
    await assertSucceeds(commit(cashier(env), "m1", late, {cash: {expenses: increment(25000)}}));
  });

  it("rejects hiding today's expense from cash", async () => {
    await assertFails(commit(cashier(env), "m1", expense("cashier", {cash: false})));
  });

  it.each([
    ["a zero amount", {amount: 0}],
    ["a negative amount", {amount: -25000}],
    ["a fractional amount", {amount: 2500.5}],
    ["someone else's name on it", {createdByUid: "owner"}],
    ["a backdated server time", {createdAt: Timestamp.fromMillis(0)}],
    ["an unknown kind", {kind: "bonus"}],
  ])("rejects %s", async (_label, fields) => {
    const data = expense("cashier", fields);
    await assertFails(commit(cashier(env), "m1", data,
      {cash: {expenses: increment(data.amount as number)}}));
  });

  it("is closed to buyers", async () => {
    await assertFails(commit(buyer(env), "m1", expense("buyer"),
      {cash: {expenses: increment(25000)}}));
  });

  it("cannot be edited or deleted afterwards", async () => {
    await commit(cashier(env), "m1", expense("cashier"), {cash: {expenses: increment(25000)}});
    await assertFails(updateDoc(doc(owner(env), movePath("m1")), {amount: 1}));
    await assertFails(deleteDoc(doc(owner(env), movePath("m1"))));
  });
});

describe("kasbon", () => {
  function creditSale(uid: string, fields: Record<string, unknown> = {}) {
    return {
      items: [{productId: "aqua", name: "Aqua 600ml", qty: 3, price: 4000, subtotal: 12000}],
      total: 12000, paid: 0, change: 0, payment: "credit",
      customerId: "bu-siti", customerName: "Bu Siti",
      cashierUid: uid, cashierName: "Rudi", occurredAt: now(), dayKey: "2026-10-06",
      createdAt: serverTimestamp(), ...fields,
    };
  }
  function sellOnCredit(db: Firestore, uid: string, options: {
    data?: Record<string, unknown>; balance?: number | null;
  } = {}) {
    const batch = writeBatch(db);
    batch.set(doc(db, salePath("s1")), creditSale(uid, options.data));
    batch.update(doc(db, productPath), {stock: increment(-3), updatedAt: serverTimestamp()});
    if (options.balance !== null) {
      batch.update(doc(db, customerPath), {
        balance: increment(options.balance ?? 12000), lastTx: {kind: "sales", id: "s1"},
      });
    }
    return batch.commit();
  }

  it("takes stock and raises the customer's balance, without touching cash", async () => {
    await assertSucceeds(sellOnCredit(cashier(env), "cashier"));
    expect((await read(customerPath))?.balance).toBe(62000);
    expect((await read(productPath))?.stock).toBe(6);
    expect(await read(cashPath)).toMatchObject({salesCash: 979400, salesCount: 47});
  });

  it("rejects a kasbon sale without the customer's balance", async () => {
    await assertFails(sellOnCredit(cashier(env), "cashier", {balance: null}));
  });

  it("rejects a balance that differs from the sale", async () => {
    await assertFails(sellOnCredit(cashier(env), "cashier", {balance: 5000}));
  });

  it("rejects a kasbon sale that also claims payment", async () => {
    await assertFails(sellOnCredit(cashier(env), "cashier", {data: {paid: 12000}}));
  });

  it("rejects changing a balance directly", async () => {
    await assertFails(updateDoc(doc(cashier(env), customerPath), {balance: 0}));
    await assertFails(updateDoc(doc(owner(env), customerPath), {balance: increment(-50000)}));
  });

  const payBack = (uid: string, amount = 30000) => move(uid, {
    kind: "debtPayment", amount, customerId: "bu-siti", customerName: "Bu Siti",
  });

  it("paying back lowers the balance and adds cash together", async () => {
    await assertSucceeds(commit(cashier(env), "m1", payBack("cashier"), {
      customer: {balance: increment(-30000)}, cash: {debtCollected: increment(30000)},
    }));
    expect((await read(customerPath))?.balance).toBe(20000);
    expect((await read(cashPath))?.debtCollected).toBe(30000);
  });

  it("rejects lowering the balance without the cash, and the reverse", async () => {
    await assertFails(commit(cashier(env), "m1", payBack("cashier"),
      {customer: {balance: increment(-30000)}}));
    await assertFails(commit(cashier(env), "m1", payBack("cashier"),
      {cash: {debtCollected: increment(30000)}}));
  });

  it("lets members add a customer or supplier that starts at zero", async () => {
    const db = cashier(env);
    await assertSucceeds(setDoc(doc(db, `${root}/customers/new`), {name: "Pak Budi", balance: 0}));
    await assertFails(setDoc(doc(db, `${root}/customers/new2`), {name: "Pak Budi", balance: -1000}));
    await assertSucceeds(setDoc(doc(db, `${root}/suppliers/new`), {name: "Agen Baru", debt: 0}));
    await assertFails(setDoc(doc(db, `${root}/suppliers/new2`), {name: "Agen", debt: 5}));
  });
});

describe("voiding a sale", () => {
  const cashSale = {
    items: [{productId: "aqua", name: "Aqua 600ml", qty: 2, price: 4000, subtotal: 8000}],
    total: 8000, paid: 10000, change: 2000, payment: "cash",
    cashierUid: "cashier", cashierName: "Rudi", dayKey: "2026-10-06",
  };

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, salePath("s1")), {...cashSale, occurredAt: now(), createdAt: now()});
      await setDoc(doc(db, salePath("k1")), {
        ...cashSale, total: 12000, paid: 0, change: 0, payment: "credit",
        customerId: "bu-siti", customerName: "Bu Siti", occurredAt: now(), createdAt: now(),
      });
    });
  });

  function voidSale(db: Firestore, uid: string, options: {
    saleId?: string; amount?: number; payment?: string; cash?: number | null;
    balance?: number | null; markSale?: boolean;
  } = {}) {
    const saleId = options.saleId ?? "s1";
    const payment = options.payment ?? "cash";
    const amount = options.amount ?? 8000;
    const batch = writeBatch(db);
    batch.set(doc(db, movePath("v1")), move(uid, {
      kind: "refund", amount, saleId, salePayment: payment, cash: payment === "cash",
      ...(payment === "credit" ? {customerId: "bu-siti"} : {}),
    }));
    if (options.markSale ?? true) {
      batch.update(doc(db, salePath(saleId)), {
        voided: true, voidedAt: now(), voidedByUid: uid, voidMoveId: "v1",
      });
    }
    batch.update(doc(db, productPath), {stock: increment(2), updatedAt: serverTimestamp()});
    if (payment === "cash" && options.cash !== null) {
      batch.update(doc(db, cashPath), {
        refunds: increment(options.cash ?? amount), lastTx: {kind: "cashMoves", id: "v1"},
      });
    }
    if (payment === "credit" && options.balance !== null) {
      batch.update(doc(db, customerPath), {
        balance: increment(-(options.balance ?? amount)), lastTx: {kind: "cashMoves", id: "v1"},
      });
    }
    return batch.commit();
  }

  it("lets the owner give back stock and money while keeping the sale", async () => {
    await assertSucceeds(voidSale(owner(env), "owner"));
    expect(await read(salePath("s1"))).toMatchObject({voided: true, total: 8000});
    expect((await read(productPath))?.stock).toBe(11);
    expect(await read(cashPath)).toMatchObject({refunds: 8000, salesCash: 979400});
  });

  it("is not allowed for a cashier", async () => {
    await assertFails(voidSale(cashier(env), "cashier"));
  });

  it("cannot be done twice", async () => {
    await assertSucceeds(voidSale(owner(env), "owner"));
    await assertFails(voidSale(owner(env), "owner"));
    expect((await read(cashPath))?.refunds).toBe(8000);
  });

  it("rejects a refund for more or less than the sale", async () => {
    await assertFails(voidSale(owner(env), "owner", {amount: 80000}));
    await assertFails(voidSale(owner(env), "owner", {amount: 1}));
  });

  it("rejects a refund that does not mark the sale, or leaves cash out", async () => {
    await assertFails(voidSale(owner(env), "owner", {markSale: false}));
    await assertFails(voidSale(owner(env), "owner", {cash: null}));
  });

  it("gives a voided kasbon sale back to the customer's balance, not to cash", async () => {
    await assertSucceeds(voidSale(owner(env), "owner",
      {saleId: "k1", amount: 12000, payment: "credit"}));
    expect((await read(customerPath))?.balance).toBe(38000);
    expect((await read(cashPath))?.refunds).toBe(0);
  });

  it("rejects voiding a kasbon sale as if it had been paid in cash", async () => {
    await assertFails(voidSale(owner(env), "owner", {saleId: "k1", amount: 12000}));
  });

  it("still forbids rewriting or deleting a sale", async () => {
    await assertFails(updateDoc(doc(owner(env), salePath("s1")), {total: 1}));
    await assertFails(updateDoc(doc(owner(env), salePath("s1")), {voided: true}));
    await assertFails(deleteDoc(doc(owner(env), salePath("s1"))));
  });
});
