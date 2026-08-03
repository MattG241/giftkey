"""
Generates the GiftKey app icon.

    python tools/make_icon.py

Drawn programmatically rather than exported from a design tool so the App Store
requirements are guaranteed rather than hoped for:

  - exactly 1024 x 1024
  - RGB mode with NO alpha channel (transparency is an automatic rejection)
  - square corners, colour running to all four edges (iOS applies its own mask;
    corners baked into the PNG produce a visible double-rounded edge)
  - thick strokes only, so the mark survives being scaled to 40x40 in Settings

Design: five white bars of varying widths reading as a barcode, cut by a single
amber scan line. The blue matches the app's AccentColor so the icon and the UI
agree. Bar widths and the scan line thickness are chosen so that at 40x40 the
narrowest bar is still ~2px and the scan line ~1.7px - below that they vanish.

Run `python tools/make_icon.py --preview` to also write a contact sheet showing
every size iOS actually renders, for checking small-size legibility.
"""

from pathlib import Path
import sys

from PIL import Image, ImageDraw

SIZE = 1024

BLUE = (22, 115, 229)      # #1673E5 - matches Assets.xcassets/AccentColor
WHITE = (255, 255, 255)
AMBER = (255, 176, 32)     # #FFB020 - the scan line

BAR_WIDTHS = [90, 55, 120, 60, 79]
GAP = 55
BLOCK_TOP = 322
BLOCK_BOTTOM = 702
BAR_RADIUS = 10

SCAN_Y = 512
SCAN_THICKNESS = 44
SCAN_OVERHANG = 40         # how far the scan line extends past the bars

ICON_PATH = Path(__file__).resolve().parent.parent \
    / "GiftKey" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"


def build() -> Image.Image:
    icon = Image.new("RGB", (SIZE, SIZE), BLUE)
    draw = ImageDraw.Draw(icon)

    block_width = sum(BAR_WIDTHS) + GAP * (len(BAR_WIDTHS) - 1)
    x = left_edge = (SIZE - block_width) // 2

    for width in BAR_WIDTHS:
        draw.rounded_rectangle(
            [x, BLOCK_TOP, x + width, BLOCK_BOTTOM],
            radius=BAR_RADIUS,
            fill=WHITE,
        )
        x += width + GAP

    right_edge = x - GAP

    draw.rounded_rectangle(
        [left_edge - SCAN_OVERHANG, SCAN_Y - SCAN_THICKNESS // 2,
         right_edge + SCAN_OVERHANG, SCAN_Y + SCAN_THICKNESS // 2],
        radius=SCAN_THICKNESS // 2,
        fill=AMBER,
    )

    return icon


def contact_sheet(icon: Image.Image) -> Image.Image:
    """The icon at the sizes iOS actually renders, for a legibility check."""
    sizes = [180, 120, 87, 60, 40]
    pad = 28
    width = sum(sizes) + pad * (len(sizes) + 1)
    height = max(sizes) + pad * 2
    sheet = Image.new("RGB", (width, height), (236, 238, 241))

    x = pad
    for s in sizes:
        sheet.paste(icon.resize((s, s), Image.LANCZOS), (x, (height - s) // 2))
        x += s + pad
    return sheet


def main() -> None:
    icon = build()

    # Fail loudly rather than shipping a bundle App Store Connect will reject.
    assert icon.size == (SIZE, SIZE), f"wrong size: {icon.size}"
    assert icon.mode == "RGB", f"alpha channel present: mode={icon.mode}"

    ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    icon.save(ICON_PATH, "PNG")
    print(f"wrote {ICON_PATH}  {icon.size[0]}x{icon.size[1]} {icon.mode}")

    if "--preview" in sys.argv:
        preview = ICON_PATH.parent / "icon-preview-sizes.png"
        contact_sheet(icon).save(preview, "PNG")
        print(f"wrote {preview}")


if __name__ == "__main__":
    main()
