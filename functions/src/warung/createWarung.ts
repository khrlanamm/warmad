import {getAuth} from "firebase-admin/auth";
import {FieldValue, GeoPoint, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {encodeGeohash} from "../geo";
import {parseCreateWarungInput} from "./input";

/**
 * Registers a warung for the calling account and makes the caller its owner.
 *
 * This runs on the server because it grants the `wid` and `role` custom
 * claims that every Security Rule for warung data depends on.
 */
export const createWarung = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Masuk dulu untuk mendaftarkan warung.");
  }
  const uid = request.auth.uid;
  const input = parseCreateWarungInput(request.data);

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const warungRef = db.collection("warungs").doc();
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (user.get("warungId")) {
      throw new HttpsError("already-exists", "Akun ini sudah terhubung ke satu warung.");
    }

    tx.set(warungRef, {
      name: input.name,
      phone: input.phone,
      address: input.address,
      location: new GeoPoint(input.lat, input.lng),
      geohash: encodeGeohash(input.lat, input.lng),
      hours: input.hours,
      showOnMap: input.showOnMap,
      ownerUid: uid,
      cashReminderTime: null,
      createdAt: now,
      updatedAt: now,
    });
    tx.set(warungRef.collection("members").doc(uid), {
      role: "owner",
      displayName: request.auth?.token.name ?? null,
      email: request.auth?.token.email ?? null,
      photoURL: request.auth?.token.picture ?? null,
      joinedAt: now,
    });
    // Running counters for the open cash period. See the cash rules in the plan.
    tx.set(warungRef.collection("cash").doc("current"), {
      seq: 1,
      openedAt: now,
      openingBalance: input.openingBalance,
      salesCash: 0,
      debtCollected: 0,
      purchasesCash: 0,
      expenses: 0,
      prive: 0,
      salesCount: 0,
    });
    tx.set(userRef, {
      warungId: warungRef.id,
      role: "owner",
      mode: "warung",
      updatedAt: now,
    }, {merge: true});
  });

  await getAuth().setCustomUserClaims(uid, {wid: warungRef.id, role: "owner"});
  // Tells the app that new claims are ready, so it refreshes its ID token.
  await userRef.set({claimsUpdatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return {warungId: warungRef.id};
});
