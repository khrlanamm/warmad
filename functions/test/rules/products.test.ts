import {
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, increment, setDoc, updateDoc} from "firebase/firestore";
import {afterAll, beforeAll, beforeEach, describe, it} from "vitest";

import {anonymous, buyer, cashier, createTestEnv, OTHER_WARUNG, owner, WARUNG} from "./setup";

let env: RulesTestEnvironment;

const product = {
  name: "Indomie Goreng",
  category: "Sembako",
  sellPrice: 3500,
  lastBuyPrice: 2900,
  stock: 18,
  active: true,
};
const path = `warungs/${WARUNG}/products/indomie`;

beforeAll(async () => {
  env = await createTestEnv();
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, path), {...product, computed: {rop: 24}});
    await setDoc(doc(db, "catalog/indomie-goreng"), {name: "Indomie Goreng"});
  });
});

describe("catalog", () => {
  it("can be read by any signed in user but not written", async () => {
    await assertSucceeds(getDoc(doc(buyer(env), "catalog/indomie-goreng")));
    await assertFails(getDoc(doc(anonymous(env), "catalog/indomie-goreng")));
    await assertFails(setDoc(doc(owner(env), "catalog/palsu"), {name: "Palsu"}));
  });
});

describe("products", () => {
  it("can be read by members only", async () => {
    await assertSucceeds(getDoc(doc(owner(env), path)));
    await assertSucceeds(getDoc(doc(cashier(env), path)));
    await assertFails(getDoc(doc(buyer(env), path)));
    await assertFails(getDoc(doc(owner(env, OTHER_WARUNG), path)));
  });

  it("can be created by the owner only", async () => {
    const fresh = `warungs/${WARUNG}/products/aqua`;
    await assertSucceeds(setDoc(doc(owner(env), fresh), product));
    await assertFails(setDoc(doc(cashier(env), `${fresh}2`), product));
    await assertFails(setDoc(doc(buyer(env), `${fresh}3`), product));
  });

  it("rejects money that is not a whole non-negative number", async () => {
    const db = owner(env);
    const fresh = `warungs/${WARUNG}/products/aqua`;
    await assertFails(setDoc(doc(db, fresh), {...product, sellPrice: 3500.5}));
    await assertFails(setDoc(doc(db, fresh), {...product, sellPrice: -1}));
    await assertFails(setDoc(doc(db, fresh), {...product, lastBuyPrice: "2900"}));
    await assertFails(setDoc(doc(db, fresh), {...product, stock: 1.5}));
    await assertFails(setDoc(doc(db, fresh), {...product, name: ""}));
  });

  it("lets the owner edit prices", async () => {
    await assertSucceeds(updateDoc(doc(owner(env), path), {sellPrice: 4000}));
  });

  it("lets a cashier move stock but not change prices or names", async () => {
    const db = cashier(env);
    await assertSucceeds(updateDoc(doc(db, path), {stock: increment(-2)}));
    await assertFails(updateDoc(doc(db, path), {sellPrice: 1}));
    await assertFails(updateDoc(doc(db, path), {name: "Lain"}));
    await assertFails(updateDoc(doc(db, path), {stock: increment(-1), sellPrice: 1}));
  });

  it("keeps the calculated reorder figures server-owned", async () => {
    await assertFails(updateDoc(doc(owner(env), path), {computed: {rop: 0}}));
    await assertFails(setDoc(doc(owner(env), `warungs/${WARUNG}/products/x`),
      {...product, computed: {rop: 1}}));
  });

  it("can never be deleted", async () => {
    await assertFails(deleteDoc(doc(owner(env), path)));
    await assertFails(deleteDoc(doc(cashier(env), path)));
  });
});
