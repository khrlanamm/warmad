"""Builds the Warmad user manual as a PDF.

Every page is HTML (brand colours and fonts, phone mockups, numbered pins on
the screenshots) printed to PDF with headless Chrome.

    python3 -I docs/manual/make_manual.py

Input:  docs/manual/shots/*.jpg   emulator screenshots, status bar cropped
        (o_scan.jpg is drawn by make_scan_shot.py, see there)
Output: docs/manual/buku-panduan-warmad.pdf

New screenshots go into docs/manual/raw/ as full-resolution PNG files
(1080x2424). The script crops and shrinks them into shots/ on its next run;
that step needs Pillow. Pin positions below are written in the coordinates of
a 401x900 preview of the full screenshot, which is what `sips -Z 900` gives.
"""

import html
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
MANUAL = ROOT / "docs" / "manual"
RAW = MANUAL / "raw"
SHOTS = MANUAL / "shots"
OUT = MANUAL / "buku-panduan-warmad.pdf"
FONTS = ROOT / "assets" / "fonts"
BRAND = ROOT / "assets" / "brand"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

APP_VERSION = "0.2.1"
GREEN, YELLOW, CREAM, INK = "#1F6B45", "#F4B51E", "#FBF7EE", "#1A2B22"

# Raw screenshot geometry. The status bar is cropped so the emulator's clock
# and icons do not show.
RAW_W, RAW_H, STATUS_BAR = 1080, 2424, 142
PREVIEW_W, PREVIEW_H = 401, 900

# Areas blanked in a screenshot before it is used, in preview coordinates:
# (left, top, right, bottom, fill). They hide the email addresses of the
# accounts used to take the screenshots.
MASKS = {
    "a_pilih_akun": [(86, 478, 240, 495, "#FFFFFF"), (86, 540, 240, 557, "#FFFFFF")],
    "b_akun": [(100, 158, 270, 177, "#FFFFFF")],
}

# accent, text on accent, tint
ROLES = {
    "mulai": ("Mulai", INK, "#FFFFFF", "#EFEADC"),
    "pemilik": ("Pemilik", GREEN, "#FFFFFF", "#E3EFE7"),
    "kasir": ("Kasir", YELLOW, INK, "#FDF1D3"),
    "pembeli": ("Pembeli", "#B4470F", "#FFFFFF", "#FCE8DC"),
    "semua": ("Semua peran", INK, "#FFFFFF", "#EFEADC"),
}


def prepare_shots():
    """Crops and shrinks new screenshots from raw/ into shots/."""
    if not RAW.is_dir():
        return
    from PIL import Image, ImageDraw

    SHOTS.mkdir(parents=True, exist_ok=True)
    scale = RAW_W / PREVIEW_W
    for source in sorted(RAW.glob("*.png")):
        target = SHOTS / f"{source.stem}.jpg"
        if target.exists() and target.stat().st_mtime >= source.stat().st_mtime:
            continue
        image = Image.open(source).convert("RGB")
        draw = ImageDraw.Draw(image)
        for left, top, right, bottom, fill in MASKS.get(source.stem, []):
            draw.rectangle([left * scale, top * scale, right * scale, bottom * scale], fill=fill)
        image = image.crop((0, STATUS_BAR, RAW_W, RAW_H))
        image = image.resize((640, round(640 * image.height / image.width)), Image.LANCZOS)
        image.save(target, "JPEG", quality=88, optimize=True)
        print("shot", target.relative_to(ROOT))


def shot(name, step, *pins):
    """One screenshot with its caption and pins: (x, y, text) in preview px."""
    return {"name": name, "step": step, "pins": pins}


def page(kind, role, title, intro, shots=(), path=None, tip=None, toc=None):
    return {"kind": kind, "role": role, "title": title, "intro": intro,
            "shots": list(shots), "path": path, "tip": tip, "toc": toc or title}


