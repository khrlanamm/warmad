"""Draws the barcode scanner screenshot used in the manual.

The emulator's camera shows a virtual living room, which says nothing about
scanning. This script draws what a phone sees when it is held over the back
of a noodle pack on a wooden counter, with the scanner's own controls on top
(the close button and the hint at the bottom), and saves it over
docs/manual/shots/o_scan.jpg.

    python3 docs/manual/make_scan_shot.py     # needs Pillow and Chrome

The pack is made up: no brand, and a barcode number that belongs to no
product. Run make_manual.py afterwards to put the picture into the PDF.
"""

import pathlib
import subprocess
import tempfile
import time

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
TARGET = ROOT / "docs" / "manual" / "shots" / "o_scan.jpg"
FONTS = ROOT / "assets" / "fonts"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Size of the screenshots in shots/: 1080x2282 shrunk to 640 wide.
WIDTH, HEIGHT = 640, 1352

# First twelve digits of the barcode. 899 is the GS1 prefix of Indonesia.
BARCODE = "899700012345"

L_CODES = ["0001101", "0011001", "0010011", "0111101", "0100011",
           "0110001", "0101111", "0111011", "0110111", "0001011"]
G_CODES = ["0100111", "0110011", "0011011", "0100001", "0011101",
           "0111001", "0000101", "0010001", "0001001", "0010111"]
PARITY = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
          "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]


def ean13(first_twelve):
    """Returns the thirteen digits and the 95 modules (1 is a bar)."""
    digits = [int(char) for char in first_twelve]
    total = sum(digit * (3 if index % 2 else 1) for index, digit in enumerate(digits))
    digits.append((10 - total % 10) % 10)
    left = "".join((L_CODES if kind == "L" else G_CODES)[digit]
                   for kind, digit in zip(PARITY[digits[0]], digits[1:7]))
    right = "".join("".join("1" if bit == "0" else "0" for bit in L_CODES[digit])
                    for digit in digits[7:])
    return "".join(map(str, digits)), f"101{left}01010{right}101"


def barcode_svg():
    number, modules = ean13(BARCODE)
    unit, height = 2.6, 96
    bars = ""
    for index, bit in enumerate(modules):
        if bit == "1":
            # Guard bars at both ends and in the middle reach lower.
            guard = index < 3 or 45 <= index < 50 or index >= 92
            bars += (f'<rect x="{18 + index * unit:.1f}" y="10" width="{unit}" '
                     f'height="{height + (12 if guard else 0)}"/>')
    width = 36 + 95 * unit
    text = (f'<text x="6" y="{height + 31}">{number[0]}</text>'
            f'<text x="{18 + 5 * unit:.1f}" y="{height + 31}" textLength="{38 * unit:.1f}">{number[1:7]}</text>'
            f'<text x="{18 + 51 * unit:.1f}" y="{height + 31}" textLength="{38 * unit:.1f}">{number[7:]}</text>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height + 40}" '
            f'font-family="Menlo, monospace" font-size="19" fill="#111">{bars}{text}</svg>')


