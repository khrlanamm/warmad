// Fills the shared `catalog` collection with common warung goods.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/seedCatalog.mjs
//
// Safe to run again: entries are keyed by their name slug and merged.
// Barcodes are deliberately not seeded. The catalog learns a barcode the
// first time a warung scans the item.
import {readFileSync} from "node:fs";
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
// Same helpers the Cloud Functions use, so seeded and app-created entries
// get identical keys.
const {searchPrefixes, slugify} = require("../lib/catalog/text.js");

const items = JSON.parse(
  readFileSync(new URL("./data/catalog.json", import.meta.url), "utf8"));

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const db = getFirestore();

const batch = db.batch();
for (const item of items) {
  const slug = slugify(item.name);
  batch.set(db.collection("catalog").doc(slug), {
    name: item.name,
    slug,
    category: item.category,
    prefixes: searchPrefixes(item.name),
    packName: item.packName,
    packSize: item.packSize,
    source: "seed",
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}
await batch.commit();
console.log(`Seeded ${items.length} catalog entries.`);
