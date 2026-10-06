import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {beforeAll, beforeEach, describe, expect, it} from "vitest";

import {
  acceptInvite, Caller, CODE_LENGTH, createInvite, newInviteCode, normalizeCode,
  removeMember,
} from "../src/members/invites";

// These run against the Firestore and Auth emulators started by
// `npm run test:rules`. They exercise the real transactions and claims.
const PROJECT = "demo-warmad";
if (getApps().length === 0) initializeApp({projectId: PROJECT});
const db = getFirestore();
const auth = getAuth();

const owner: Caller = {uid: "owner", name: "Pak Ahmad", wid: "w1", role: "owner"};
const rudi: Caller = {uid: "rudi", name: "Rudi", email: "rudi@example.com"};
const siti: Caller = {uid: "siti", name: "Siti"};
const now = new Date("2026-10-06T12:00:00Z");

async function clear() {
  await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    {method: "DELETE"});
  await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/accounts`,
    {method: "DELETE"});
}

beforeAll(() => {
  expect(process.env.FIRESTORE_EMULATOR_HOST, "Firestore emulator must be running").toBeTruthy();
  expect(process.env.FIREBASE_AUTH_EMULATOR_HOST, "Auth emulator must be running").toBeTruthy();
});

beforeEach(async () => {
  await clear();
  for (const uid of ["owner", "rudi", "siti"]) await auth.createUser({uid});
  await db.doc("warungs/w1").set({name: "Warung Barokah", ownerUid: "owner"});
  await db.doc("warungs/w1/members/owner").set({role: "owner"});
  await db.doc("users/owner").set({warungId: "w1", role: "owner"});
});

describe("invite codes", () => {
  it("are six characters without look-alike letters or digits", () => {
    for (let i = 0; i < 200; i++) {
      const code = newInviteCode();
      expect(code).toHaveLength(CODE_LENGTH);
      expect(code).toMatch(/^[A-HJKMNP-Z2-9]+$/);
    }
  });

  it("are tidied before lookup", () => {
    expect(normalizeCode(" ab-c 23d ")).toBe("ABC23D");
    expect(normalizeCode(undefined)).toBe("");
  });
});

describe("createInvite", () => {
  it("gives the owner a code that lasts 24 hours", async () => {
    const {code, expiresAt} = await createInvite(db, owner, now);
    expect(expiresAt - now.getTime()).toBe(24 * 3600 * 1000);
    const invite = await db.doc(`invites/${code}`).get();
    expect(invite.get("warungId")).toBe("w1");
    expect(invite.get("warungName")).toBe("Warung Barokah");
    expect(invite.get("usedByUid")).toBeNull();
  });

  it("is refused for a cashier and for an account without a warung", async () => {
    await expect(createInvite(db, {...rudi, wid: "w1", role: "cashier"}, now))
      .rejects.toMatchObject({code: "permission-denied"});
    await expect(createInvite(db, rudi, now)).rejects.toMatchObject({code: "permission-denied"});
  });
});

describe("acceptInvite", () => {
  it("makes the caller a cashier with matching claims", async () => {
    const {code} = await createInvite(db, owner, now);
    const joined = await acceptInvite(db, auth, rudi, code.toLowerCase(), now);
    expect(joined).toEqual({warungId: "w1", warungName: "Warung Barokah"});

    expect((await db.doc("warungs/w1/members/rudi").get()).data())
      .toMatchObject({role: "cashier", displayName: "Rudi", email: "rudi@example.com"});
    expect((await db.doc("users/rudi").get()).data())
      .toMatchObject({warungId: "w1", role: "cashier", mode: "warung"});
    expect((await auth.getUser("rudi")).customClaims).toEqual({wid: "w1", role: "cashier"});
    expect((await db.doc("users/rudi").get()).get("claimsUpdatedAt")).toBeTruthy();
  });

  it("cannot be used twice", async () => {
    const {code} = await createInvite(db, owner, now);
    await acceptInvite(db, auth, rudi, code, now);
    await expect(acceptInvite(db, auth, siti, code, now))
      .rejects.toMatchObject({code: "failed-precondition"});
    expect((await db.doc("warungs/w1/members/siti").get()).exists).toBe(false);
    expect((await auth.getUser("siti")).customClaims ?? {}).toEqual({});
  });

  it("lets only one of two phones win the same code", async () => {
    const {code} = await createInvite(db, owner, now);
    const results = await Promise.allSettled([
      acceptInvite(db, auth, rudi, code, now),
      acceptInvite(db, auth, siti, code, now),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const members = await db.collection("warungs/w1/members").get();
    expect(members.docs.filter((d) => d.get("role") === "cashier")).toHaveLength(1);
  });

  it("is refused once the code has expired", async () => {
    const {code} = await createInvite(db, owner, now);
    const later = new Date(now.getTime() + 25 * 3600 * 1000);
    await expect(acceptInvite(db, auth, rudi, code, later))
      .rejects.toMatchObject({code: "deadline-exceeded"});
  });

  it("is refused for an unknown or malformed code", async () => {
    await expect(acceptInvite(db, auth, rudi, "ZZZZZZ", now))
      .rejects.toMatchObject({code: "not-found"});
    await expect(acceptInvite(db, auth, rudi, "ABC", now))
      .rejects.toMatchObject({code: "invalid-argument"});
    await expect(acceptInvite(db, auth, rudi, null, now))
      .rejects.toMatchObject({code: "invalid-argument"});
  });

  it("is refused for an account that already belongs to a warung", async () => {
    const {code} = await createInvite(db, owner, now);
    await expect(acceptInvite(db, auth, owner, code, now))
      .rejects.toMatchObject({code: "already-exists"});
    // The code is still good for someone else.
    await expect(acceptInvite(db, auth, rudi, code, now)).resolves.toBeTruthy();
  });
});

describe("removeMember", () => {
  beforeEach(async () => {
    const {code} = await createInvite(db, owner, now);
    await acceptInvite(db, auth, rudi, code, now);
  });

  it("removes the cashier, clears their claims and revokes their sessions", async () => {
    const before = (await auth.getUser("rudi")).tokensValidAfterTime;
    await new Promise((resolve) => setTimeout(resolve, 1100));
    await removeMember(db, auth, owner, "rudi");

    expect((await db.doc("warungs/w1/members/rudi").get()).exists).toBe(false);
    const profile = (await db.doc("users/rudi").get()).data()!;
    expect(profile.warungId).toBeUndefined();
    expect(profile.role).toBeUndefined();
    const user = await auth.getUser("rudi");
    expect(user.customClaims ?? {}).toEqual({});
    expect(new Date(user.tokensValidAfterTime!).getTime())
      .toBeGreaterThan(new Date(before ?? 0).getTime());
  });

  it("lets the removed cashier join again with a new code", async () => {
    await removeMember(db, auth, owner, "rudi");
    const {code} = await createInvite(db, owner, now);
    await expect(acceptInvite(db, auth, rudi, code, now)).resolves.toBeTruthy();
  });

  it("is refused for anyone but the owner", async () => {
    await expect(removeMember(db, auth, {...rudi, wid: "w1", role: "cashier"}, "rudi"))
      .rejects.toMatchObject({code: "permission-denied"});
    await expect(removeMember(db, auth, {...owner, wid: "w2"}, "rudi"))
      .rejects.toMatchObject({code: "not-found"});
  });

  it("never removes the owner", async () => {
    await expect(removeMember(db, auth, owner, "owner"))
      .rejects.toMatchObject({code: "failed-precondition"});
    expect((await db.doc("warungs/w1/members/owner").get()).exists).toBe(true);
  });

  it("is refused for someone who is not a member", async () => {
    await expect(removeMember(db, auth, owner, "siti")).rejects.toMatchObject({code: "not-found"});
  });
});

it("keeps an expired invite out of reach by its timestamp", async () => {
  await db.doc("invites/OLDOLD").set({
    warungId: "w1", warungName: "Warung Barokah", usedByUid: null,
    expiresAt: Timestamp.fromDate(new Date(now.getTime() - 1000)),
  });
  await expect(acceptInvite(db, auth, rudi, "OLDOLD", now))
    .rejects.toMatchObject({code: "deadline-exceeded"});
});
