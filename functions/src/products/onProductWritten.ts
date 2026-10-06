import {DocumentSnapshot, FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

import {searchPrefixes, slugify} from "../catalog/text";
import {ProductState, stockAlert} from "../notifications/alerts";
import {notifyOwner} from "../notifications/send";

/**
 * Links a warung's product to the shared catalog so the same item can be
 * recognised across warungs.
 *
 * Products are created on the phone, possibly offline, so the link is made
 * here once the write reaches the server. A match is looked up by barcode
 * first, then by name; a catalog entry is created when there is none.
 */
async function linkToCatalog(after: DocumentSnapshot): Promise<void> {
  const product = after.data() ?? {};
  // Already linked. This also stops the loop caused by the update below.
  if (product.catalogId) return;

  const name = typeof product.name === "string" ? product.name.trim() : "";
  const slug = slugify(name);
  if (!slug) return;
  const barcode = typeof product.barcode === "string" && product.barcode ?
    product.barcode : null;

  const db = getFirestore();
  const catalog = db.collection("catalog");
  let catalogId: string | null = null;

  if (barcode) {
    const byBarcode = await catalog
      .where("barcodes", "array-contains", barcode).limit(1).get();
    if (!byBarcode.empty) catalogId = byBarcode.docs[0].id;
  }
  if (!catalogId) {
    const entry = catalog.doc(slug);
    catalogId = await db.runTransaction(async (tx) => {
      const existing = await tx.get(entry);
      if (existing.exists) {
        // The catalog learns a barcode the first time a warung scans it.
        if (barcode) tx.update(entry, {barcodes: FieldValue.arrayUnion(barcode)});
      } else {
        tx.set(entry, {
          name,
          slug,
          category: typeof product.category === "string" ? product.category : null,
          barcodes: barcode ? [barcode] : [],
          prefixes: searchPrefixes(name),
          source: "warung",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      return entry.id;
    });
  }

  // Does not touch updatedAt: the link is not a change the phones need to
  // re-read for stock or prices.
  await after.ref.update({catalogId});
}

/** Notifies the owner the moment a product becomes low or runs out. */
async function alertOnStockChange(
  before: DocumentSnapshot | undefined, after: DocumentSnapshot,
): Promise<void> {
  const previous = before?.exists ? before.data() as ProductState : undefined;
  const current = after.data() as ProductState;
  // Cheap exit for the common case: most writes do not change the status.
  if (!stockAlert(previous, current, false)) return;

  const warung = after.ref.parent.parent!;
  const info = await warung.get();
  const ownerUid = info.get("ownerUid") as string | undefined;
  if (!ownerUid) return;
  const alert = stockAlert(previous, current, info.get("showOnMap") === true);
  if (alert) await notifyOwner(warung, ownerUid, alert, {productId: after.id});
}

export const onProductWritten = onDocumentWritten(
  "warungs/{wid}/products/{pid}",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    await linkToCatalog(after);
    await alertOnStockChange(event.data?.before, after);
  },
);
