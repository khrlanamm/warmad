import {Auth, getAuth} from "firebase-admin/auth";
import {FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

/**
 * Deletes the caller's account and the data that belongs to it. Google Play
 * requires that an app with accounts lets people do this.
 *
 * - A buyer: their profile and push tokens.
 * - A cashier: the same, plus their membership. What they recorded stays in
 *   the warung; it belongs to the warung's books.
 * - An owner: the same, plus the whole warung with every record in it, its
 *   public copy, and the access of all its cashiers.
 */
export async function deleteAccountData(db: Firestore, auth: Auth, uid: string): Promise<void> {
  const userRef = db.doc(`users/${uid}`);
  const profile = await userRef.get();
  const warungId = profile.get("warungId") as string | undefined;
  const role = profile.get("role") as string | undefined;

  if (warungId && role === "owner") {
    const warung = db.doc(`warungs/${warungId}`);
    const members = await warung.collection("members").get();
    for (const member of members.docs) {
      if (member.id === uid) continue;
      // Cashiers lose access before the data they could read disappears.
      await auth.setCustomUserClaims(member.id, {});
      await auth.revokeRefreshTokens(member.id);
      await db.doc(`users/${member.id}`).set({
        warungId: FieldValue.delete(),
        role: FieldValue.delete(),
        claimsUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    const invites = await db.collection("invites").where("warungId", "==", warungId).get();
    await Promise.all(invites.docs.map((invite) => invite.ref.delete()));
    await db.recursiveDelete(db.doc(`publicWarungs/${warungId}`));
    await db.recursiveDelete(warung);
  } else if (warungId) {
    await db.doc(`warungs/${warungId}/members/${uid}`).delete();
  }

  // Includes the push tokens underneath the profile.
  await db.recursiveDelete(userRef);
  await auth.deleteUser(uid);
}

export const deleteAccount = onCall({timeoutSeconds: 300}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Masuk dulu.");
  await deleteAccountData(getFirestore(), getAuth(), request.auth.uid);
  return {ok: true};
});
