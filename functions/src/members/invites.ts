import {randomInt} from "node:crypto";

import {Auth} from "firebase-admin/auth";
import {FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

// Letters and digits that are hard to mix up when read aloud or typed:
// no 0/O, 1/I/L.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 6;
const VALID_FOR_HOURS = 24;

export function newInviteCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

/** Tidies what a person typed: trims, uppercases, drops spaces and dashes. */
export function normalizeCode(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.toUpperCase().replace(/[\s-]/g, "");
}

export interface Caller {
  uid: string;
  name?: string | null;
  email?: string | null;
  photoURL?: string | null;
  /** Custom claims of the caller's ID token. */
  wid?: string;
  role?: string;
}

function requireOwner(caller: Caller): string {
  if (!caller.wid || caller.role !== "owner") {
    throw new HttpsError("permission-denied", "Hanya pemilik warung yang bisa mengatur kasir.");
  }
  return caller.wid;
}

/** Creates a one-time code a cashier can use to join the owner's warung. */
export async function createInvite(
  db: Firestore, caller: Caller, now: Date,
): Promise<{code: string; expiresAt: number}> {
  const warungId = requireOwner(caller);
  const warung = await db.doc(`warungs/${warungId}`).get();
  const expiresAt = new Date(now.getTime() + VALID_FOR_HOURS * 3600 * 1000);

  // A clash is very unlikely (31^6 codes), but a code must never be reused
  // while an older invite with it is still around.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newInviteCode();
    try {
      await db.doc(`invites/${code}`).create({
        warungId,
        warungName: warung.get("name") ?? "",
        createdByUid: caller.uid,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromDate(expiresAt),
        usedByUid: null,
      });
      return {code, expiresAt: expiresAt.getTime()};
    } catch (error) {
      if ((error as {code?: number}).code !== 6) throw error; // 6 = ALREADY_EXISTS
    }
  }
  throw new HttpsError("unavailable", "Gagal membuat kode. Coba lagi.");
}

/**
 * Makes the caller a cashier of the warung the code belongs to.
 *
 * The membership, the profile and the used mark are written in one
 * transaction, so a code cannot be used twice even when two phones try at
 * the same moment. The claims that unlock the warung data are set after.
 */
export async function acceptInvite(
  db: Firestore, auth: Auth, caller: Caller, rawCode: unknown, now: Date,
): Promise<{warungId: string; warungName: string}> {
  const code = normalizeCode(rawCode);
  if (code.length !== CODE_LENGTH) {
    throw new HttpsError("invalid-argument", "Kode undangan terdiri dari 6 huruf atau angka.");
  }
  const inviteRef = db.doc(`invites/${code}`);
  const userRef = db.doc(`users/${caller.uid}`);

  const joined = await db.runTransaction(async (tx) => {
    const [invite, user] = await Promise.all([tx.get(inviteRef), tx.get(userRef)]);
    if (!invite.exists) {
      throw new HttpsError("not-found", "Kode undangan tidak ditemukan. Cek lagi kodenya.");
    }
    if (invite.get("usedByUid")) {
      throw new HttpsError("failed-precondition", "Kode undangan ini sudah dipakai.");
    }
    if ((invite.get("expiresAt") as Timestamp).toMillis() < now.getTime()) {
      throw new HttpsError(
        "deadline-exceeded", "Kode undangan sudah kedaluwarsa. Minta kode baru ke pemilik.");
    }
    if (user.get("warungId")) {
      throw new HttpsError("already-exists", "Akun ini sudah terhubung ke satu warung.");
    }

    const warungId = invite.get("warungId") as string;
    tx.set(db.doc(`warungs/${warungId}/members/${caller.uid}`), {
      role: "cashier",
      displayName: caller.name ?? null,
      email: caller.email ?? null,
      photoURL: caller.photoURL ?? null,
      joinedAt: FieldValue.serverTimestamp(),
    });
    tx.set(userRef, {
      warungId, role: "cashier", mode: "warung", updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.update(inviteRef, {usedByUid: caller.uid, usedAt: FieldValue.serverTimestamp()});
    return {warungId, warungName: (invite.get("warungName") as string) ?? ""};
  });

  await auth.setCustomUserClaims(caller.uid, {wid: joined.warungId, role: "cashier"});
  // Tells the app that new claims are ready, so it refreshes its ID token.
  await userRef.set({claimsUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return joined;
}

/**
 * Removes a cashier from the owner's warung. Their claims are cleared and
 * their sessions revoked, so access ends as soon as their token is refreshed
 * (within the hour at the latest).
 */
export async function removeMember(
  db: Firestore, auth: Auth, caller: Caller, memberUid: unknown,
): Promise<void> {
  const warungId = requireOwner(caller);
  if (typeof memberUid !== "string" || memberUid.length === 0) {
    throw new HttpsError("invalid-argument", "Kasir tidak dikenal.");
  }
  if (memberUid === caller.uid) {
    throw new HttpsError("failed-precondition", "Pemilik tidak bisa mengeluarkan dirinya sendiri.");
  }
  const memberRef = db.doc(`warungs/${warungId}/members/${memberUid}`);
  const member = await memberRef.get();
  if (!member.exists || member.get("role") !== "cashier") {
    throw new HttpsError("not-found", "Kasir tidak ditemukan di warung ini.");
  }

  const batch = db.batch();
  batch.delete(memberRef);
  batch.set(db.doc(`users/${memberUid}`), {
    warungId: FieldValue.delete(),
    role: FieldValue.delete(),
    claimsUpdatedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();

  await auth.setCustomUserClaims(memberUid, {});
  await auth.revokeRefreshTokens(memberUid);
}
