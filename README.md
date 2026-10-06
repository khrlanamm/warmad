# Warmad

Aplikasi Android untuk warung Madura. Sisi warung: kasir, stok, barang masuk, pengeluaran, kasbon, tutup kas, laporan, dan notifikasi stok. Sisi pembeli: peta warung terdekat dan pencarian barang lintas warung.

Flutter di sisi aplikasi, Firebase di sisi server (Authentication, Firestore, Cloud Functions, Cloud Messaging, Hosting). Project Firebase: `warrung-madura`, wilayah `asia-southeast2`.

## Susunan repo

| Folder | Isi |
|---|---|
| `lib/app` | Tema, router |
| `lib/core` | Uang, tanggal, widget bersama |
| `lib/features/<fitur>` | Tiap fitur: `domain` (logika murni), `data` (Firestore), `ui` |
| `functions/src` | Cloud Functions (TypeScript) |
| `functions/test` | Uji logika, uji Security Rules, uji integrasi di emulator |
| `functions/scripts` | Skrip data demo dan perbaikan |
| `firestore.rules` | Security Rules |
| `hosting` | Halaman kebijakan privasi dan hapus akun |

## Menjalankan

```sh
flutter pub get
flutter run
```

File rahasia tidak ikut di git dan harus ada sendiri di tiap mesin:

- `android/key.properties`: kata sandi keystore dan `mapsApiKey` (kunci Maps SDK for Android).
- `android/app/upload-keystore.jks`: kunci upload Play Store.
- `secrets/*.json`: kunci service account untuk skrip.

## Uji

```sh
flutter analyze
flutter test                              # logika uang, stok, kas, laporan
npm --prefix functions run test:rules     # rules + functions, butuh Java 21
```

Uji rules dan functions berjalan di Emulator Suite, tidak menyentuh data produksi.

## Deploy

```sh
firebase deploy --only functions,firestore:rules
firebase deploy --only hosting
flutter build appbundle --release         # hasil: build/app/outputs/bundle/release/
```

## Data demo

```sh
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/secrets/<service-account>.json
OWNER_EMAIL=pemilik@example.com npm --prefix functions run seed:demo
```

Pemilik harus sudah mendaftarkan warungnya lewat aplikasi. Skrip mengisi katalog, barang, riwayat penjualan 60 hari, laporan, angka batas pesan, salinan publik, dan beberapa warung tetangga. Tiap skrip di `functions/scripts` bisa dijalankan sendiri; cara pakainya ada di awal file.

## Aturan inti

- Uang selalu `int` Rupiah, tidak pernah `double`.
- Penjualan, barang masuk, pengeluaran, kasbon, pembatalan, dan tutup kas masing-masing satu `WriteBatch`: atomik, jalan offline, aman saat dua HP mencatat bersamaan.
- Security Rules mengikat tiap perubahan saldo (kas, utang pemasok, kasbon) ke catatan yang menjelaskannya di batch yang sama.
- Pembeli hanya membaca `publicWarungs`, salinan yang ditulis Cloud Functions. Isinya hanya nama, lokasi, jam buka, dan status barang.
- Rumus stok pengaman, batas pesan, dan jumlah pesan ada di TypeScript dan Dart, diuji dengan vektor yang sama di `functions/test/vectors/inventory.json`.
