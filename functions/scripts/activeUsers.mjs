// Lists who used the app on a given day and at what time. Reads data that
// already exists: the sign-in records of Firebase Authentication and the
// sales each warung account recorded. Writes nothing.
//
// Firebase keeps only the latest sign-in and the latest session refresh of
// each account. So run this near the end of the day you ask about: an account
// that was active on Monday and again on Tuesday shows up under Tuesday only.
// A session refreshes at most once an hour, so the time shown can be up to an
// hour earlier than the moment the app was last opened. The sales column
// counts the sales of that day and does not have these limits.
//
// Run from the repository root:
//   GOOGLE_APPLICATION_CREDENTIALS=secrets/<service-account>.json \
//     node functions/scripts/activeUsers.mjs [yyyy-MM-dd] [testers.txt]
//
// The day is a calendar day in Jakarta time and defaults to today. The
// optional file holds tester emails, one per line. With it, the report covers
// those testers only and names the ones who did not open the app.
import {readFileSync} from "node:fs";

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";

const ZONE = "Asia/Jakarta";
const dayOf = (date) => new Intl.DateTimeFormat("en-CA", {timeZone: ZONE}).format(date);
const clockOf = (date) =>
  new Intl.DateTimeFormat("id-ID", {timeZone: ZONE, hour: "2-digit", minute: "2-digit"}).format(date);

const args = process.argv.slice(2);
const day = args.find((arg) => /^\d{4}-\d{2}-\d{2}$/.test(arg)) ?? dayOf(new Date());
const testersFile = args.find((arg) => arg !== day);
const testers = testersFile ?
  new Set(readFileSync(testersFile, "utf8").split(/\s+/).map((line) => line.trim().toLowerCase()).filter(Boolean)) :
  null;

initializeApp({credential: applicationDefault(), projectId: "warrung-madura"});
const auth = getAuth();
const db = getFirestore();

const accounts = [];
let pageToken;
do {
  const page = await auth.listUsers(1000, pageToken);
  accounts.push(...page.users);
  pageToken = page.pageToken;
} while (pageToken);

const profiles = new Map();
for (let i = 0; i < accounts.length; i += 300) {
  const refs = accounts.slice(i, i + 300).map((account) => db.doc(`users/${account.uid}`));
  for (const snapshot of await db.getAll(...refs)) profiles.set(snapshot.id, snapshot.data() ?? {});
}

// Sales of the day, counted per person who recorded them.
const salesBy = new Map();
const warungIds = new Set([...profiles.values()].map((profile) => profile.warungId).filter(Boolean));
for (const warungId of warungIds) {
  const sales = await db.collection(`warungs/${warungId}/sales`).where("dayKey", "==", day).select("cashierUid").get();
  for (const sale of sales.docs) {
    const uid = sale.get("cashierUid");
    salesBy.set(uid, (salesBy.get(uid) ?? 0) + 1);
  }
}

const describe = (profile) => {
  if (profile.warungId) return profile.role === "cashier" ? "kasir" : "pemilik";
  return profile.mode === "pembeli" ? "pembeli" : "belum pilih peran";
};

const rows = accounts
  .filter((account) => !testers || testers.has((account.email ?? "").toLowerCase()))
  .map((account) => {
    const times = [account.metadata.lastRefreshTime, account.metadata.lastSignInTime]
      .filter(Boolean)
      .map((time) => new Date(time));
    const lastActive = times.length ? new Date(Math.max(...times)) : null;
    return {
      email: account.email ?? account.uid,
      role: describe(profiles.get(account.uid) ?? {}),
      lastActive,
      sales: salesBy.get(account.uid) ?? 0,
      activeThatDay: (lastActive !== null && dayOf(lastActive) === day) || salesBy.has(account.uid),
    };
  })
  .sort((a, b) => (b.lastActive?.getTime() ?? 0) - (a.lastActive?.getTime() ?? 0));

const active = rows.filter((row) => row.activeThatDay);
console.log(`Aktif pada ${day} (waktu Jakarta): ${active.length} dari ${rows.length} akun`);
for (const row of active) {
  const when = row.lastActive && dayOf(row.lastActive) === day ? clockOf(row.lastActive) : "--.--";
  console.log(`  ${when}  ${row.email.padEnd(36)} ${row.role.padEnd(18)} ${row.sales} penjualan`);
}

const idle = rows.filter((row) => !row.activeThatDay);
if (idle.length) {
  console.log(`\nTidak tercatat aktif pada ${day}:`);
  for (const row of idle) {
    const last = row.lastActive ? `${dayOf(row.lastActive)} ${clockOf(row.lastActive)}` : "belum pernah masuk";
    console.log(`  ${row.email.padEnd(36)} ${row.role.padEnd(18)} terakhir ${last}`);
  }
}

if (testers) {
  const known = new Set(accounts.map((account) => (account.email ?? "").toLowerCase()));
  const missing = [...testers].filter((email) => !known.has(email));
  if (missing.length) {
    console.log(`\nBelum pernah masuk ke aplikasi (${missing.length}):`);
    for (const email of missing) console.log(`  ${email}`);
  }
}