PAGES = [
    # ---------------------------------------------------------------- mulai
    page("duo", "mulai", "Masuk dengan Google",
         "Tidak ada daftar akun dan tidak ada kata sandi baru. Cukup akun Google yang sudah ada di HP.",
         [shot("a_masuk", "Buka Warmad",
               (48, 798, "Ketuk <b>Masuk dengan Google</b>.")),
          shot("a_pilih_akun", "Pilih akun",
               (350, 500, "Pilih akun Google yang mau dipakai. Selesai, kamu sudah masuk."))],
         tip="Satu akun Google untuk satu orang. Pemilik dan kasir memakai akun masing-masing."),
    page("tour", "mulai", "Pilih peranmu",
         "Layar ini muncul sekali, saat pertama kali masuk. Peran bisa diganti lagi nanti dari menu Akun.",
         [shot("a_peran", "",
               (372, 322, "<b>Saya pemilik warung.</b> Daftarkan warung, lalu pakai kasir, stok, kas, dan laporan."),
               (372, 437, "<b>Saya pembeli.</b> Langsung ke peta warung dan cari barang."),
               (50, 787, "<b>Saya kasir.</b> Gabung ke warung dengan kode undangan dari pemilik."),
               (36, 712, "Setelah memilih, ketuk <b>Lanjut</b>."))],
         toc="Pilih peran"),

    # -------------------------------------------------------------- pemilik
    page("divider", "pemilik", "Pemilik warung",
         "Catat penjualan, jaga stok, cocokkan uang di laci, dan lihat laporan warungmu.",
         [shot("o_beranda", "")]),
    page("duo", "pemilik", "Daftarkan warung",
         "Dua langkah saja. Semua isian bisa diubah lagi nanti.",
         [shot("a_daftar1", "Langkah 1: data warung",
               (364, 207, "Isi nama warung, nomor HP, dan alamat."),
               (268, 548, "Geser peta sampai pin tepat di lokasi warung."),
               (294, 750, "Pilih jam buka."),
               (36, 812, "Ketuk <b>Lanjut</b>.")),
          shot("a_daftar2", "Langkah 2: kas dan peta",
               (364, 210, "Hitung uang di laci sekarang. Angka ini jadi saldo awal kas."),
               (366, 336, "Mau terlihat di peta pembeli? Nyalakan. Bawaannya mati."),
               (36, 812, "Ketuk <b>Buat warung</b>."))],
         toc="Daftarkan warung"),
    page("tour", "pemilik", "Beranda",
         "Semua yang perlu kamu tahu hari ini ada di satu layar.",
         [shot("o_beranda", "",
               (356, 172, "<b>Kas usaha sekarang.</b> Uang yang seharusnya ada di laci."),
               (138, 320, "Tiga tombol cepat: <b>Jual</b>, <b>Barang masuk</b>, <b>Pengeluaran</b>."),
               (378, 424, "Peringatan barang hampir habis. Ketuk untuk melihat daftarnya."),
               (378, 522, "<b>Tutup kas</b> saat ganti jaga atau akhir hari."),
               (250, 618, "Transaksi terakhir. <b>Lihat semua</b> membuka riwayat penjualan."),
               (318, 97, "Lonceng: notifikasi warung."),
               (240, 818, "Lima tab: Beranda, Kasir, Stok, Laporan, Akun."))]),
    page("duo", "pemilik", "Kasir: pilih barang",
         "Buka tab Kasir atau ketuk Jual di Beranda.",
         [shot("o_kasir1", "Dari daftar",
               (318, 253, "Ketuk <b>+</b> untuk memasukkan barang ke keranjang."),
               (378, 195, "Geser kategori untuk menyaring daftar."),
               (326, 80, "Punya barcode? Ketuk ikon pindai.")),
          shot("o_kasir_cari", "Dari pencarian",
               (300, 138, "Ketik sebagian nama barang."),
               (318, 317, "Ketuk <b>+</b> pada barang yang dicari."),
               (165, 266, "Stok 0 tetap bisa dijual. Barangnya nyata ada di tanganmu."))],
         path="Tab Kasir", toc="Kasir: pilih barang"),
    page("duo", "pemilik", "Kasir: terima uang",
         "Keranjang muncul di bawah begitu ada barang yang dipilih.",
         [shot("o_kasir2", "Hitung",
               (232, 380, "Atur jumlah dengan <b>−</b> dan <b>+</b>."),
               (232, 608, "Total belanja."),
               (382, 651, "Ketuk nominal uang yang diterima, atau ketik sendiri."),
               (292, 712, "Kembalian langsung terhitung."),
               (136, 748, "Ketuk <b>Bayar</b>."),
               (28, 746, "Pembeli berutang? Ketuk <b>Kasbon</b>.")),
          shot("o_kasir3", "Selesai",
               (320, 777, "Penjualan tersimpan. Berikan kembaliannya."),
               (168, 393, "Stok langsung berkurang, kas langsung bertambah."))],
         path="Tab Kasir", toc="Kasir: terima uang"),
    page("duo", "pemilik", "Kasir: pindai barcode",
         "Lebih cepat untuk barang kemasan. Barang harus sudah punya barcode di daftar stok.",
         [shot("o_scan_izin", "Pertama kali",
               (62, 455, "Izinkan kamera. Gambar kamera tidak disimpan dan tidak dikirim.")),
          shot("o_scan", "Arahkan kamera",
               (314, 430, "Arahkan ke barcode di kemasan. Barang yang cocok langsung masuk keranjang."),
               (72, 84, "Tutup pemindai."))],
         path="Tab Kasir › ikon pindai",
         tip="Muncul pesan “Barang dengan barcode ini belum terdaftar”? Tambahkan barangnya dulu lewat tab Stok.",
         toc="Kasir: pindai barcode"),
    page("duo", "pemilik", "Kasbon: pembeli berutang",
         "Barang keluar, uang belum masuk. Warmad mencatat siapa berutang berapa.",
         [shot("o_kasbon2", "Pilih pelanggan",
               (332, 134, "Di keranjang ketuk <b>Kasbon</b>, lalu ketik nama pelanggan."),
               (214, 195, "Pelanggan baru: ketuk <b>Tambah</b>. Pelanggan lama: ketuk namanya.")),
          shot("o_kasbon3", "Tersimpan",
               (342, 539, "Tercatat sebagai kasbon. Stok berkurang, kas tidak bertambah."))],
         path="Tab Kasir › Kasbon", toc="Kasbon pelanggan"),
    page("duo", "pemilik", "Kasbon: terima pembayaran",
         "Saat pelanggan membayar, uangnya masuk ke kas usaha.",
         [shot("o_kasbon_list", "Daftar kasbon",
               (176, 159, "Sisa kasbon tiap pelanggan."),
               (238, 147, "Pelanggan membayar? Ketuk <b>Terima bayar</b>."),
               (326, 80, "Tambah pelanggan baru.")),
          shot("o_kasbon_bayar", "Catat pembayaran",
               (306, 290, "Isi jumlah yang dibayar. Boleh sebagian."),
               (346, 389, "Ketuk <b>Simpan</b>. Kas usaha bertambah."))],
         path="Akun › Kasbon pelanggan", toc="Kasbon: terima pembayaran"),
    page("duo", "pemilik", "Riwayat dan batalkan penjualan",
         "Salah catat? Penjualan bisa dibatalkan. Catatannya tetap ada supaya jejaknya jelas.",
         [shot("o_penjualan", "Riwayat penjualan",
               (378, 118, "Label kuning: penjualan kasbon."),
               (378, 205, "Ketuk satu penjualan untuk melihat isinya."),
               (262, 655, "Penjualan yang dibatalkan dicoret, tidak dihapus.")),
          shot("o_penjualan_detail", "Detail penjualan",
               (378, 600, "Barang, total, uang diterima, dan kembalian."),
               (36, 833, "<b>Batalkan penjualan</b>: stok dan kas kembali. Hanya pemilik."))],
         path="Beranda › Lihat semua", toc="Riwayat dan batalkan penjualan"),
    page("duo", "pemilik", "Stok barang",
         "Barang yang perlu perhatian selalu di urutan teratas.",
         [shot("o_stok", "Daftar stok",
               (300, 237, "Ringkasan: berapa yang hampir habis dan habis."),
               (290, 292, "Merah: habis. Jingga: hampir habis."),
               (326, 80, "Tambah barang baru."),
               (244, 779, "Ketuk barang untuk melihat detailnya.")),
          shot("o_detail1", "Detail barang",
               (378, 186, "Stok sekarang, batas pesan, dan stok pengaman."),
               (378, 290, "Saran jumlah belanja, dihitung dari penjualan nyata warungmu."),
               (378, 428, "Penjualan 7 hari terakhir."),
               (322, 80, "<b>Ubah</b> data barang. Hanya pemilik."),
               (36, 812, "Barang datang? Ketuk <b>Catat barang masuk</b>."))],
         path="Tab Stok", toc="Stok barang"),
    page("duo", "pemilik", "Tambah barang",
         "Ketuk + di tab Stok. Ratusan barang warung sudah ada di katalog, tinggal pilih.",
         [shot("o_barang_baru1", "Isi data barang",
               (36, 122, "Ada barcode? Pindai dulu, nama terisi sendiri."),
               (364, 240, "Atau ketik nama barang."),
               (362, 381, "Pilih kategori."),
               (364, 476, "Isi harga jual, harga beli, dan stok sekarang."),
               (244, 721, "Belanja per dus atau renceng? Isi nama satuan dan isinya."),
               (36, 812, "Ketuk <b>Simpan barang</b>.")),
          shot("o_barang_baru2", "Saran dari katalog",
               (378, 281, "Saran muncul saat kamu mengetik."),
               (300, 305, "Ketuk saran supaya nama dan kategori terisi sendiri."))],
         path="Tab Stok › +", toc="Tambah barang"),
    page("duo", "pemilik", "Barang masuk",
         "Catat setiap belanja ke pemasok supaya stok dan kas tetap cocok.",
         [shot("o_masuk1", "Barang dan jumlah",
               (300, 178, "Pilih barang yang datang."),
               (378, 252, "Isi jumlah dalam pcs."),
               (208, 341, "Atau tambah per renceng atau dus."),
               (364, 435, "Harga beli per pcs."),
               (300, 532, "Pilih atau ketik nama pemasok. Boleh kosong.")),
          shot("o_masuk2", "Tanggal dan pembayaran",
               (300, 558, "Lupa mencatat kemarin? Ganti tanggalnya."),
               (298, 675, "Bayar dari <b>kas usaha</b>, atau catat sebagai <b>utang ke pemasok</b>."),
               (378, 720, "Total pembelian."),
               (36, 812, "Ketuk <b>Simpan barang masuk</b>."))],
         path="Beranda › Barang masuk", toc="Barang masuk"),
    page("duo", "pemilik", "Pemasok dan utang",
         "Setelah barang masuk disimpan, stok bertambah. Belanja yang belum dibayar tercatat sebagai utang.",
         [shot("o_detail_aman", "Stok bertambah",
               (36, 186, "Stok naik dan status berubah jadi <b>Aman</b>."),
               (378, 290, "Saran belanja dihitung ulang tiap malam.")),
          shot("o_pemasok", "Daftar pemasok",
               (176, 159, "Utang ke tiap pemasok."),
               (290, 147, "Sudah dibayar? Ketuk <b>Bayar</b>. Kas usaha berkurang."),
               (326, 80, "Tambah pemasok baru."))],
         path="Akun › Pemasok dan utang", toc="Pemasok dan utang"),
    page("duo", "pemilik", "Pengeluaran",
         "Pisahkan biaya warung dari uang yang kamu ambil untuk keperluan sendiri.",
         [shot("o_keluar1", "Untuk usaha",
               (20, 118, "<b>Untuk usaha</b>: listrik, sewa, plastik, dan biaya warung lain."),
               (292, 338, "Pilih kategori."),
               (364, 435, "Isi nominal."),
               (300, 632, "Tanggal bisa dimundurkan."),
               (378, 682, "Kas usaha setelah pengeluaran ini."),
               (36, 812, "Ketuk <b>Simpan pengeluaran</b>.")),
          shot("o_keluar2", "Untuk pribadi",
               (378, 120, "<b>Untuk pribadi</b>: uang laci yang kamu ambil untuk keperluan sendiri."),
               (378, 524, "Kas di laci berkurang, tapi tidak dihitung sebagai biaya usaha."))],
         path="Beranda › Pengeluaran", toc="Pengeluaran"),
    page("duo", "pemilik", "Tutup kas",
         "Cocokkan uang di laci dengan catatan. Lakukan tiap ganti jaga atau akhir hari.",
         [shot("o_tutup1", "Lihat catatan",
               (378, 166, "Catatan kas sejak tutup kas terakhir."),
               (224, 302, "Uang yang seharusnya ada di laci."),
               (364, 405, "Hitung uang di laci, lalu ketik jumlahnya.")),
          shot("o_tutup2", "Lihat selisih",
               (378, 458, "Selisih langsung terlihat. Kurang atau lebih, kas tetap bisa ditutup."),
               (36, 594, "Ketuk <b>Simpan dan tutup kas</b>. Periode baru mulai dari uang yang kamu hitung."),
               (278, 670, "Belum yakin? Ketuk <b>Cek lagi nanti</b>."))],
         path="Beranda › Tutup kas", toc="Tutup kas"),
    page("duo", "pemilik", "Setelah kas ditutup",
         "Setiap tutup kas tersimpan permanen dan pemilik selalu diberi tahu.",
         [shot("o_riwayat_kas", "Riwayat tutup kas",
               (300, 139, "<b>Pas</b>: uang cocok dengan catatan."),
               (226, 267, "<b>Selisih</b> tercatat dan tidak bisa diubah."),
               (238, 154, "Siapa yang menutup kas.")),
          shot("o_notif", "Notifikasi pemilik",
               (24, 154, "Kasir menutup kas: pemilik langsung diberi tahu."),
               (24, 285, "Barang habis atau hampir habis juga muncul di sini."),
               (255, 80, "Tandai semua sudah dibaca."))],
         path="Akun › Riwayat tutup kas", toc="Riwayat tutup kas dan notifikasi"),
    page("tour", "pemilik", "Laporan arus kas",
         "Uang masuk dan keluar warung, tanpa menghitung ulang nota.",
         [shot("o_laporan1", "",
               (20, 118, "Pilih <b>Arus kas</b> atau <b>Stok</b>."),
               (312, 193, "Harian, mingguan, atau bulanan."),
               (272, 240, "Mundur ke periode sebelumnya."),
               (200, 268, "Kas masuk dan kas keluar."),
               (378, 350, "Selisihnya: arus kas bersih."),
               (378, 458, "Grafik per hari."),
               (326, 80, "Bagikan laporan sebagai PDF atau Excel."))],
         path="Tab Laporan", toc="Laporan arus kas"),
    page("duo", "pemilik", "Laporan stok dan ekspor",
         "Lihat barang paling laku, lalu kirim laporannya ke siapa pun.",
         [shot("o_laporan_stok", "Laporan stok",
               (378, 302, "Barang paling laku pada periode ini."),
               (378, 625, "Daftar yang perlu dibelanjakan.")),
          shot("o_ekspor", "Bagikan",
               (254, 728, "<b>PDF</b>: mudah dibaca dan dicetak."),
               (348, 783, "<b>CSV</b>: buka di Excel."))],
         path="Tab Laporan › ikon unduh", toc="Laporan stok dan ekspor"),
    page("duo", "pemilik", "Akun dan warung",
         "Pengaturan warung ada di tab Akun.",
         [shot("o_akun1", "Pengaturan",
               (290, 244, "<b>Tampilkan warung di peta.</b> Bisa dimatikan kapan saja."),
               (282, 379, "Atur jam buka."),
               (306, 434, "Undang atau keluarkan kasir."),
               (290, 490, "Pengingat tutup kas."),
               (378, 535, "Kasbon, pemasok, riwayat penjualan, dan riwayat tutup kas.")),
          shot("o_pengingat", "Pengingat tutup kas",
               (244, 783, "Pilih jamnya. HP akan mengingatkan lewat notifikasi."),
               (36, 578, "<b>Beralih ke mode pembeli</b> untuk mencari warung lain."))],
         path="Tab Akun", toc="Akun dan warung"),
    page("duo", "pemilik", "Undang kasir",
         "Kasir memakai akun Google-nya sendiri. Kamu cukup memberi kode.",
         [shot("o_kasir_list", "Akun kasir",
               (36, 812, "Ketuk <b>Undang kasir</b> untuk membuat kode."),
               (296, 282, "Ikon merah: keluarkan kasir dari warung.")),
          shot("o_undang", "Kode undangan",
               (372, 632, "Kode 6 karakter. Berlaku 24 jam dan hanya sekali pakai."),
               (40, 812, "Ketuk <b>Bagikan kode</b>, misalnya lewat WhatsApp."))],
         path="Akun › Akun kasir", toc="Undang kasir"),
    page("tour", "pemilik", "Keluarkan kasir",
         "Kasir berhenti bekerja? Cabut aksesnya dari layar Akun kasir.",
         [shot("o_kasir_cabut", "",
               (348, 372, "Kasir tidak bisa lagi membuka data warung. Penjualan dan tutup kas yang pernah ia catat tetap ada."),
               (348, 528, "Ketuk <b>Keluarkan</b> untuk mencabut aksesnya."))],
         path="Akun › Akun kasir",
         tip="Di HP kasir, pencabutan bisa butuh sampai 1 jam untuk berlaku penuh.",
         toc="Keluarkan kasir"),

    # ---------------------------------------------------------------- kasir
    page("divider", "kasir", "Kasir",
         "Bantu pemilik menjaga warung: jual, catat barang masuk, dan tutup kas saat ganti jaga.",
         [shot("k_gabung", "")]),
    page("duo", "kasir", "Gabung ke warung",
         "Minta kode undangan ke pemilik warung, lalu masuk dengan akun Google-mu sendiri.",
         [shot("a_peran", "Pilih kasir",
               (50, 787, "Di layar peran, ketuk <b>Saya kasir, punya kode undangan</b>.")),
          shot("k_gabung", "Ketik kode",
               (372, 158, "Ketik 6 karakter kode dari pemilik."),
               (36, 475, "Ketuk <b>Gabung</b>. Kamu langsung masuk ke warung."))],
         tip="Kode berlaku 24 jam dan hanya sekali pakai. Kode ditolak? Minta kode baru ke pemilik.",
         toc="Gabung dengan kode undangan"),
    page("duo", "kasir", "Yang bisa dilakukan kasir",
         "Tampilannya sama dengan pemilik. Cara menjual, mencatat barang masuk, pengeluaran, kasbon, dan tutup kas ada di bagian Pemilik.",
         [shot("k_beranda", "Beranda kasir",
               (356, 172, "Kas usaha terlihat supaya bisa dicocokkan dengan laci."),
               (138, 320, "Jual, catat barang masuk, dan catat pengeluaran."),
               (378, 522, "Tutup kas saat ganti jaga.")),
          shot("k_akun", "Akun kasir",
               (302, 178, "Peranmu tertulis di sini."),
               (378, 219, "Kasbon, pemasok, dan riwayat tetap bisa dibuka."),
               (36, 460, "Mau cari warung lain? Pindah ke mode pembeli."))],
         toc="Yang bisa dilakukan kasir"),
    page("duo", "kasir", "Yang hanya untuk pemilik",
         "Beberapa hal dikunci supaya data warung tetap aman.",
         [shot("k_laporan", "Laporan",
               (200, 415, "Laporan hanya bisa dibuka pemilik.")),
          shot("k_detail", "Detail barang",
               (366, 80, "Tidak ada tombol <b>Ubah</b>. Nama dan harga hanya bisa diubah pemilik."),
               (36, 812, "Mencatat barang masuk tetap bisa."))],
         tip="Kasir juga tidak bisa membatalkan penjualan, mengundang kasir lain, atau mengubah pengaturan warung.",
         toc="Yang hanya untuk pemilik"),

    # -------------------------------------------------------------- pembeli
    page("divider", "pembeli", "Pembeli",
         "Cari warung Madura terdekat dan cek dulu barangnya sebelum berangkat.",
         [shot("b_peta", "")]),
    page("duo", "pembeli", "Peta warung",
         "Warung di sekitarmu langsung tampil. Izinkan lokasi supaya jaraknya tepat.",
         [shot("b_peta", "Peta",
               (372, 72, "Cari barang langsung dari sini."),
               (164, 147, "Tampilkan hanya warung yang sedang buka."),
               (238, 372, "Pin kuning: warung terpilih. Ketuk pin hijau untuk memilih warung lain."),
               (292, 671, "Jarak, jam buka, dan kapan status diperbarui."),
               (36, 746, "Ketuk <b>Lihat barang</b>."),
               (372, 746, "<b>Arah</b>: petunjuk jalan ke warung.")),
          shot("b_warung", "Halaman warung",
               (36, 354, "Buka petunjuk arah di aplikasi peta."),
               (364, 484, "Cek satu barang di warung ini."),
               (268, 570, "Status barang: tersedia, terbatas, atau habis."),
               (258, 528, "Kapan status terakhir diperbarui."))],
         path="Tab Peta", toc="Peta warung"),
    page("duo", "pembeli", "Cari barang",
         "Butuh satu barang tertentu? Lihat warung terdekat yang punya.",
         [shot("b_cari1", "Ketik nama barang",
               (310, 138, "Ketik nama barang."),
               (306, 282, "Pilih barang dari daftar.")),
          shot("b_cari2", "Warung yang punya",
               (292, 199, "Saring: stok tersedia atau buka sekarang."),
               (262, 311, "Warung terdekat di urutan atas."),
               (272, 568, "<b>Terbatas</b>: stok tinggal sedikit."),
               (374, 644, "Status diisi pemilik warung dan bisa berbeda dengan kondisi di toko."))],
         path="Tab Cari", toc="Cari barang"),
    page("duo", "pembeli", "Akun dan pindah peran",
         "Satu akun bisa dipakai sebagai pembeli sekaligus pemilik atau kasir.",
         [shot("b_akun", "Akun pembeli",
               (36, 222, "Punya warung? Ketuk untuk pindah ke mode pemilik."),
               (36, 288, "Keluar dari akun."),
               (286, 412, "Hapus akun dan semua datamu, kapan saja.")),
          shot("o_akun2", "Dari pemilik atau kasir",
               (36, 578, "Pemilik dan kasir: ketuk <b>Beralih ke mode pembeli</b> di tab Akun."),
               (292, 720, "Kebijakan privasi."))],
         path="Tab Akun", toc="Akun dan pindah peran"),

    # ---------------------------------------------------------------- semua
    page("tips", "semua", "Enam hal yang perlu kamu tahu", "Supaya tidak bingung saat memakai Warmad sehari-hari.",
         toc="Hal penting"),
    page("missions", "semua", "Kartu misi", "Coba semuanya, centang satu per satu. Makin banyak yang dicoba, makin cepat ketahuan apa yang perlu diperbaiki.",
         toc="Kartu misi"),
]