def page():
    lines = "".join(f'<i style="width:{width}%"></i>' for width in (96, 88, 93, 70))
    rows = "".join(f"<tr><td>{label}</td><td>{value}</td></tr>" for label, value in (
        ("Energi total", "380 kkal"), ("Lemak total", "14 g"), ("Protein", "8 g"),
        ("Karbohidrat", "54 g"), ("Garam", "1,2 g")))
    return f"""<!doctype html><meta charset="utf-8"><style>
@font-face {{ font-family: Bricolage; src: url("{(FONTS / 'BricolageGrotesque.ttf').as_uri()}"); font-weight: 200 800; }}
@font-face {{ font-family: DMSans; src: url("{(FONTS / 'DMSans.ttf').as_uri()}"); font-weight: 100 1000; }}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; overflow: hidden; }}
body {{ position: relative; width: {WIDTH}px; height: {HEIGHT}px; font-family: DMSans, sans-serif;
  /* The counter: warm wood with plank seams. */
  background:
    repeating-linear-gradient(94deg, transparent 0 196px, rgba(40, 22, 8, .5) 196px 199px),
    repeating-linear-gradient(92deg, rgba(255, 220, 170, .05) 0 3px, transparent 3px 11px),
    linear-gradient(170deg, #8a5c33, #a8733f 45%, #7b4f2a); }}
/* Goods on the shelf behind, out of focus. */
.shelf {{ position: absolute; left: -40px; right: -40px; top: -60px; height: 330px; filter: blur(22px);
  background: linear-gradient(90deg, #c33 0 14%, #f2c230 14% 31%, #2f7d4f 31% 47%, #e9e2d0 47% 63%, #2a5ea8 63% 80%, #d6772a 80%);
  opacity: .82; }}
.edge {{ position: absolute; left: 0; right: 0; top: 232px; height: 90px; filter: blur(10px);
  background: linear-gradient(#3a2412, rgba(58, 36, 18, 0)); }}
.pack {{ position: absolute; left: 76px; top: 286px; width: 492px; height: 716px; transform: rotate(-4deg);
  border-radius: 10px; padding: 62px 34px 0; color: #2b2b2b;
  background: linear-gradient(105deg, #f3eee0, #fbf8ef 38%, #e9e2cf 72%, #f4efe1);
  box-shadow: 0 26px 46px rgba(20, 10, 0, .55), 0 2px 0 rgba(255, 255, 255, .6) inset; }}
/* Crimped seals at both ends of the wrapper. */
.pack::before, .pack::after {{ content: ""; position: absolute; left: 0; right: 0; height: 40px;
  background: repeating-linear-gradient(90deg, rgba(0, 0, 0, .13) 0 2px, rgba(255, 255, 255, .5) 2px 7px), #d9d1bc; }}
.pack::before {{ top: 0; border-radius: 10px 10px 0 0; }}
.pack::after {{ bottom: 0; border-radius: 0 0 10px 10px; }}
.band {{ display: flex; align-items: baseline; justify-content: space-between; margin: 0 -34px; padding: 12px 34px;
  background: #c6281d; color: #fff; }}
.band b {{ font: 800 30px/1 Bricolage; letter-spacing: -.5px; }}
.band span {{ font: 600 13px/1 DMSans; letter-spacing: 1px; text-transform: uppercase; }}
h4 {{ margin: 22px 0 8px; font: 700 14px/1 DMSans; letter-spacing: 1.2px; text-transform: uppercase; }}
.text i {{ display: block; height: 7px; margin-bottom: 8px; border-radius: 4px; background: #9a968a; }}
.split {{ display: grid; grid-template-columns: 1fr 1fr; gap: 26px; }}
table {{ width: 100%; border-collapse: collapse; font: 500 12px/1.2 DMSans; }}
td {{ padding: 4px 6px; border: 1.5px solid #6d6a61; }}
td:last-child {{ text-align: right; }}
.code {{ display: grid; place-items: center; margin: 26px auto 0; width: 310px; padding: 8px 0 4px; background: #fff;
  border-radius: 4px; }}
.small {{ margin-top: 14px; font: 500 10.5px/1.4 DMSans; color: #5d5a52; text-align: center; }}
/* Light on the plastic, the darker corners of a phone camera, and grain. */
.glare {{ position: absolute; inset: 0; border-radius: 10px;
  background: linear-gradient(118deg, transparent 30%, rgba(255, 255, 255, .34) 44%, transparent 56%); }}
.thumb {{ position: absolute; left: -46px; top: 846px; width: 190px; height: 420px; border-radius: 95px 95px 60px 60px;
  transform: rotate(38deg); background: linear-gradient(100deg, #b97f5b, #d7a27d 45%, #b47a57);
  box-shadow: 0 18px 30px rgba(20, 10, 0, .45); }}
.thumb::after {{ content: ""; position: absolute; left: 42px; top: 26px; width: 106px; height: 118px;
  border-radius: 53px 53px 40px 40px; background: linear-gradient(#f1d3c0, #e2b9a3); opacity: .85; }}
.dark {{ position: absolute; inset: 0; background: radial-gradient(ellipse at 50% 46%, transparent 48%, rgba(0, 0, 0, .5)); }}
.grain {{ position: absolute; inset: 0; opacity: .16; mix-blend-mode: overlay; }}
/* The scanner's own controls. */
.close {{ position: absolute; left: 18px; top: 18px; width: 64px; height: 64px; border-radius: 50%;
  display: grid; place-items: center; background: rgba(40, 40, 40, .78); }}
.hint {{ position: absolute; left: 0; right: 0; top: 1243px; text-align: center; color: #fff;
  font: 600 25px/1.3 DMSans; letter-spacing: .2px; text-shadow: 0 1px 6px rgba(0, 0, 0, .7); }}
</style>
<div class="shelf"></div><div class="edge"></div>
<div class="pack">
  <div class="band"><b>MI GORENG</b><span>Mi instan 85 g</span></div>
  <div class="split">
    <div><h4>Cara memasak</h4><div class="text">{lines}</div>
      <h4>Komposisi</h4><div class="text">{lines}</div></div>
    <div><h4>Nilai gizi</h4><table>{rows}</table></div>
  </div>
  <div class="code">{barcode_svg()}</div>
  <div class="small">Simpan di tempat kering dan sejuk · Diproduksi di Indonesia</div>
  <div class="glare"></div>
</div>
<div class="thumb"></div>
<div class="dark"></div>
<svg class="grain" width="{WIDTH}" height="{HEIGHT}"><filter id="n"><feTurbulence type="fractalNoise"
  baseFrequency=".9" numOctaves="2" stitchTiles="stitch"/></filter><rect width="100%" height="100%" filter="url(#n)"/></svg>
<div class="close"><svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="#fff" stroke-width="2.2"
  stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></div>
<div class="hint">Arahkan kamera ke barcode barang</div>"""


def main():
    with tempfile.TemporaryDirectory() as work:
        source = pathlib.Path(work) / "scan.html"
        capture = pathlib.Path(work) / "scan.png"
        source.write_text(page(), encoding="utf-8")
        chrome = subprocess.Popen(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
             f"--user-data-dir={work}/profile", "--force-device-scale-factor=1",
             f"--window-size={WIDTH},{HEIGHT}", "--virtual-time-budget=4000",
             f"--screenshot={capture}", source.as_uri()],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Headless Chrome writes the screenshot and then sometimes fails to
        # exit, so wait for the file rather than for the process.
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline and chrome.poll() is None:
            if capture.exists() and capture.stat().st_size > 0:
                time.sleep(1.5)
                break
            time.sleep(0.3)
        if chrome.poll() is None:
            chrome.kill()
        chrome.wait()
        if not capture.exists():
            raise SystemExit("Chrome did not render the scanner picture")
        image = Image.open(capture).convert("RGB").crop((0, 0, WIDTH, HEIGHT))
        image.save(TARGET, "JPEG", quality=90, optimize=True)
        print(TARGET.relative_to(ROOT), image.size)


if __name__ == "__main__":
    main()
