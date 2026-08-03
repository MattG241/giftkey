"""
Converts iPhone screenshots into the exact pixel dimensions App Store Connect accepts.

    python tools/resize_screenshots.py <folder-of-pngs> [output-folder]

App Store Connect's 6.5" iPhone slot takes 1242x2688 or 1284x2778 and rejects anything
else outright. Modern iPhones do not produce either of those natively - an iPhone 15/16
is 1179x2556, a 16 Pro Max is 1320x2868 - so screenshots taken on the device need
converting before they will upload.

Aspect ratios across all these devices differ by well under one percent, so a straight
resize is visually indistinguishable from letterboxing and avoids black bars. If a source
image is meaningfully the wrong shape (an iPad screenshot, say) the script says so and
pads instead of distorting.

Output files are numbered in the order they are processed, because App Store Connect
displays screenshots in filename order and the first three are what appear on the
install sheet.
"""

from pathlib import Path
import sys

from PIL import Image

TARGET = (1284, 2778)          # App Store Connect 6.5" iPhone
ASPECT_TOLERANCE = 0.02        # 2% - beyond this, pad rather than stretch


def convert(source: Path, destination: Path, index: int) -> None:
    image = Image.open(source).convert("RGB")
    src_aspect = image.width / image.height
    dst_aspect = TARGET[0] / TARGET[1]
    drift = abs(src_aspect - dst_aspect) / dst_aspect

    if drift <= ASPECT_TOLERANCE:
        out = image.resize(TARGET, Image.LANCZOS)
        note = f"resized (aspect drift {drift * 100:.2f}%)"
    else:
        # Wrong shape entirely. Fit inside and pad with the image's own corner colour so
        # the bars are not an obvious black frame.
        scale = min(TARGET[0] / image.width, TARGET[1] / image.height)
        fitted = image.resize((round(image.width * scale), round(image.height * scale)),
                              Image.LANCZOS)
        out = Image.new("RGB", TARGET, image.getpixel((0, 0)))
        out.paste(fitted, ((TARGET[0] - fitted.width) // 2,
                           (TARGET[1] - fitted.height) // 2))
        note = f"padded (aspect drift {drift * 100:.1f}% - too far to stretch)"

    target_path = destination / f"{index:02d}-{source.stem}.png"
    out.save(target_path, "PNG")
    print(f"  {source.name}  {image.width}x{image.height}  ->  {target_path.name}  {note}")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    source_dir = Path(sys.argv[1])
    if not source_dir.is_dir():
        sys.exit(f"not a folder: {source_dir}")

    destination = Path(sys.argv[2]) if len(sys.argv) > 2 else source_dir / "appstore"
    destination.mkdir(parents=True, exist_ok=True)

    images = sorted(p for p in source_dir.iterdir()
                    if p.suffix.lower() in {".png", ".jpg", ".jpeg"})
    if not images:
        sys.exit(f"no images found in {source_dir}")

    print(f"Converting {len(images)} screenshot(s) to {TARGET[0]}x{TARGET[1]}:")
    for index, image_path in enumerate(images, start=1):
        convert(image_path, destination, index)

    print(f"\nDone. Upload everything in: {destination}")
    print("App Store Connect shows them in filename order - the first three appear on "
          "the install sheet.")


if __name__ == "__main__":
    main()