TIPS = [
    ("Tetap jalan tanpa internet",
     "Penjualan, barang masuk, pengeluaran, kasbon, dan tutup kas tetap bisa dicatat. Data terkirim sendiri saat HP tersambung lagi."),
    ("Yang butuh internet",
     "Masuk, daftar warung, undang dan gabung kasir, serta peta dan cari barang untuk pembeli."),
    ("Dua HP sekaligus",
     "Pemilik dan kasir bisa mencatat pada saat yang sama. Stok dan kas tetap tepat."),
    ("Stok 0 tetap bisa dijual",
     "Warmad tidak menolak penjualan. Kalau stok di aplikasi tidak cocok dengan rak, perbaiki lewat Barang masuk."),
    ("Yang dilihat pembeli",
     "Hanya nama warung, lokasi, jam buka, dan status barang. Jumlah stok, harga beli, penjualan, dan kas tidak pernah tampil."),
    ("Datamu milikmu",
     "Akun dan seluruh datanya bisa dihapus kapan saja dari tab Akun › Hapus akun."),
]

MISSIONS = {
    "pemilik": [
        "Daftarkan warung dan isi saldo awal kas",
        "Tambah 3 barang, salah satunya dengan pindai barcode",
        "Catat 1 penjualan tunai dan cek kembaliannya",
        "Catat 1 penjualan kasbon, lalu terima pembayarannya",
        "Catat barang masuk sebagai utang ke pemasok",
        "Catat 1 pengeluaran usaha dan 1 untuk pribadi",
        "Tutup kas dan lihat selisihnya",
        "Buka laporan mingguan dan bagikan sebagai PDF",
        "Undang 1 kasir dengan kode",
        "Nyalakan “Tampilkan warung di peta”",
    ],
    "kasir": [
        "Gabung ke warung dengan kode undangan",
        "Catat 2 penjualan, satu lewat pencarian",
        "Matikan internet, catat 1 penjualan, nyalakan lagi",
        "Catat barang masuk",
        "Tutup kas saat selesai jaga",
    ],
    "pembeli": [
        "Buka peta dan pilih satu warung",
        "Lihat daftar barang di warung itu",
        "Cari 1 barang dan lihat warung yang punya",
        "Buka petunjuk arah ke warung",
        "Pindah ke mode pemilik, lalu kembali ke pembeli",
    ],
}

