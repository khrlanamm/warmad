# Warmad

![Warmad feature graphic](https://raw.githubusercontent.com/khrlanamm/khrlanamm/main/assets/projects/warmad.webp)

Android app for warung Madura, the small 24-hour neighborhood shops. For the shop: cashier, stock, incoming goods, expenses, customer credit (kasbon), cash closing, reports, and low stock alerts. For buyers: a map of nearby shops and item search across shops.

[Google Play](https://play.google.com/store/apps/details?id=com.benevology.warmad)

Flutter on the app side, Firebase on the server side (Authentication, Firestore, Cloud Functions, Cloud Messaging, Hosting). Firebase project `warrung-madura`, region `asia-southeast2`.

## Repository layout

| Folder | Contents |
|---|---|
| `lib/app` | Theme, router |
| `lib/core` | Money, dates, shared widgets |
| `lib/features/<feature>` | Each feature: `domain` (pure logic), `data` (Firestore), `ui` |
| `functions/src` | Cloud Functions (TypeScript) |
| `functions/test` | Logic tests, Security Rules tests, integration tests on the emulator |
| `functions/scripts` | Demo data and maintenance scripts |
| `firestore.rules` | Security Rules |
| `hosting` | Privacy policy and account deletion pages |
| `store` | Play Store listing text and images |
| `docs/manual` | User manual (PDF) and the script that builds it |

## Running

```sh
flutter pub get
flutter run
```

Secret files are not in git and must exist on each machine:

- `android/key.properties`: keystore passwords and `mapsApiKey` (Maps SDK for Android key).
- `android/app/upload-keystore.jks`: Play Store upload key.
- `secrets/*.json`: service account keys for the scripts.

## Tests

```sh
flutter analyze
flutter test                              # money, stock, cash, and report logic
npm --prefix functions run test:rules     # rules and functions, needs Java 21
```

Rules and functions tests run on the Emulator Suite and never touch production data.

## Deploy

```sh
firebase deploy --only functions,firestore:rules
firebase deploy --only hosting
flutter build appbundle --release         # output: build/app/outputs/bundle/release/
```

## User manual

```sh
python3 -I docs/manual/make_manual.py     # output: docs/manual/buku-panduan-warmad.pdf
```

The content of each page (title, screenshot, marker positions, explanation) is in the `PAGES` list in the script. New screenshots go to `docs/manual/raw/` as 1080x2424 PNG files. The script crops and shrinks them into `docs/manual/shots/`.

The barcode scanner screen (`shots/o_scan.jpg`) is not a screenshot. The emulator camera only shows a virtual room, so `docs/manual/make_scan_shot.py` draws it.

## Demo data

```sh
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/secrets/<service-account>.json
OWNER_EMAIL=pemilik@example.com npm --prefix functions run seed:demo
```

The owner must register the shop in the app first. The script fills the catalog, items, 60 days of sales history, reports, reorder points, the public copy, and a few neighboring shops. Each script in `functions/scripts` can run on its own, and its usage is at the top of the file.

## Core rules

- Money is always an `int` in Rupiah, never a `double`.
- Each sale, incoming delivery, expense, kasbon entry, void, and cash closing is one `WriteBatch`. It is atomic, works offline, and stays correct when two phones record at the same time.
- Security Rules tie every balance change (cash, supplier debt, kasbon) to the record that explains it in the same batch.
- Buyers only read `publicWarungs`, a copy written by Cloud Functions. It holds only the name, location, opening hours, and item availability.
- The formulas for safety stock, reorder point, and order quantity exist in both TypeScript and Dart, and both are tested with the same vectors in `functions/test/vectors/inventory.json`.

## License

All rights reserved. The source code is public for reference only. See [LICENSE](LICENSE).
