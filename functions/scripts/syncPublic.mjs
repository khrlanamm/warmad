// Rebuilds what buyers see for one warung from its private data: the public
// copy of the warung and the availability of each of its goods. Removes the
// public copy when the owner keeps the warung off the map.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/syncPublic.mjs owner@example.com
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

const email = process.argv[2];
if (!email) {
  console.error("Usage: node functions/scripts/syncPublic.mjs <owner email>");
  process.exit(1);
}

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const require = createRequire(import.meta.url);
const {syncPublicWarung} = require("../lib/public/sync.js");

const db = getFirestore();
const user = await getAuth().getUserByEmail(email);
const warungId = (await db.doc(`users/${user.uid}`).get()).get("warungId");
if (!warungId) {
  console.error(`${email} has no warung.`);
  process.exit(1);
}
await syncPublicWarung(db, db.doc(`warungs/${warungId}`));
const items = await db.collection(`publicWarungs/${warungId}/items`).count().get();
console.log(`Public copy of warung ${warungId} now lists ${items.data().count} item(s).`);