ARROW = ('<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" '
         'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>')

CSS = f"""
@font-face {{ font-family: Bricolage; src: url("{(FONTS / 'BricolageGrotesque.ttf').as_uri()}"); font-weight: 200 800; }}
@font-face {{ font-family: DMSans; src: url("{(FONTS / 'DMSans.ttf').as_uri()}"); font-weight: 100 1000; }}
@page {{ size: 210mm 297mm; margin: 0; }}
* {{ box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
html, body {{ margin: 0; padding: 0; background: {CREAM}; }}
body {{ font: 400 13.5px/1.4 DMSans, sans-serif; color: {INK}; }}
a {{ color: inherit; text-decoration: none; }}
b {{ font-weight: 700; }}
.page {{ position: relative; width: 210mm; height: 297mm; overflow: hidden; background: {CREAM};
  page-break-after: always; break-after: page; padding: 58px 48px 0; }}
.page:last-child {{ page-break-after: auto; break-after: auto; }}

/* The yellow scalloped awning from the logo. */
.awning {{ position: absolute; top: 0; left: 0; right: 0; height: 16px; background: {YELLOW}; }}
.awning::after {{ content: ""; position: absolute; top: 15px; left: 0; right: 0; height: 18px;
  background: radial-gradient(ellipse 22px 15px at 50% 0, {YELLOW} 98%, transparent 100%) repeat-x;
  background-size: 44px 18px; }}

.head {{ display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }}
.tab {{ display: inline-flex; align-items: center; gap: 8px; height: 26px; padding: 0 12px 0 4px; border-radius: 13px;
  background: var(--accent); color: var(--on); font: 700 11.5px/1 DMSans; letter-spacing: .9px; text-transform: uppercase; }}
.tab i {{ display: grid; place-items: center; width: 18px; height: 18px; border-radius: 9px; background: var(--on);
  color: var(--accent); font: 800 10.5px/1 Bricolage; font-style: normal; letter-spacing: 0; }}
.crumb {{ display: inline-flex; align-items: center; height: 26px; padding: 0 12px; border-radius: 13px;
  border: 1.5px solid #E6E0D2; background: #fff; font: 500 11.5px/1 DMSans; color: #5C6B62; white-space: nowrap; }}
h1 {{ margin: 12px 0 0; font: 700 31px/1.1 Bricolage; letter-spacing: -.7px; }}
.intro {{ margin: 7px 0 0; max-width: 600px; font-size: 14.5px; line-height: 1.4; color: #5C6B62; }}

.pin {{ display: grid; place-items: center; flex: none; width: 24px; height: 24px; border-radius: 50%;
  background: {YELLOW}; color: {INK}; font: 800 13px/1 Bricolage; }}
/* Shadows have hard edges on purpose. Chrome prints a blurred shadow as a
   masked image, and the macOS PDF viewer draws those as gray boxes. */
.device {{ position: relative; background: {INK}; box-shadow: 7px 9px 0 #E9E2D0; }}
.screen {{ position: relative; overflow: hidden; background: {CREAM}; aspect-ratio: {RAW_W} / {RAW_H - STATUS_BAR}; }}
.screen img {{ display: block; width: 100%; }}
.screen .pin {{ position: absolute; width: 25px; height: 25px; margin: -12.5px 0 0 -12.5px;
  box-shadow: 0 0 0 2.5px #fff, 0 0 0 4px {INK}; }}

.legend {{ list-style: none; margin: 14px 0 0; padding: 0 2px; display: grid; gap: 6.5px; }}
.legend li {{ display: flex; gap: 9px; align-items: flex-start; line-height: 1.34; }}
.legend .pin {{ width: 21px; height: 21px; font-size: 11.5px; margin-top: -1px; }}

/* Two screenshots side by side. */
.duo {{ display: grid; grid-template-columns: 1fr 46px 1fr; margin-top: 20px; }}
.duo .col {{ width: 100%; }}
.duo .step {{ display: flex; align-items: center; gap: 8px; height: 26px; margin-bottom: 10px;
  font: 700 14.5px/1 Bricolage; letter-spacing: -.1px; }}
.duo .step i {{ display: grid; place-items: center; width: 24px; height: 24px; border-radius: 8px;
  background: var(--tint); color: var(--accent-text); font: 800 13px/1 Bricolage; font-style: normal; }}
.duo .device {{ width: 312px; margin: 0 auto; padding: 9px; border-radius: 37px; }}
.duo .screen {{ border-radius: 28px; }}
.duo .next {{ display: grid; place-items: center; width: 34px; height: 34px; margin: 338px auto 0; border-radius: 50%;
  background: var(--accent); color: var(--on); }}

/* One screenshot with its notes next to it. */
.tour {{ display: grid; grid-template-columns: 366px 1fr; gap: 28px; margin-top: 22px; align-items: start; }}
.tour .device {{ width: 366px; padding: 10px; border-radius: 42px; }}
.tour .screen {{ border-radius: 32px; }}
.tour .legend {{ margin: 6px 0 0; gap: 9px; }}
.tour .legend li {{ padding: 11px 13px; border-radius: 14px; background: #fff; border: 1.5px solid #E6E0D2;
  font-size: 14px; line-height: 1.36; }}
.tour .legend .pin {{ width: 24px; height: 24px; font-size: 13px; }}

.tip {{ display: flex; gap: 10px; align-items: flex-start; margin-top: 14px; padding: 11px 14px; border-radius: 14px;
  background: var(--tint); font-size: 13.5px; line-height: 1.36; }}
.tip em {{ flex: none; font: 800 11px/1 DMSans; font-style: normal; letter-spacing: .8px; text-transform: uppercase;
  padding: 5px 8px; border-radius: 8px; background: var(--accent); color: var(--on); }}
.page .tip.low {{ position: absolute; left: 48px; right: 48px; bottom: 58px; margin: 0; }}

.foot {{ position: absolute; left: 48px; right: 48px; bottom: 18px; height: 26px; display: flex; align-items: center;
  justify-content: space-between; font: 500 11px/1 DMSans; color: #8A968E; }}
.foot .mark {{ font: 800 15px/1 Bricolage; letter-spacing: -.5px; color: {GREEN}; }}
.foot .mark span {{ margin-left: 8px; font: 500 11px/1 DMSans; letter-spacing: 0; color: #8A968E; }}
.foot .home {{ padding: 6px 12px; border-radius: 12px; border: 1.5px solid #E6E0D2; background: #fff; color: #5C6B62; }}
.foot .num {{ display: grid; place-items: center; min-width: 26px; height: 26px; border-radius: 13px;
  background: {INK}; color: #fff; font: 700 11.5px/1 DMSans; }}

/* Cover */
.cover {{ background: {GREEN}; color: #fff; padding: 0; }}
.cover .awning {{ height: 34px; }}
.cover .awning::after {{ top: 33px; height: 30px; background-size: 72px 30px;
  background-image: radial-gradient(ellipse 36px 25px at 50% 0, {YELLOW} 98%, transparent 100%); }}
.cover .logo {{ position: absolute; left: 34px; top: 118px; width: 300px; }}
.cover .kicker {{ position: absolute; left: 60px; top: 372px; font: 700 13px/1 DMSans; letter-spacing: 2.4px;
  text-transform: uppercase; color: {YELLOW}; }}
.cover h1 {{ position: absolute; left: 58px; top: 400px; width: 400px; margin: 0; font: 700 62px/1 Bricolage;
  letter-spacing: -2px; }}
.cover .sub {{ position: absolute; left: 60px; top: 548px; width: 330px; font: 400 17px/1.4 DMSans;
  color: rgba(255, 255, 255, .86); }}
.cover .roles {{ position: absolute; left: 60px; top: 690px; display: grid; gap: 10px; }}
.cover .roles a {{ display: flex; align-items: center; gap: 12px; width: 300px; padding: 11px 14px; border-radius: 16px;
  background: rgba(255, 255, 255, .1); border: 1.5px solid rgba(255, 255, 255, .22); font: 600 15.5px/1.2 DMSans; }}
.cover .roles i {{ display: grid; place-items: center; width: 30px; height: 30px; border-radius: 10px; font: 800 14px/1 Bricolage;
  font-style: normal; }}
.cover .roles small {{ display: block; margin-top: 2px; font: 400 12px/1.2 DMSans; color: rgba(255, 255, 255, .72); }}
.cover .roles .go {{ margin-left: auto; color: {YELLOW}; display: grid; }}
.cover .stage {{ position: absolute; left: 448px; top: 250px; transform: rotate(5deg); }}
.cover .device {{ width: 330px; padding: 11px; border-radius: 42px; box-shadow: 12px 14px 0 #17523A; }}
.cover .screen {{ border-radius: 31px; }}
.cover .ver {{ position: absolute; left: 60px; bottom: 44px; font: 500 12px/1 DMSans; color: rgba(255, 255, 255, .7); }}

/* Contents */
.toc {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px 20px; margin-top: 20px; }}
.toc section {{ padding: 14px 16px 12px; border-radius: 18px; background: #fff; border: 1.5px solid #E6E0D2; }}
.toc section.wide {{ grid-row: span 3; }}
.toc h2 {{ display: flex; align-items: center; gap: 9px; margin: 0 0 8px; font: 700 17px/1 Bricolage; letter-spacing: -.2px; }}
.toc h2 i {{ width: 12px; height: 12px; border-radius: 4px; background: var(--accent); }}
.toc a {{ display: flex; align-items: baseline; gap: 8px; padding: 4.3px 0; font-size: 13.2px; line-height: 1.25; }}
.toc a u {{ flex: 1; border-bottom: 1.5px dotted #CFC8B6; transform: translateY(-3px); text-decoration: none; }}
.toc a b {{ font: 700 12px/1 DMSans; color: var(--accent-text); }}
.how {{ display: flex; gap: 22px; margin-top: 16px; padding: 13px 16px; border-radius: 18px; background: #EFEADC; }}
.how div {{ display: flex; gap: 9px; align-items: center; font-size: 13px; line-height: 1.3; }}
.how .box {{ flex: none; width: 18px; height: 18px; border-radius: 5px; border: 2px solid {INK}; background: #fff; }}

/* Section opener */
.divider {{ background: var(--accent); color: var(--on); padding: 0; }}
.divider .big {{ position: absolute; left: 54px; top: 86px; font: 800 150px/1 Bricolage; letter-spacing: -6px;
  color: color-mix(in srgb, var(--on) 20%, var(--accent)); }}
.divider .label {{ position: absolute; left: 60px; top: 254px; font: 700 13px/1 DMSans; letter-spacing: 2.4px; text-transform: uppercase;
  color: color-mix(in srgb, var(--on) 80%, var(--accent)); }}
.divider h1 {{ position: absolute; left: 58px; top: 278px; width: 380px; margin: 0; font: 700 58px/1 Bricolage; letter-spacing: -1.8px; }}
.divider .sub {{ position: absolute; left: 60px; top: 414px; width: 320px; font: 400 16px/1.42 DMSans;
  color: color-mix(in srgb, var(--on) 90%, var(--accent)); }}
.divider .list {{ position: absolute; left: 60px; top: 520px; width: 330px; display: grid; gap: 0; }}
.divider .list a {{ display: flex; justify-content: space-between; gap: 10px; padding: 4.6px 0; font: 500 13px/1.2 DMSans;
  border-bottom: 1px solid color-mix(in srgb, var(--on) 22%, transparent); }}
.divider .list a b {{ font-weight: 700; }}
.divider .stage {{ position: absolute; left: 452px; top: 214px; transform: rotate(4deg); }}
.divider .device {{ width: 320px; padding: 10px; border-radius: 40px;
  box-shadow: 12px 14px 0 color-mix(in srgb, var(--accent) 78%, #000); }}
.divider .screen {{ border-radius: 30px; }}
.divider .foot, .divider .foot .mark, .divider .foot .mark span {{ color: var(--on); }}
.divider .foot .home {{ background: transparent; color: var(--on); border-color: color-mix(in srgb, var(--on) 40%, transparent); }}
.divider .foot .num {{ background: var(--on); color: var(--accent); }}

/* Good to know */
.cards {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 26px; }}
.cards article {{ position: relative; padding: 20px 20px 20px; border-radius: 20px; background: #fff; border: 1.5px solid #E6E0D2; min-height: 214px; }}
.cards article i {{ display: grid; place-items: center; width: 38px; height: 38px; border-radius: 12px; font: 800 18px/1 Bricolage;
  font-style: normal; }}
.cards h3 {{ margin: 16px 0 7px; font: 700 21px/1.15 Bricolage; letter-spacing: -.3px; }}
.cards p {{ margin: 0; font-size: 15px; line-height: 1.45; color: #4A5A51; }}
.help {{ display: flex; align-items: center; justify-content: space-between; gap: 20px; margin-top: 20px; padding: 18px 20px;
  border-radius: 20px; background: {GREEN}; color: #fff; }}
.help h3 {{ margin: 0 0 4px; font: 700 19px/1.15 Bricolage; }}
.help p {{ margin: 0; font-size: 14px; color: rgba(255, 255, 255, .86); }}
.help a {{ flex: none; padding: 11px 16px; border-radius: 14px; background: {YELLOW}; color: {INK}; font: 700 14px/1 DMSans; }}

/* Missions */
.missions {{ display: grid; grid-template-columns: 1.12fr 1fr; gap: 16px; margin-top: 22px; }}
.missions section {{ padding: 16px 18px 14px; border-radius: 20px; background: #fff; border: 1.5px solid #E6E0D2; }}
.missions section.tall {{ grid-row: span 2; }}
.missions h2 {{ display: flex; align-items: center; justify-content: space-between; margin: 0 0 10px; font: 700 19px/1 Bricolage; }}
.missions h2 span {{ padding: 5px 9px; border-radius: 9px; background: var(--accent); color: var(--on); font: 700 11px/1 DMSans; letter-spacing: .6px; }}
.missions label {{ display: flex; gap: 11px; align-items: flex-start; padding: 10.5px 0; font-size: 14.4px; line-height: 1.36;
  border-top: 1px solid #F0EBDD; }}
.missions label:first-of-type {{ border-top: 0; }}
.missions .box {{ flex: none; width: 19px; height: 19px; margin-top: -1px; border-radius: 6px; border: 2px solid var(--accent-text); background: #fff; }}
.done {{ margin-top: 16px; padding: 16px 20px; border-radius: 20px; background: {YELLOW}; color: {INK}; }}
.done h3 {{ margin: 0 0 4px; font: 700 20px/1.15 Bricolage; }}
.done p {{ margin: 0; font-size: 14px; line-height: 1.4; }}
"""


