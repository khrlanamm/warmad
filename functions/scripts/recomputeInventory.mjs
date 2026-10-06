// Recalculates reorder points and order sizes for one warung right now,
// instead of waiting for the nightly job.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/recomputeInventory.mjs owner@example.com
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

const email = process.argv[2];
if (!email) {
  console.error("Usage: node functions/scripts/recomputeInventory.mjs <owner email>");
  process.exit(1);
}

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
// Loaded after initializeApp: the compiled module reads the default app.
const require = createRequire(import.meta.url);
const {recomputeWarung} = require("../lib/inventory/recompute.js");

const db = getFirestore();
const user = await getAuth().getUserByEmail(email);
const warungId = (await db.doc(`users/${user.uid}`).get()).get("warungId");
if (!warungId) {
  console.error(`${email} has no warung.`);
  process.exit(1);
}
const changed = await recomputeWarung(db, db.doc(`warungs/${warungId}`), new Date());
console.log(`Updated ${changed} product(s) of warung ${warungId}.`);
