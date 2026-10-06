import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

import * as invites from "./invites";

function callerOf(request: CallableRequest): invites.Caller {
  if (!request.auth) throw new HttpsError("unauthenticated", "Masuk dulu.");
  const token = request.auth.token;
  return {
    uid: request.auth.uid,
    name: token.name,
    email: token.email,
    photoURL: token.picture,
    wid: token.wid,
    role: token.role,
  };
}

/** Owner only: creates a one-time code for a cashier to join. */
export const createInvite = onCall((request) =>
  invites.createInvite(getFirestore(), callerOf(request), new Date()));

/** Any signed in account without a warung: joins with a code as cashier. */
export const acceptInvite = onCall((request) =>
  invites.acceptInvite(
    getFirestore(), getAuth(), callerOf(request), request.data?.code, new Date()));

/** Owner only: removes a cashier. */
export const removeMember = onCall(async (request) => {
  await invites.removeMember(getFirestore(), getAuth(), callerOf(request), request.data?.uid);
  return {ok: true};
});
