import {
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {afterAll, beforeAll, beforeEach, describe, it} from "vitest";

import {
  anonymous,
  buyer,
  cashier,
  createTestEnv,
  OTHER_WARUNG,
  owner,
  WARUNG,
} from "./setup";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await createTestEnv();
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/owner"), {
      displayName: "Pak Ahmad", mode: "warung", warungId: WARUNG, role: "owner",
    });
    await setDoc(doc(db, `warungs/${WARUNG}`), {
      name: "Warung Barokah", ownerUid: "owner", geohash: "qw8nv", showOnMap: false,
    });
    await setDoc(doc(db, `warungs/${WARUNG}/members/owner`), {role: "owner"});
    await setDoc(doc(db, `warungs/${WARUNG}/cash/current`), {seq: 1, openingBalance: 500000});
    await setDoc(doc(db, `warungs/${OTHER_WARUNG}`), {name: "Toko Madura Jaya"});
  });
});

describe("users", () => {
  const profile = {displayName: "Siti", email: "siti@example.com", photoURL: null, mode: "pembeli"};

  it("lets a user create and read their own profile", async () => {
    const db = buyer(env);
    await assertSucceeds(setDoc(doc(db, "users/buyer"), profile));
    await assertSucceeds(getDoc(doc(db, "users/buyer")));
  });

  it("blocks reading or writing someone else's profile", async () => {
    const db = buyer(env);
    await assertFails(getDoc(doc(db, "users/owner")));
    await assertFails(setDoc(doc(db, "users/owner"), profile));
  });

  it("blocks signed out access", async () => {
    await assertFails(getDoc(doc(anonymous(env), "users/owner")));
  });

  it("blocks a user from granting themselves a warung on create", async () => {
    const db = buyer(env);
    await assertFails(setDoc(doc(db, "users/buyer"), {...profile, warungId: WARUNG, role: "owner"}));
  });

  it("blocks a user from changing their warung or role", async () => {
    const db = owner(env);
    await assertFails(updateDoc(doc(db, "users/owner"), {warungId: OTHER_WARUNG}));
    await assertFails(updateDoc(doc(db, "users/owner"), {role: "cashier"}));
  });

  it("lets a user switch mode but only to a known mode", async () => {
    const db = owner(env);
    await assertSucceeds(updateDoc(doc(db, "users/owner"), {mode: "pembeli"}));
    await assertFails(updateDoc(doc(db, "users/owner"), {mode: "admin"}));
  });
});

describe("warungs", () => {
  it("lets members read their warung, members and cash", async () => {
    for (const db of [owner(env), cashier(env)]) {
      await assertSucceeds(getDoc(doc(db, `warungs/${WARUNG}`)));
      await assertSucceeds(getDoc(doc(db, `warungs/${WARUNG}/members/owner`)));
      await assertSucceeds(getDoc(doc(db, `warungs/${WARUNG}/cash/current`)));
    }
  });

  it("hides every warung document from buyers and other warungs", async () => {
    for (const db of [buyer(env), owner(env, OTHER_WARUNG), anonymous(env)]) {
      await assertFails(getDoc(doc(db, `warungs/${WARUNG}`)));
      await assertFails(getDoc(doc(db, `warungs/${WARUNG}/members/owner`)));
      await assertFails(getDoc(doc(db, `warungs/${WARUNG}/cash/current`)));
    }
  });

  it("lets only the owner change warung settings", async () => {
    await assertSucceeds(updateDoc(doc(owner(env), `warungs/${WARUNG}`), {showOnMap: true}));
    await assertFails(updateDoc(doc(cashier(env), `warungs/${WARUNG}`), {showOnMap: true}));
  });

  it("keeps ownerUid and geohash server-owned", async () => {
    const db = owner(env);
    await assertFails(updateDoc(doc(db, `warungs/${WARUNG}`), {ownerUid: "cashier"}));
    await assertFails(updateDoc(doc(db, `warungs/${WARUNG}`), {geohash: "zzzzz"}));
  });

  it("blocks clients from creating a warung or a membership directly", async () => {
    const db = buyer(env);
    await assertFails(setDoc(doc(db, "warungs/mine"), {name: "Warung Palsu", ownerUid: "buyer"}));
    await assertFails(setDoc(doc(db, `warungs/${WARUNG}/members/buyer`), {role: "owner"}));
  });

  it("blocks direct writes to the cash counters for now", async () => {
    await assertFails(updateDoc(doc(owner(env), `warungs/${WARUNG}/cash/current`), {openingBalance: 0}));
  });
});
