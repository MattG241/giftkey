"""
Generates the demo barcodes App Review asks for under Guideline 2.1(a).

    python tools/make_demo_barcodes.py            # write the PNGs
    python tools/make_demo_barcodes.py --verify   # write them, then decode them back

Apple cannot assess a scanner app without something to scan, and "point it at any
product barcode" is not an answer a reviewer working from a desk can act on. This
writes a one-page sheet the reviewer can display on a second screen or print, plus
one full-bleed PNG per code for scanning off a monitor, into `docs/review/`.

The four codes are chosen to exercise the whole pipeline, not just a happy path:

  1. Code 128, 16 digits  - a realistic third-party gift card. Passes the
                            "Gift card (8-20 digits)" validation preset.
  2. Code 128, 8 digits   - the short end of the same preset.
  3. EAN-13               - a product barcode. Thirteen digits, so it also passes the
                            gift card preset; switch the preset to a custom
                            `^[0-9]{8,12}$` (or turn on Strip check digit) to watch a
                            code get rejected and the keyboard shake.
  4. QR                   - non-numeric payload. Rejected by any of the numeric
                            presets, which is the guard rail the app exists for.

Everything is drawn from the symbology specs rather than pulled from a barcode
library so the output is reproducible and has no build-time dependency beyond
Pillow (already used by `make_icon.py`) and segno for the QR matrix. `--verify`
decodes the written PNGs with zxing-cpp - an independent decoder, so a mistake in
the tables below fails the run instead of shipping an unscannable image:

    pip install pillow segno zxing-cpp

Module width and quiet zones are deliberately generous. A reviewer is scanning off
a laptop screen at whatever brightness they have, not off print.
"""

from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path(__file__).resolve().parent.parent / "docs" / "review"

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
INK = (26, 28, 31)          # matches docs/index.html --fg
MUTED = (92, 99, 110)       # matches docs/index.html --muted
BLUE = (22, 115, 229)       # matches AccentColor
PANEL = (245, 247, 249)
RULE = (227, 230, 234)

MODULE = 6                  # px per narrowest bar
BAR_HEIGHT = 260
QUIET = 12 * MODULE         # Code 128 wants >= 10 modules; give it 12
QR_MODULE = 12
QR_QUIET = 4 * QR_MODULE


# --------------------------------------------------------------------------- Code 128

# Widths of the six alternating bars/spaces (bar, space, bar, space, bar, space) for
# each of the 103 data values, then Start A/B/C. The stop pattern has seven.
CODE128_PATTERNS = [
    "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312",
    "132212", "221213", "221312", "231212", "112232", "122132", "122231", "113222",
    "123122", "123221", "223211", "221132", "221231", "213212", "223112", "312131",
    "311222", "321122", "321221", "312212", "322112", "322211", "212123", "212321",
    "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
    "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121",
    "313121", "211331", "231131", "213113", "213311", "213131", "311123", "311321",
    "331121", "312113", "312311", "332111", "314111", "221411", "431111", "111224",
    "111422", "121124", "121421", "141122", "141221", "112214", "112412", "122114",
    "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
    "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112",
    "421211", "212141", "214121", "412121", "111143", "111341", "131141", "114113",
    "114311", "411113", "411311", "113141", "114131", "311141", "411131", "211412",
    "211214", "211232",
]
CODE128_STOP = "2331112"
START_B = 104


def code128_modules(text: str) -> list[int]:
    """1/0 modules for `text` in Code Set B, including start, check digit and stop."""
    for character in text:
        if not 32 <= ord(character) <= 126:
            raise ValueError(f"Code Set B cannot encode {character!r}")

    values = [ord(character) - 32 for character in text]
    checksum = START_B
    for position, value in enumerate(values, start=1):
        checksum += position * value
    checksum %= 103

    patterns = [CODE128_PATTERNS[START_B]]
    patterns += [CODE128_PATTERNS[value] for value in values]
    patterns += [CODE128_PATTERNS[checksum], CODE128_STOP]
    return widths_to_modules("".join(patterns))


def widths_to_modules(widths: str) -> list[int]:
    """"212222..." - alternating bar/space run lengths - into a flat list of 1s and 0s."""
    modules: list[int] = []
    for index, width in enumerate(widths):
        modules += [1 if index % 2 == 0 else 0] * int(width)
    return modules


# ---------------------------------------------------------------------------- EAN-13

EAN_L = ["0001101", "0011001", "0010011", "0111101", "0100011",
         "0110001", "0101111", "0111011", "0110111", "0001011"]
EAN_G = ["0100111", "0110011", "0011011", "0100001", "0011101",
         "0111001", "0000101", "0010001", "0001001", "0010111"]
