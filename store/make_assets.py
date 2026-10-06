"""Builds the Play Store listing images from raw emulator screenshots.

Each image is an HTML page (headline, device mockup, brand colours and
fonts) rendered to PNG with headless Chrome.

    python3 -I store/make_assets.py

Input:  store/raw/*.png   screenshots taken on the emulator
        (p*.png at 1080x2424 for phone, t*.png at 1600x2560 for tablet)
Output: store/out/        feature graphic, phone and tablet screenshots
"""

import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "store" / "raw"
OUT = ROOT / "store" / "out"
FONTS = ROOT / "assets" / "fonts"
BRAND = ROOT / "assets" / "brand"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

GREEN, YELLOW, CREAM, INK = "#1F6B45", "#F4B51E", "#FBF7EE", "#1A2B22"

# Height of the Android status bar in the raw screenshots. It is cropped
# away so the emulator's clock and icons do not show in the listing.
PHONE = {"width": 1080, "height": 2424, "status_bar": 142}
TABLET = {"width": 1600, "height": 2560, "status_bar": 141}

# (raw file, headline, sub line)
PHONE_SHOTS = [
    ("p1_beranda", "Kas warung selalu jelas",
     "Penjualan, stok, dan uang di laci tercatat di satu tempat."),
    ("p2_kasir", "Catat penjualan dalam hitungan detik",
     "Stok berkurang dan kas bertambah sendiri, juga saat tanpa internet."),
    ("p5_tutupkas", "Cocokkan uang di laci dengan catatan",
     "Tutup kas menunjukkan selisihnya saat itu juga."),
    ("p3_stok", "Tahu barang hampir habis lebih dulu",
     "Sebelum pembeli yang menanyakannya."),
    ("p4_detail", "Saran kapan belanja dan berapa banyak",
     "Dihitung dari penjualan nyata di warungmu."),
    ("p6_laporan", "Arus kas harian, mingguan, bulanan",
     "Bagikan laporan sebagai PDF atau Excel."),
    ("p7_peta", "Pembeli menemukan warungmu di peta",
     "Warung hanya tampil kalau pemiliknya mengizinkan."),
    ("p8_cari", "Cari barang, lihat warung yang punya",
     "Diurutkan dari yang paling dekat."),
]
TABLET_SHOTS = [
    ("t1_beranda", "Kas warung selalu jelas",
     "Penjualan, stok, dan uang di laci tercatat di satu tempat."),
    ("t2_kasir", "Catat penjualan dalam hitungan detik",
     "Stok berkurang dan kas bertambah sendiri, juga saat tanpa internet."),
    ("t6_stok", "Tahu barang hampir habis lebih dulu",
     "Sebelum pembeli yang menanyakannya."),
    ("t3_laporan", "Arus kas harian, mingguan, bulanan",
     "Bagikan laporan sebagai PDF atau Excel."),
    ("t4_peta", "Pembeli menemukan warungmu di peta",
     "Warung hanya tampil kalau pemiliknya mengizinkan."),
    ("t5_cari", "Cari barang, lihat warung yang punya",
     "Diurutkan dari yang paling dekat."),
]

BASE_CSS = f"""
@font-face {{ font-family: Bricolage; src: url("{(FONTS / 'BricolageGrotesque.ttf').as_uri()}"); font-weight: 200 800; }}
@font-face {{ font-family: DMSans; src: url("{(FONTS / 'DMSans.ttf').as_uri()}"); font-weight: 100 1000; }}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; overflow: hidden; }}
/* The yellow scalloped awning from the logo. */
.awning {{ position: absolute; top: 0; left: 0; right: 0; height: 46px; background: {YELLOW}; }}
.awning::after {{
  content: ""; position: absolute; top: 46px; left: 0; right: 0; height: 40px;
  background: radial-gradient(ellipse 45px 34px at 50% 0, {YELLOW} 98%, transparent 100%) repeat-x;
  background-size: 90px 40px;
}}
.device {{ background: {INK}; box-shadow: 0 30px 60px rgba(0, 0, 0, .28); }}
.screen {{ overflow: hidden; background: {CREAM}; }}
.screen img {{ display: block; }}
"""


def device(raw, source, width, bezel, radius):
    """A device mockup `width` px wide showing `raw` without its status bar."""
    scale = width / source["width"]
    crop = source["status_bar"] * scale
    height = (source["height"] - source["status_bar"]) * scale
    return f"""
    <div class="device" style="padding:{bezel}px;border-radius:{radius}px;width:{width + 2 * bezel}px">
      <div class="screen" style="height:{height:.1f}px;border-radius:{radius - bezel}px">
        <img src="{(RAW / (raw + '.png')).as_uri()}" style="width:{width}px;margin-top:-{crop:.1f}px">
      </div>
    </div>"""


