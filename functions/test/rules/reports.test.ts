import {
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {afterAll, beforeAll, beforeEach, describe, it} from "vitest";

import {anonymous, buyer, cashier, createTestEnv, OTHER_WARUNG, owner, WARUNG} from "./setup";

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

describe("public copies", () => {
  const paths = [`publicWarungs/${WARUNG}`, `publicWarungs/${WARUNG}/items/indomie-goreng`];
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), paths[0]), {name: "Warung Barokah"});
      await setDoc(doc(ctx.firestore(), paths[1]), {name: "Indomie Goreng", status: "tersedia"});
    });
  });

  it("can be read by any signed in user", async () => {
    for (const path of paths) {
      await assertSucceeds(getDoc(doc(buyer(env), path)));
      await assertSucceeds(getDoc(doc(cashier(env), path)));
    }
  });

  it("cannot be read when signed out", async () => {
    for (const path of paths) await assertFails(getDoc(doc(anonymous(env), path)));
  });

  it("cannot be written by anyone, not even the warung's owner", async () => {
    for (const path of paths) {
      await assertFails(setDoc(doc(owner(env), path), {status: "tersedia"}));
      await assertFails(updateDoc(doc(owner(env), path), {name: "Lain"}));
      await assertFails(deleteDoc(doc(owner(env), path)));
    }
  });

  it("gives a buyer no way into the private warung data", async () => {
    for (const path of [
      `warungs/${WARUNG}`, `warungs/${WARUNG}/products/indomie`,
      `warungs/${WARUNG}/sales/s1`, `warungs/${WARUNG}/cash/current`,
      `warungs/${WARUNG}/cashClosings/1`, `warungs/${WARUNG}/cashMoves/m1`,
      `warungs/${WARUNG}/members/owner`, `warungs/${WARUNG}/customers/c1`,
      `warungs/${WARUNG}/suppliers/s1`, `warungs/${WARUNG}/dailySummaries/2026-10-06`,
      `warungs/${WARUNG}/notifications/n1`,
    ]) {
      await assertFails(getDoc(doc(buyer(env), path)));
    }
  });
});

describe("notifications", () => {
  const path = `warungs/${WARUNG}/notifications/n1`;
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), {title: "Aqua habis", read: false});
    });
  });

  it("can be read and marked as read by the owner only", async () => {
    await assertSucceeds(getDoc(doc(owner(env), path)));
    await assertSucceeds(updateDoc(doc(owner(env), path), {read: true}));
    await assertFails(getDoc(doc(cashier(env), path)));
    await assertFails(getDoc(doc(buyer(env), path)));
  });

  it("cannot be rewritten, unread again, created or deleted by the owner", async () => {
    await assertFails(updateDoc(doc(owner(env), path), {title: "Lain"}));
    await assertFails(updateDoc(doc(owner(env), path), {read: false, title: "x"}));
    await assertFails(setDoc(doc(owner(env), `warungs/${WARUNG}/notifications/n2`), {title: "x"}));
    await assertFails(deleteDoc(doc(owner(env), path)));
  });
});

describe("push tokens", () => {
  const device = {token: "abc", platform: "android"};

  it("can be saved and removed by their own account only", async () => {
    await assertSucceeds(setDoc(doc(buyer(env), "users/buyer/devices/abc"), device));
    await assertSucceeds(deleteDoc(doc(buyer(env), "users/buyer/devices/abc")));
    await assertFails(setDoc(doc(buyer(env), "users/owner/devices/abc"), device));
    await assertFails(getDoc(doc(buyer(env), "users/owner/devices/abc")));
  });

  it("reject anything but a token", async () => {
    await assertFails(setDoc(doc(buyer(env), "users/buyer/devices/x"), {token: 1}));
    await assertFails(setDoc(doc(buyer(env), "users/buyer/devices/x"), {...device, role: "owner"}));
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