EAN_R = ["1110010", "1100110", "1101100", "1000010", "1011100",
         "1001110", "1010000", "1000100", "1001000", "1110100"]
EAN_PARITY = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
              "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]


def ean13_check_digit(twelve: str) -> str:
    total = sum(int(digit) * (3 if index % 2 else 1) for index, digit in enumerate(twelve))
    return str((10 - total % 10) % 10)


def ean13_modules(thirteen: str) -> list[int]:
    if len(thirteen) != 13 or not thirteen.isdigit():
        raise ValueError(f"EAN-13 needs thirteen digits, got {thirteen!r}")
    if ean13_check_digit(thirteen[:12]) != thirteen[12]:
        raise ValueError(f"bad check digit on {thirteen}")

    parity = EAN_PARITY[int(thirteen[0])]
    bits = "101"
    for digit, side in zip(thirteen[1:7], parity):
        bits += (EAN_L if side == "L" else EAN_G)[int(digit)]
    bits += "01010"
    for digit in thirteen[7:]:
        bits += EAN_R[int(digit)]
    bits += "101"
    return [int(bit) for bit in bits]


# ---------------------------------------------------------------------------- drawing

def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{name}", size)
    except OSError:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            return ImageFont.load_default(size=size)


def linear_image(modules: list[int], caption: str) -> Image.Image:
    """A 1-D barcode with its quiet zones and human-readable text below it."""
    text_font = font(46)
    text_height = 70
    width = len(modules) * MODULE + QUIET * 2
    height = BAR_HEIGHT + text_height + QUIET

    image = Image.new("RGB", (width, height), WHITE)
    draw = ImageDraw.Draw(image)
    for index, module in enumerate(modules):
        if module:
            x = QUIET + index * MODULE
            draw.rectangle([x, QUIET // 2, x + MODULE - 1, QUIET // 2 + BAR_HEIGHT], fill=BLACK)

    draw.text((width // 2, QUIET // 2 + BAR_HEIGHT + 14), caption,
              font=text_font, fill=BLACK, anchor="ma")
    return image


def qr_image(payload: str) -> Image.Image:
    import segno

    matrix = [list(row) for row in segno.make(payload, error="h").matrix]
    text_font = font(46)
    side = len(matrix) * QR_MODULE + QR_QUIET * 2
    # The payload can be wider than the symbol; widen the canvas rather than clip it.
    width = max(side, int(text_font.getlength(payload)) + QR_QUIET * 2)
    left = (width - side) // 2
    image = Image.new("RGB", (width, side + 70), WHITE)
    draw = ImageDraw.Draw(image)
    for row, cells in enumerate(matrix):
        for column, cell in enumerate(cells):
            if cell:
                x = left + QR_QUIET + column * QR_MODULE
                y = QR_QUIET + row * QR_MODULE
                draw.rectangle([x, y, x + QR_MODULE - 1, y + QR_MODULE - 1], fill=BLACK)

    draw.text((width // 2, side + 4), payload, font=text_font, fill=BLACK, anchor="ma")
    return image


# ------------------------------------------------------------------------- the codes

GIFT_CARD_16 = "6034551234567890"
GIFT_CARD_8 = "90210457"
PRODUCT_12 = "931007201169"
QR_PAYLOAD = "GIFTKEY-DEMO-QR"


def demo_codes() -> list[dict]:
    product_13 = PRODUCT_12 + ean13_check_digit(PRODUCT_12)
    return [
        {
            "slug": "1-code128-giftcard-16",
            "title": "1. Code 128 - gift card, 16 digits",
            "note": "The main case. Passes the \"Gift card (8-20 digits)\" filter and types "
                    "into the field you came from.",
            "value": GIFT_CARD_16,
            "format": "Code128",
            "image": lambda: linear_image(code128_modules(GIFT_CARD_16), GIFT_CARD_16),
        },
        {
            "slug": "2-code128-giftcard-8",
            "title": "2. Code 128 - gift card, 8 digits",
            "note": "The short end of the same filter. Also accepted.",
            "value": GIFT_CARD_8,
            "format": "Code128",
            "image": lambda: linear_image(code128_modules(GIFT_CARD_8), GIFT_CARD_8),
        },
        {
            "slug": "3-ean13-product",
            "title": "3. EAN-13 - product barcode",
            "note": "Shows Strip check digit and UPC/EAN conversion in Settings. Turn on "
                    "\"Strip check digit\" and this types as " + product_13[:12] + ".",
            "value": product_13,
            "format": "EAN13",
            "image": lambda: linear_image(ean13_modules(product_13), product_13),
        },
        {
            "slug": "4-qr-text",
            "title": "4. QR - non-numeric payload",
            "note": "Scan this with the gift card filter on: nothing is typed, the keyboard "
                    "shakes. That rejection is the point of the app.",
            "value": QR_PAYLOAD,
            "format": "QRCode",
            "image": lambda: qr_image(QR_PAYLOAD),
        },
    ]


# ------------------------------------------------------------------------- the sheet

SHEET_WIDTH = 1600
MARGIN = 90


def wrap(text: str, text_font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    lines: list[str] = []
    line = ""
    for word in text.split():
        candidate = f"{line} {word}".strip()
        if text_font.getlength(candidate) <= max_width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def sheet(codes: list[dict]) -> Image.Image:
    title_font = font(58, bold=True)
    subtitle_font = font(30)
    card_title_font = font(36, bold=True)
    note_font = font(27)

    card_padding = 40
    gap = 44
    inner = SHEET_WIDTH - MARGIN * 2
    note_width = inner - card_padding * 2
    note_spacing = 10

    cards = []
    for code in codes:
        art = code["image"]()
        scale = min(1.0, (inner - 80) / art.width)
        if scale < 1.0:
            art = art.resize((int(art.width * scale), int(art.height * scale)), Image.LANCZOS)
        note_lines = wrap(code["note"], note_font, note_width)
        # title, note block, then the code itself
        text_height = 56 + len(note_lines) * (note_font.size + note_spacing) + 24
        cards.append({
            "code": code,
            "art": art,
            "note_lines": note_lines,
            "text_height": text_height,
            "height": card_padding * 2 + text_height + art.height,
        })

    height = (MARGIN + 210 + sum(card["height"] for card in cards)
              + gap * (len(cards) - 1) + MARGIN)
    image = Image.new("RGB", (SHEET_WIDTH, height), WHITE)
    draw = ImageDraw.Draw(image)

    draw.text((MARGIN, MARGIN), "GiftKey - demo codes for App Review",
              font=title_font, fill=INK)
    draw.text((MARGIN, MARGIN + 78),
              "Display this page on a second screen or print it, then scan the codes with "
              "the GiftKey keyboard\nor the app's Scan tab. Expected results are printed "
              "under each code.",
              font=subtitle_font, fill=MUTED)
    draw.line([MARGIN, MARGIN + 180, SHEET_WIDTH - MARGIN, MARGIN + 180], fill=RULE, width=2)

    y = MARGIN + 210
    for card in cards:
        draw.rounded_rectangle([MARGIN, y, SHEET_WIDTH - MARGIN, y + card["height"]],
                               radius=24, fill=PANEL, outline=RULE, width=2)
        draw.text((MARGIN + card_padding, y + card_padding), card["code"]["title"],
                  font=card_title_font, fill=BLUE)
        draw.multiline_text((MARGIN + card_padding, y + card_padding + 56),
                            "\n".join(card["note_lines"]),
                            font=note_font, fill=MUTED, spacing=note_spacing)
        image.paste(card["art"], ((SHEET_WIDTH - card["art"].width) // 2,
                                  y + card_padding + card["text_height"]))
        y += card["height"] + gap

    return image


# -------------------------------------------------------------------------- verifying

def verify(expectations: list[tuple[Path, list[dict]]]) -> bool:
    """Decode every written PNG with an independent decoder. Returns True if all pass."""
    try:
        import zxingcpp
    except ImportError:
        print("verify skipped: pip install zxing-cpp")
        return True

    def normalise(name: str) -> str:
        return "".join(character for character in name if character.isalnum()).lower()

    ok = True
    for path, codes in expectations:
        found = {(normalise(str(result.format)), result.text)
                 for result in zxingcpp.read_barcodes(Image.open(path))}
        missing = [f"{code['format']} {code['value']}" for code in codes
                   if (normalise(code["format"]), code["value"]) not in found]
        print(f"{'ok  ' if not missing else 'FAIL'} {path.name}: "
              f"decoded {sorted(text for _, text in found) or 'nothing'}"
              + (f" - missing {missing}" if missing else ""))
        ok = ok and not missing
    return ok


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    codes = demo_codes()

    expectations: list[tuple[Path, list[dict]]] = []
    for code in codes:
        path = OUT_DIR / f"giftkey-demo-{code['slug']}.png"
        image = code["image"]()
        image.save(path, "PNG")
        expectations.append((path, [code]))
        print(f"wrote {path}  {image.width}x{image.height}")

    sheet_path = OUT_DIR / "giftkey-demo-codes.png"
    page = sheet(codes)
    page.save(sheet_path, "PNG")
    expectations.append((sheet_path, codes))     # every code must survive the sheet too
    print(f"wrote {sheet_path}  {page.width}x{page.height}")

    if "--verify" in sys.argv:
        if not verify(expectations):
            sys.exit("demo codes did not decode - do not ship these")


if __name__ == "__main__":
    main()