def role_style(role):
    _, accent, on, tint = ROLES[role]
    # Yellow is too light to read as text on white, so text uses a darker tone.
    accent_text = "#8A5F00" if role == "kasir" else accent
    return f"--accent:{accent};--on:{on};--tint:{tint};--accent-text:{accent_text}"


def device(item, pins=True):
    marks = ""
    if pins:
        for number, (x, y, _) in enumerate(item["pins"], start=1):
            left = x / PREVIEW_W * 100
            top = (y / PREVIEW_H * RAW_H - STATUS_BAR) / (RAW_H - STATUS_BAR) * 100
            marks += f'<span class="pin" style="left:{left:.2f}%;top:{top:.2f}%">{number}</span>'
    source = (SHOTS / f"{item['name']}.jpg").as_uri()
    return f'<div class="device"><div class="screen"><img src="{source}">{marks}</div></div>'


def legend(item):
    rows = "".join(f'<li><span class="pin">{number}</span><span>{text}</span></li>'
                   for number, (_, _, text) in enumerate(item["pins"], start=1))
    return f'<ol class="legend">{rows}</ol>'


def header(spec, number):
    label = ROLES[spec["role"]][0]
    crumb = f'<span class="crumb">{html.escape(spec["path"])}</span>' if spec["path"] else ""
    return f"""<div class="head"><span class="tab"><i>{number}</i>{label}</span>{crumb}</div>
<h1>{spec['title']}</h1><p class="intro">{spec['intro']}</p>"""


