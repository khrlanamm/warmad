import {DocumentReference, FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {logger} from "firebase-functions/v2";

import {Alert} from "./alerts";

/**
 * Puts an alert in the warung's notification list and pushes it to the
 * owner's phones. The list is what the app shows; the push is best effort.
 */
export async function notifyOwner(
  warung: DocumentReference, ownerUid: string, alert: Alert,
  extra: Record<string, string> = {},
): Promise<void> {
  await warung.collection("notifications").add({
    ...alert, ...extra, read: false, createdAt: FieldValue.serverTimestamp(),
  });

  const devices = await getFirestore().collection(`users/${ownerUid}/devices`).get();
  const tokens = devices.docs.map((doc) => doc.get("token") as string).filter(Boolean);
  if (tokens.length === 0) return;

  const result = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {title: alert.title, body: alert.body},
    data: {type: alert.type, warungId: warung.id, ...extra},
    android: {priority: "high"},
  });
  // Forget tokens of phones that uninstalled the app or signed out.
  await Promise.all(result.responses.map((response, index) => {
    const code = response.error?.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") {
      return devices.docs[index].ref.delete();
    }
    if (response.error) logger.warn("Push failed", {code});
    return null;
  }));
}
