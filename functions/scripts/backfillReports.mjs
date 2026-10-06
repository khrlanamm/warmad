// Rebuilds the per-day report documents of one warung from its sales and
// cash moves. Use it after seeding history, or to repair the reports.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/backfillReports.mjs owner@example.com
//
// Do not run it while the warung is recording transactions: it replaces the
// report documents with what it read at the start.
import {createRequire} from "node:module";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
const {productDeltaForSale, summaryDeltaForMove, summaryDeltaForSale} =
  require("../lib/reports/aggregate.js");

const email = process.argv[2];
if (!email) {
  console.error("Usage: node functions/scripts/backfillReports.mjs <owner email>");
  process.exit(1);
}

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const db = getFirestore();

const user = await getAuth().getUserByEmail(email);
const warungId = (await db.doc(`users/${user.uid}`).get()).get("warungId");
if (!warungId) {
  console.error(`${email} has no warung.`);
  process.exit(1);
}
const warung = db.doc(`warungs/${warungId}`);

const summaries = new Map(); // dayKey -> {fields, expenseByCategory}
const products = new Map(); // dayKey -> {qty, revenue}
const day = (map, key, empty) => map.get(key) ?? map.set(key, empty()).get(key);

function addSummary(dayKey, delta) {
  const entry = day(summaries, dayKey, () => ({fields: {}, expenseByCategory: {}}));
  for (const [key, value] of Object.entries(delta.fields)) {
    entry.fields[key] = (entry.fields[key] ?? 0) + value;
  }
  if (delta.expenseCategory) {
    const {name, amount} = delta.expenseCategory;
    entry.expenseByCategory[name] = (entry.expenseByCategory[name] ?? 0) + amount;
  }
}
function addProducts(dayKey, delta) {
  const entry = day(products, dayKey, () => ({qty: {}, revenue: {}}));
  for (const [id, {qty, revenue}] of Object.entries(delta)) {
    entry.qty[id] = (entry.qty[id] ?? 0) + qty;
    entry.revenue[id] = (entry.revenue[id] ?? 0) + revenue;
  }
}

const sales = await warung.collection("sales").get();
const moves = await warung.collection("cashMoves").get();
const saleById = new Map(sales.docs.map((doc) => [doc.id, doc.data()]));

for (const doc of sales.docs) {
  const sale = doc.data();
  if (!sale.dayKey) continue;
  addSummary(sale.dayKey, summaryDeltaForSale(sale));
  addProducts(sale.dayKey, productDeltaForSale(sale));
}
for (const doc of moves.docs) {
  const move = doc.data();
  if (!move.dayKey) continue;
  addSummary(move.dayKey, summaryDeltaForMove(move));
  const voided = move.kind === "refund" ? saleById.get(move.saleId) : undefined;
  if (voided?.dayKey) addProducts(voided.dayKey, productDeltaForSale(voided, -1));
}

// Firestore batches hold at most 500 writes.
const writes = [];
for (const name of ["dailySummaries", "dailyProductSales"]) {
  for (const doc of (await warung.collection(name).get()).docs) {
    writes.push((batch) => batch.delete(doc.ref));
  }
}
for (const [dayKey, entry] of summaries) {
  writes.push((batch) => batch.set(warung.collection("dailySummaries").doc(dayKey), {
    ...entry.fields,
    expenseByCategory: entry.expenseByCategory,
    updatedAt: FieldValue.serverTimestamp(),
  }));
}
for (const [dayKey, entry] of products) {
  writes.push((batch) => batch.set(warung.collection("dailyProductSales").doc(dayKey), {
    ...entry, updatedAt: FieldValue.serverTimestamp(),
  }));
}
for (const doc of [...sales.docs, ...moves.docs]) {
  if (!doc.get("aggregatedAt")) {
    writes.push((batch) => batch.update(doc.ref, {aggregatedAt: FieldValue.serverTimestamp()}));
  }
}
for (let i = 0; i < writes.length; i += 400) {
  const batch = db.batch();
  writes.slice(i, i + 400).forEach((write) => write(batch));
  await batch.commit();
}
console.log(
  `Rebuilt ${summaries.size} day(s) from ${sales.size} sales and ${moves.size} cash moves ` +
  `for warung ${warungId}.`);
