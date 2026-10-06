import {
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc} from "firebase/firestore";
import {afterAll, beforeAll, beforeEach, describe, it} from "vitest";

import {buyer, cashier, createTestEnv, OTHER_WARUNG, owner, WARUNG} from "./setup";

let env: RulesTestEnvironment;

const paths = [
  `warungs/${WARUNG}/dailySummaries/2026-10-06`,
  `warungs/${WARUNG}/dailyProductSales/2026-10-06`,
];

beforeAll(async () => {
  env = await createTestEnv();
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const path of paths) await setDoc(doc(ctx.firestore(), path), {salesCash: 31000});
  });
});

describe("report documents", () => {
  it("can be read by the owner", async () => {
    for (const path of paths) await assertSucceeds(getDoc(doc(owner(env), path)));
  });

  it("are hidden from cashiers, buyers and other warungs", async () => {
    for (const path of paths) {
      await assertFails(getDoc(doc(cashier(env), path)));
      await assertFails(getDoc(doc(buyer(env), path)));
      await assertFails(getDoc(doc(owner(env, OTHER_WARUNG), path)));
    }
  });

  it("cannot be written by anyone, including the owner", async () => {
    for (const path of paths) {
      await assertFails(setDoc(doc(owner(env), path), {salesCash: 0}));
    }
  });
});
