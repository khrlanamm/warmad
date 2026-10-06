import {getFirestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {closingAlert, ClosingState, reminderSlot} from "./alerts";
import {notifyOwner} from "./send";

/** Tells the owner about a closing with a difference, or closed by a cashier. */
export const onCashClosingCreated = onDocumentCreated(
  "warungs/{wid}/cashClosings/{closingId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const warung = snapshot.ref.parent.parent!;
    const ownerUid = (await warung.get()).get("ownerUid") as string | undefined;
    if (!ownerUid) return;

    const alert = closingAlert(snapshot.data() as ClosingState, ownerUid);
    if (alert) await notifyOwner(warung, ownerUid, alert, {closingId: snapshot.id});
  },
);

/**
 * Reminds owners to close the cash at the time they picked. Runs every
 * quarter of an hour and only looks at warungs whose reminder is that slot.
 */
export const cashClosingReminder = onSchedule(
  {schedule: "*/15 * * * *", timeZone: "Asia/Jakarta"},
  async () => {
    const slot = reminderSlot(new Date());
    const warungs = await getFirestore().collection("warungs")
      .where("cashReminderTime", "==", slot).select("ownerUid").get();
    for (const warung of warungs.docs) {
      try {
        await notifyOwner(warung.ref, warung.get("ownerUid"), {
          type: "closingReminder",
          title: "Waktunya tutup kas",
          body: "Hitung uang di laci dan cocokkan dengan catatan hari ini.",
        });
      } catch (error) {
        logger.error("Closing reminder failed", {warung: warung.id, error});
      }
    }
  },
);
