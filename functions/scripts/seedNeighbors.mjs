// Puts a few demo warungs on the buyer map around Jl. Telang Raya, Kamal,
// so the map and the item search have more than one result.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/seedNeighbors.mjs
//
// These exist only as public copies marked `seed: true`; nobody owns them
// and they have no private data. Safe to run again.
import {readFileSync} from "node:fs";
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {GeoPoint, getFirestore, Timestamp} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
const {slugify} = require("../lib/catalog/text.js");
const {encodeGeohash} = require("../lib/geo.js");

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const db = getFirestore();

const catalog = JSON.parse(
  readFileSync(new URL("./data/catalog.json", import.meta.url), "utf8"));

// Positions are a few hundred metres from Jl. Telang Raya (-7.1289, 112.7243).
const neighbors = [
  {id: "seed-madura-jaya", name: "Toko Madura Jaya", address: "Jl. Raya Telang No. 45, Kamal",
    lat: -7.1262, lng: 112.7268, hours: {is24h: true}, minutesAgo: 60},
  {id: "seed-al-ikhlas", name: "Warung Al-Ikhlas", address: "Perum Telang Indah Blok C, Kamal",
    lat: -7.1325, lng: 112.7281, hours: {is24h: false, open: "05:30", close: "23:00"},
    minutesAgo: 25},
  {id: "seed-sumber-rezeki", name: "Warung Sumber Rezeki", address: "Jl. Telang Asri No. 3, Kamal",
    lat: -7.1351, lng: 112.7198, hours: {is24h: true}, minutesAgo: 60 * 26},
  {id: "seed-bu-aminah", name: "Warung Bu Aminah", address: "Jl. Kampus UTM, Telang, Kamal",
    lat: -7.1247, lng: 112.7205, hours: {is24h: false, open: "06:00", close: "21:00"},
    minutesAgo: 8},
];

// A fixed pattern, so each warung carries a different mix and status.
function statusFor(warungIndex, itemIndex) {
  const roll = (warungIndex * 7 + itemIndex * 13) % 10;
  return roll === 0 ? "habis" : roll <= 2 ? "terbatas" : "tersedia";
}

const writes = [];
neighbors.forEach((warung, warungIndex) => {
  const ref = db.doc(`publicWarungs/${warung.id}`);
  const lastActiveAt = Timestamp.fromMillis(Date.now() - warung.minutesAgo * 60 * 1000);
  // Each neighbour stocks most, but not all, of the catalog.
  const stocked = catalog.filter((_, itemIndex) => (itemIndex + warungIndex) % 4 !== 0);
  writes.push((batch) => batch.set(ref, {
    name: warung.name, address: warung.address,
    location: new GeoPoint(warung.lat, warung.lng),
    geohash: encodeGeohash(warung.lat, warung.lng),
    hours: warung.hours, itemCount: stocked.length, lastActiveAt, seed: true,
  }));
  stocked.forEach((item, itemIndex) => {
    writes.push((batch) => batch.set(ref.collection("items").doc(slugify(item.name)), {
      name: item.name, category: item.category,
      status: statusFor(warungIndex, itemIndex), updatedAt: lastActiveAt,
    }));
  });
});

for (let i = 0; i < writes.length; i += 400) {
  const batch = db.batch();
  writes.slice(i, i + 400).forEach((write) => write(batch));
  await batch.commit();
}
console.log(`Seeded ${neighbors.length} neighbouring warungs with ${writes.length - neighbors.length} items.`);
