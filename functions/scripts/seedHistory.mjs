// Fills one warung with believable past sales, so reports, best sellers and
// reorder figures have something to show in a demo.
//
// Run from the repository root, after `npm --prefix functions run build`:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/seedHistory.mjs owner@example.com [days]
//
// It writes sales, expenses and stock purchases dated before today, marked
// `seed: true`. It does not touch today's cash counters or current stock.
// Safe to run again: earlier seeded history is removed first. Afterwards run
// backfillReports.mjs and recomputeInventory.mjs.
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

const email = process.argv[2];
const days = Number(process.argv[3] ?? 60);
if (!email) {
  console.error("Usage: node functions/scripts/seedHistory.mjs <owner email> [days]");
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

// A small seeded generator, so every run produces the same history.
let state = 20261006;
function random() {
  state = (state + 0x6d2b79f5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const between = (min, max) => min + Math.floor(random() * (max - min + 1));

const products = (await warung.collection("products").where("active", "==", true).get())
  .docs.map((doc) => ({id: doc.id, ...doc.data()}));
if (products.length === 0) {
  console.error("The warung has no products. Run seedWarungProducts.mjs first.");
  process.exit(1);
}

// Cheap things sell often, expensive things rarely.
function popularity(product) {
  const price = product.sellPrice;
  const base = price <= 2000 ? 20 : price <= 5000 ? 10 : price <= 10000 ? 5 :
    price <= 20000 ? 2.5 : 1;
  return base * (0.5 + random());
}
const weights = products.map(popularity);
const totalWeight = weights.reduce((a, b) => a + b, 0);
function pickProduct() {
  let roll = random() * totalWeight;
  for (let i = 0; i < products.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return products[i];
  }
  return products[products.length - 1];
}

const cashiers = [
  {uid: user.uid, name: user.displayName ?? "Pemilik"},
  {uid: "seed-rudi", name: "Rudi"},
  {uid: "seed-siti", name: "Siti"},
];
const dayKeyOf = (date) =>
  new Intl.DateTimeFormat("en-CA", {timeZone: "Asia/Jakarta"}).format(date);

const writes = [];
for (const name of ["sales", "cashMoves"]) {
  for (const doc of (await warung.collection(name).where("seed", "==", true).get()).docs) {
    writes.push((batch) => batch.delete(doc.ref));
  }
}

const now = new Date();
const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
let saleCount = 0;
for (let back = days; back >= 1; back--) {
  const dayStart = new Date(startOfToday.getTime() - back * 24 * 3600 * 1000);
  const weekend = [0, 6].includes(dayStart.getDay());
  const at = (hour, minute) =>
    new Date(dayStart.getTime() + hour * 3600 * 1000 + minute * 60 * 1000);

  const salesToday = between(28, 44) + (weekend ? 8 : 0);
  for (let n = 0; n < salesToday; n++) {
    const lines = new Map();
    for (let line = between(1, 4); line > 0; line--) {
      const product = pickProduct();
      lines.set(product.id, {product, qty: (lines.get(product.id)?.qty ?? 0) + between(1, 3)});
    }
    const items = [...lines.values()].map(({product, qty}) => ({
      productId: product.id, name: product.name, qty,
      price: product.sellPrice, subtotal: qty * product.sellPrice,
    }));
    const total = items.reduce((sum, item) => sum + item.subtotal, 0);
    const paid = Math.ceil(total / 5000) * 5000;
    const cashier = cashiers[between(0, cashiers.length - 1)];
    const occurredAt = at(between(6, 22), between(0, 59));
    const sale = {
      items, total, paid, change: paid - total, payment: "cash",
      cashierUid: cashier.uid, cashierName: cashier.name,
      occurredAt: Timestamp.fromDate(occurredAt), dayKey: dayKeyOf(occurredAt),
      createdAt: Timestamp.fromDate(occurredAt),
      // Already counted: backfillReports.mjs builds the reports from these.
      aggregatedAt: FieldValue.serverTimestamp(), seed: true,
    };
    writes.push((batch) => batch.set(warung.collection("sales").doc(), sale));
    saleCount++;
  }

  const move = (hour, fields) => {
    const occurredAt = at(hour, between(0, 59));
    writes.push((batch) => batch.set(warung.collection("cashMoves").doc(), {
      cash: false, // Before the open period, so today's counters stay as they are.
      occurredAt: Timestamp.fromDate(occurredAt), dayKey: dayKeyOf(occurredAt),
      createdByUid: user.uid, createdByName: user.displayName ?? "Pemilik",
      createdAt: Timestamp.fromDate(occurredAt),
      aggregatedAt: FieldValue.serverTimestamp(), seed: true, ...fields,
    }));
  };
  // Restock two or three products most days.
  for (let n = between(1, 3); n > 0; n--) {
    const product = pickProduct();
    const qty = product.pack?.size ?? between(5, 20);
    move(9, {
      kind: "purchase", amount: qty * (product.lastBuyPrice || 1000), productId: product.id,
      productName: product.name, qty, paidFrom: "cash",
    });
  }
  if (back % 7 === 3) move(10, {kind: "expense", amount: 25000, category: "Plastik & kemasan"});
  if (back % 7 === 5) move(16, {kind: "expense", amount: 30000, category: "Transport"});
  if (back % 30 === 12) move(11, {kind: "expense", amount: 350000, category: "Listrik"});
  if (back % 30 === 2) move(11, {kind: "expense", amount: 600000, category: "Sewa"});
  if (back % 7 === 0) move(20, {kind: "prive", amount: between(4, 12) * 25000, category: "Pribadi"});
}

for (let i = 0; i < writes.length; i += 400) {
  const batch = db.batch();
  writes.slice(i, i + 400).forEach((write) => write(batch));
  await batch.commit();
}
console.log(`Seeded ${saleCount} sales over ${days} days for warung ${warungId}.`);
