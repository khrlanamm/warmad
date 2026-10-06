import {DocumentReference, FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

import {publicItemOf, publicWarungOf, WarungDoc} from "./projection";

async function commitInChunks(db: Firestore, writes: Array<(batch: FirebaseFirestore.WriteBatch) => void>) {
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    writes.slice(i, i + 400).forEach((write) => write(batch));
    await batch.commit();
  }
}

/**
 * Brings the public copy of one warung in line with its private data:
 * creates or refreshes it when the owner shows the warung on the map, and
 * removes every trace when they do not.
 */
export async function syncPublicWarung(db: Firestore, warung: DocumentReference): Promise<void> {
  const publicRef = db.doc(`publicWarungs/${warung.id}`);
  const face = publicWarungOf((await warung.get()).data() as WarungDoc | undefined);
  const existing = await publicRef.collection("items").select().get();
  const writes: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];

  if (face === null) {
    existing.docs.forEach((doc) => writes.push((batch) => batch.delete(doc.ref)));
    writes.push((batch) => batch.delete(publicRef));
    await commitInChunks(db, writes);
    return;
  }

  const products = await warung.collection("products").get();
  const wanted = new Set<string>();
  for (const product of products.docs) {
    const item = publicItemOf(product.data());
    if (!item) continue;
    const catalogId = product.get("catalogId") as string;
    wanted.add(catalogId);
    writes.push((batch) => batch.set(
      publicRef.collection("items").doc(catalogId),
      {...item, updatedAt: FieldValue.serverTimestamp()}));
  }
  existing.docs.filter((doc) => !wanted.has(doc.id))
    .forEach((doc) => writes.push((batch) => batch.delete(doc.ref)));
  writes.push((batch) => batch.set(publicRef, {
    ...face, itemCount: wanted.size, lastActiveAt: FieldValue.serverTimestamp(),
  }, {merge: true}));
  await commitInChunks(db, writes);
}

/**
 * Keeps the public copy in step when the owner edits the warung or flips
 * the "show on map" switch.
 */
export const onWarungWritten = onDocumentWritten("warungs/{wid}", async (event) => {
  const before = publicWarungOf(event.data?.before.data() as WarungDoc | undefined);
  const after = publicWarungOf(event.data?.after.data() as WarungDoc | undefined);
  // Most warung edits (reminder time and so on) change nothing public.
  if (JSON.stringify(before) === JSON.stringify(after)) return;
  const ref = event.data?.after.ref ?? event.data?.before.ref;
  if (ref) await syncPublicWarung(getFirestore(), ref);
});