def screenshot_page(raw, title, sub, source, dark, device_width, bezel, radius):
    background, text, muted = (GREEN, "#fff", "rgba(255,255,255,.82)") if dark else (CREAM, INK, "#5C6B62")
    return f"""<!doctype html><meta charset="utf-8"><style>{BASE_CSS}
body {{ width: 1080px; height: 1920px; background: {background}; position: relative; }}
.copy {{ position: absolute; top: 132px; left: 80px; right: 80px; text-align: center; }}
h1 {{ margin: 0; font: 700 72px/1.08 Bricolage; letter-spacing: -1.5px; color: {text}; }}
p {{ margin: 22px 0 0; font: 400 34px/1.35 DMSans; color: {muted}; }}
.stage {{ position: absolute; top: 470px; left: 0; right: 0; display: flex; justify-content: center; }}
</style><div class="awning"></div>
<div class="copy"><h1>{title}</h1><p>{sub}</p></div>
<div class="stage">{device(raw, source, device_width, bezel, radius)}</div>"""


def feature_graphic_page():
    logo = (BRAND / "warmad-splash-dark.svg").as_uri()
    return f"""<!doctype html><meta charset="utf-8"><style>{BASE_CSS}
body {{ width: 1024px; height: 500px; background: {GREEN}; position: relative; }}
.awning {{ height: 26px; }}
.awning::after {{ top: 26px; height: 26px; background-size: 64px 26px;
  background-image: radial-gradient(ellipse 32px 22px at 50% 0, {YELLOW} 98%, transparent 100%); }}
.logo {{ position: absolute; left: 44px; top: 96px; width: 330px; }}
h1 {{ position: absolute; left: 70px; top: 318px; width: 520px; margin: 0;
  font: 700 40px/1.12 Bricolage; letter-spacing: -.6px; color: #fff; }}
p {{ position: absolute; left: 70px; top: 418px; width: 520px; margin: 0;
  font: 400 21px/1.3 DMSans; color: rgba(255,255,255,.82); }}
.stage {{ position: absolute; left: 640px; top: 78px; transform: rotate(6deg); }}
</style><div class="awning"></div>
<img class="logo" src="{logo}">
<h1>Kasir, stok, dan kas warung dalam satu aplikasi</h1>
<p>Untuk warung Madura. Tetap jalan tanpa internet.</p>
<div class="stage">{device('p1_beranda', PHONE, 290, 9, 34)}</div>"""


def render(html, name, width, height, scale=1.0):
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        page = pathlib.Path(work) / "page.html"
        page.write_text(html, encoding="utf-8")
        target = OUT / f"{name}.png"
        target.unlink(missing_ok=True)
        chrome = subprocess.Popen(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--allow-file-access-from-files", f"--user-data-dir={work}/profile",
             f"--force-device-scale-factor={scale}", f"--window-size={width},{height}",
             "--virtual-time-budget=4000", f"--screenshot={target}", page.as_uri()],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Headless Chrome writes the screenshot and then sometimes fails to
        # exit, so wait for the file rather than for the process.
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline and chrome.poll() is None:
            if target.exists() and target.stat().st_size > 0:
                time.sleep(1.5)  # let Chrome finish writing
                break
            time.sleep(0.3)
        if chrome.poll() is None:
            chrome.kill()
        chrome.wait()
        if not target.exists():
            raise SystemExit(f"Chrome did not render {name}")
        print(target.relative_to(ROOT))


def main():
    render(feature_graphic_page(), "feature-graphic", 1024, 500)
    for index, (raw, title, sub) in enumerate(PHONE_SHOTS, start=1):
        html = screenshot_page(raw, title, sub, PHONE, index % 2 == 1, 630, 16, 62)
        render(html, f"phone-{index}", 1080, 1920)
    for index, (raw, title, sub) in enumerate(TABLET_SHOTS, start=1):
        html = screenshot_page(raw, title, sub, TABLET, index % 2 == 1, 860, 20, 44)
        # Same page at two sizes: 1080x1920 for 7 inch, 1440x2560 for 10 inch.
        render(html, f"tablet7-{index}", 1080, 1920)
        render(html, f"tablet10-{index}", 1080, 1920, scale=4 / 3)


if __name__ == "__main__":
    main()
