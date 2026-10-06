// Adds demo products to the warung owned by one account.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/seedWarungProducts.mjs owner@example.com
//
// Safe to run again: products the warung already has (matched by name) are
// left alone, so stock that changed through real use is never overwritten.
import {readFileSync} from "node:fs";
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
const {slugify} = require("../lib/catalog/text.js");

const email = process.argv[2];
if (!email) {
  console.error("Usage: node functions/scripts/seedWarungProducts.mjs <owner email>");
  process.exit(1);
}

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const db = getFirestore();

const user = await getAuth().getUserByEmail(email);
const warungId = (await db.doc(`users/${user.uid}`).get()).get("warungId");
if (!warungId) {
  console.error(`${email} has no warung yet. Register one in the app first.`);
  process.exit(1);
}

const items = JSON.parse(
  readFileSync(new URL("./data/catalog.json", import.meta.url), "utf8"));
const products = db.collection(`warungs/${warungId}/products`);
const existing = new Set(
  (await products.get()).docs.map((doc) => slugify(doc.get("name") ?? "")));

// Deterministic stock levels so every run of a fresh warung looks the same:
// most items comfortably stocked, some low, a few empty.
function stockFor(index, reorderPoint) {
  if (index % 23 === 4) return 0;
  if (index % 7 === 3) return Math.max(1, Math.floor(reorderPoint * 0.6));
  return reorderPoint + 4 + ((index * 37) % (reorderPoint * 3 + 5));
}

const batch = db.batch();
let added = 0;
items.forEach((item, index) => {
  const slug = slugify(item.name);
  if (existing.has(slug)) return;
  const reorderPoint = Math.min(30, Math.max(3, Math.round(item.packSize * 0.5)));
  batch.set(products.doc(slug), {
    name: item.name,
    category: item.category,
    barcode: null,
    catalogId: slug,
    unit: "pcs",
    pack: item.packSize > 1 ? {name: item.packName, size: item.packSize} : null,
    sellPrice: item.sellPrice,
    lastBuyPrice: item.buyPrice,
    stock: stockFor(index, reorderPoint),
    manualRop: reorderPoint,
    manualOrderQty: item.packSize > 1 ? item.packSize : null,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  added++;
});
await batch.commit();
console.log(`Added ${added} products to warung ${warungId} (${existing.size} already there).`);