def footer(number):
    return f"""<div class="foot"><span class="mark">warmad<span>Buku panduan</span></span>
<a class="home" href="#isi">Daftar isi</a><span class="num">{number}</span></div>"""


def tip(spec, low=False):
    if not spec["tip"]:
        return ""
    return f'<div class="tip{" low" if low else ""}"><em>Tips</em><span>{spec["tip"]}</span></div>'


def render_duo(spec, number):
    first, second = spec["shots"]
    columns = ""
    for index, item in enumerate((first, second), start=1):
        columns += f"""<div class="col"><div class="step"><i>{index}</i>{item['step']}</div>
{device(item)}{legend(item)}</div>"""
        if index == 1:
            columns += f'<div class="next">{ARROW}</div>'
    return f"""{header(spec, number)}<div class="duo">{columns}</div>{tip(spec, low=True)}"""


def render_tour(spec, number):
    item = spec["shots"][0]
    return f"""{header(spec, number)}<div class="tour">{device(item)}<div>{legend(item)}{tip(spec)}</div></div>"""


def section_pages(pages, role):
    return [(number, spec) for number, spec in pages if spec["role"] == role and spec["kind"] != "divider"]


def render_divider(spec, number, pages):
    label = ROLES[spec["role"]][0]
    order = ["pemilik", "kasir", "pembeli"].index(spec["role"]) + 1
    links = "".join(f'<a href="#p{n}"><span>{s["toc"]}</span><b>{n}</b></a>'
                    for n, s in section_pages(pages, spec["role"]))
    return f"""<div class="big">0{order}</div><div class="label">Bagian {order}</div><h1>{spec['title']}</h1>
<p class="sub">{spec['intro']}</p><div class="list">{links}</div>
<div class="stage">{device(spec['shots'][0], pins=False)}</div>"""


