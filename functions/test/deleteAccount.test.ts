import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {beforeEach, describe, expect, it} from "vitest";

import {deleteAccountData} from "../src/account/deleteAccount";

// Runs against the Firestore and Auth emulators (`npm run test:rules`).
const PROJECT = "demo-warmad";
if (getApps().length === 0) initializeApp({projectId: PROJECT});
const db = getFirestore();
const auth = getAuth();

async function exists(path: string) {
  return (await db.doc(path).get()).exists;
}
async function userExists(uid: string) {
  return auth.getUser(uid).then(() => true, () => false);
}

beforeEach(async () => {
  await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    {method: "DELETE"});
  await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/accounts`,
    {method: "DELETE"});

  for (const uid of ["owner", "rudi", "buyer", "other"]) await auth.createUser({uid});
  await auth.setCustomUserClaims("owner", {wid: "w1", role: "owner"});
  await auth.setCustomUserClaims("rudi", {wid: "w1", role: "cashier"});
  await auth.setCustomUserClaims("other", {wid: "w2", role: "owner"});

  await db.doc("users/owner").set({warungId: "w1", role: "owner"});
  await db.doc("users/owner/devices/t1").set({token: "t1"});
  await db.doc("users/rudi").set({warungId: "w1", role: "cashier"});
  await db.doc("users/buyer").set({mode: "pembeli"});
  await db.doc("users/buyer/devices/t2").set({token: "t2"});
  await db.doc("users/other").set({warungId: "w2", role: "owner"});

  await db.doc("warungs/w1").set({name: "Warung Barokah", ownerUid: "owner"});
  await db.doc("warungs/w1/members/owner").set({role: "owner"});
  await db.doc("warungs/w1/members/rudi").set({role: "cashier"});
  await db.doc("warungs/w1/sales/s1").set({total: 8000, cashierUid: "rudi"});
  await db.doc("warungs/w1/products/aqua").set({name: "Aqua"});
  await db.doc("warungs/w1/cash/current").set({seq: 1});
  await db.doc("publicWarungs/w1").set({name: "Warung Barokah"});
  await db.doc("publicWarungs/w1/items/aqua").set({status: "tersedia"});
  await db.doc("invites/ABC234").set({warungId: "w1"});

  await db.doc("warungs/w2").set({name: "Toko Madura Jaya", ownerUid: "other"});
  await db.doc("warungs/w2/sales/s9").set({total: 1000});
  await db.doc("publicWarungs/w2").set({name: "Toko Madura Jaya"});
});

describe("deleting a buyer's account", () => {
  it("removes the profile, the push tokens and the sign-in", async () => {
    await deleteAccountData(db, auth, "buyer");
    expect(await exists("users/buyer")).toBe(false);
    expect(await exists("users/buyer/devices/t2")).toBe(false);
    expect(await userExists("buyer")).toBe(false);
  });

  it("touches nobody else", async () => {
    await deleteAccountData(db, auth, "buyer");
    expect(await exists("users/owner")).toBe(true);
    expect(await exists("warungs/w1/sales/s1")).toBe(true);
    expect(await userExists("owner")).toBe(true);
  });
});

describe("deleting a cashier's account", () => {
  it("removes the cashier but keeps the warung's records", async () => {
    await deleteAccountData(db, auth, "rudi");
    expect(await exists("users/rudi")).toBe(false);
    expect(await exists("warungs/w1/members/rudi")).toBe(false);
    expect(await userExists("rudi")).toBe(false);
    // The sale Rudi recorded is part of the warung's books.
    expect(await exists("warungs/w1/sales/s1")).toBe(true);
    expect(await exists("warungs/w1")).toBe(true);
    expect(await exists("warungs/w1/members/owner")).toBe(true);
  });
});

describe("deleting an owner's account", () => {
  it("removes the warung, everything in it and its public copy", async () => {
    await deleteAccountData(db, auth, "owner");
    for (const path of [
      "users/owner", "users/owner/devices/t1", "warungs/w1", "warungs/w1/members/owner",
      "warungs/w1/sales/s1", "warungs/w1/products/aqua", "warungs/w1/cash/current",
      "publicWarungs/w1", "publicWarungs/w1/items/aqua", "invites/ABC234",
    ]) {
      expect(await exists(path), path).toBe(false);
    }
    expect(await userExists("owner")).toBe(false);
  });

  it("takes access away from the warung's cashiers but keeps their accounts", async () => {
    await deleteAccountData(db, auth, "owner");
    expect(await userExists("rudi")).toBe(true);
    expect((await auth.getUser("rudi")).customClaims ?? {}).toEqual({});
    const profile = (await db.doc("users/rudi").get()).data()!;
    expect(profile.warungId).toBeUndefined();
    expect(profile.role).toBeUndefined();
    expect(profile.claimsUpdatedAt).toBeTruthy();
  });

  it("leaves other warungs alone", async () => {
    await deleteAccountData(db, auth, "owner");
    expect(await exists("warungs/w2")).toBe(true);
    expect(await exists("warungs/w2/sales/s9")).toBe(true);
    expect(await exists("publicWarungs/w2")).toBe(true);
    expect((await auth.getUser("other")).customClaims).toEqual({wid: "w2", role: "owner"});
  });
});