def render_cover(pages):
    logo = (BRAND / "warmad-splash-dark.svg").as_uri()
    openers = {s["role"]: n for n, s in pages if s["kind"] == "divider"}
    notes = {"pemilik": "Kasir, stok, kas, laporan", "kasir": "Gabung dan bantu jaga warung",
             "pembeli": "Peta warung dan cari barang"}
    roles = ""
    for role in ("pemilik", "kasir", "pembeli"):
        label, accent, on, _ = ROLES[role]
        roles += f"""<a href="#p{openers[role]}"><i style="background:{accent};color:{on}">{label[0]}</i>
<span>{label if role != 'pemilik' else 'Pemilik warung'}<small>{notes[role]}</small></span><span class="go">{ARROW}</span></a>"""
    return f"""<div class="page cover"><div class="awning"></div><img class="logo" src="{logo}">
<div class="kicker">Buku panduan</div><h1>Cara pakai Warmad</h1>
<p class="sub">Panduan bergambar untuk pemilik warung, kasir, dan pembeli. Ikuti nomor pada tiap gambar.</p>
<div class="roles">{roles}</div>
<div class="stage">{device({'name': 'o_beranda', 'pins': ()}, pins=False)}</div>
<div class="ver">Untuk aplikasi Warmad versi {APP_VERSION}</div></div>"""


def render_toc(pages):
    blocks = ""
    for role, wide in (("pemilik", True), ("mulai", False), ("kasir", False), ("pembeli", False), ("semua", False)):
        label = {"mulai": "Mulai dari sini", "pemilik": "Pemilik warung", "kasir": "Kasir",
                 "pembeli": "Pembeli", "semua": "Untuk semua"}[role]
        rows = "".join(f'<a href="#p{n}"><span>{s["toc"]}</span><u></u><b>{n}</b></a>'
                       for n, s in section_pages(pages, role))
        blocks += f"""<section class="{'wide' if wide else ''}" style="{role_style(role)}">
<h2><i></i>{label}</h2>{rows}</section>"""
    return f"""<div class="page" id="isi" style="{role_style('mulai')}"><div class="awning"></div>
<div class="head"><span class="tab"><i>2</i>Daftar isi</span></div>
<h1>Mau belajar yang mana?</h1>
<p class="intro">Ketuk judul untuk langsung ke halamannya. Tombol <b>Daftar isi</b> di bawah tiap halaman membawamu kembali ke sini.</p>
<div class="how"><div><span class="pin">1</span><span>Nomor kuning di gambar cocok dengan nomor di penjelasannya.</span></div>
<div><span class="box"></span><span>Kotak di Kartu misi untuk dicentang setelah mencoba.</span></div></div>
<div class="toc">{blocks}</div>{footer(2)}</div>"""


def render_tips(spec, number):
    palette = [(GREEN, "#fff"), (YELLOW, INK), ("#B4470F", "#fff")]
    cards = ""
    for index, (title, body) in enumerate(TIPS):
        background, text = palette[index % 3]
        cards += f"""<article><i style="background:{background};color:{text}">{index + 1}</i>
<h3>{title}</h3><p>{body}</p></article>"""
    return f"""{header(spec, number)}<div class="cards">{cards}</div>
<div class="help"><div><h3>Ada yang macet atau membingungkan?</h3>
<p>Ceritakan apa yang kamu ketuk dan apa yang terjadi. Tangkapan layar sangat membantu.</p></div>
<a href="mailto:benevology@gmail.com">benevology@gmail.com</a></div>"""


def render_missions(spec, number):
    blocks = ""
    for role in ("pemilik", "kasir", "pembeli"):
        label = "Pemilik warung" if role == "pemilik" else ROLES[role][0]
        rows = "".join(f'<label><span class="box"></span><span>{text}</span></label>' for text in MISSIONS[role])
        blocks += f"""<section class="{'tall' if role == 'pemilik' else ''}" style="{role_style(role)}">
<h2>{label}<span>{len(MISSIONS[role])} MISI</span></h2>{rows}</section>"""
    return f"""{header(spec, number)}<div class="missions">{blocks}</div>
<div class="done"><h3>Semua tercentang? Terima kasih.</h3>
<p>Kirim masukanmu ke <b>benevology@gmail.com</b>: apa yang mudah, apa yang membingungkan, dan apa yang belum ada.</p></div>"""


def build_html():
    # Page 1 is the cover and page 2 the contents.
    pages = list(enumerate(PAGES, start=3))
    body = render_cover(pages) + render_toc(pages)
    for number, spec in pages:
        kind = spec["kind"]
        if kind == "duo":
            inner = render_duo(spec, number)
        elif kind == "tour":
            inner = render_tour(spec, number)
        elif kind == "divider":
            inner = render_divider(spec, number, pages)
        elif kind == "tips":
            inner = render_tips(spec, number)
        else:
            inner = render_missions(spec, number)
        awning = "" if kind == "divider" else '<div class="awning"></div>'
        body += f"""<div class="page {kind if kind == 'divider' else ''}" id="p{number}" style="{role_style(spec['role'])}">
{awning}{inner}{footer(number)}</div>"""
    return f'<!doctype html><html lang="id"><meta charset="utf-8"><title>Buku Panduan Warmad</title><style>{CSS}</style>{body}</html>'


def print_pdf(document):
    with tempfile.TemporaryDirectory() as work:
        source = pathlib.Path(work) / "manual.html"
        source.write_text(document, encoding="utf-8")
        OUT.unlink(missing_ok=True)
        chrome = subprocess.Popen(
            [CHROME, "--headless=new", "--disable-gpu", "--allow-file-access-from-files",
             f"--user-data-dir={work}/profile", "--no-pdf-header-footer", "--virtual-time-budget=8000",
             f"--print-to-pdf={OUT}", source.as_uri()],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Headless Chrome writes the file and then sometimes fails to exit, so
        # wait for the file to stop growing rather than for the process.
        deadline = time.monotonic() + 120
        size = -1
        while time.monotonic() < deadline and chrome.poll() is None:
            current = OUT.stat().st_size if OUT.exists() else 0
            if current > 0 and current == size:
                break
            size = current
            time.sleep(2)
        if chrome.poll() is None:
            chrome.kill()
        chrome.wait()
        if not OUT.exists() or OUT.stat().st_size == 0:
            raise SystemExit("Chrome did not write the PDF")
        print(OUT.relative_to(ROOT), f"{OUT.stat().st_size / 1e6:.1f} MB")


def main():
    prepare_shots()
    missing = sorted({item["name"] for spec in PAGES for item in spec["shots"]
                      if not (SHOTS / f"{item['name']}.jpg").exists()})
    if missing:
        raise SystemExit(f"Missing screenshots in {SHOTS.relative_to(ROOT)}: {', '.join(missing)}")
    print_pdf(build_html())


if __name__ == "__main__":
    main()
