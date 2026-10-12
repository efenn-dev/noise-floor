"""Turn generated item pictures into transparent inventory icons, plus a contact sheet to review them.

Codex draws each item on a flat dark background (see the prompt in the M10b devlog entry). This removes
the background colour only where it connects to the image border, so dark parts inside the item stay,
softens the cut edge, recentres the item with a margin and saves a square RGBA PNG.

Usage:
    python tools/art/make_icon.py .shots/icons_raw assets/icons
    -> assets/icons/<id>.png (256 px) and .shots/icons_sheet.png
"""

import argparse
import logging
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

log = logging.getLogger("make_icon")


def cut_out(img: Image.Image, tolerance: float) -> Image.Image:
    """RGBA copy of `img` with the border-connected background made transparent."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    border = np.concatenate([rgb[:4].reshape(-1, 3), rgb[-4:].reshape(-1, 3),
                             rgb[:, :4].reshape(-1, 3), rgb[:, -4:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    near_bg = np.linalg.norm(rgb - bg, axis=2) < tolerance
    region = np.zeros_like(near_bg)
    region[0, :] = near_bg[0, :]
    region[-1, :] = near_bg[-1, :]
    region[:, 0] |= near_bg[:, 0]
    region[:, -1] |= near_bg[:, -1]
    while True:  # grow from the border through background-coloured pixels only
        grown = region.copy()
        grown[1:] |= region[:-1]
        grown[:-1] |= region[1:]
        grown[:, 1:] |= region[:, :-1]
        grown[:, :-1] |= region[:, 1:]
        grown &= near_bg
        if (grown == region).all():
            break
        region = grown
    alpha = Image.fromarray(((~region) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out


def frame(icon: Image.Image, size: int, margin: float) -> Image.Image:
    """Crop to the visible item, then centre it on a transparent square with `margin` on each side."""
    box = icon.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox() or (0, 0, *icon.size)
    item = icon.crop(box)
    side = int(max(item.size) / (1 - 2 * margin))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(item, ((side - item.width) // 2, (side - item.height) // 2), item)
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("src", type=Path, help="folder of generated <id>.png pictures")
    parser.add_argument("dst", type=Path, help="folder for the finished icons")
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--tolerance", type=float, default=22.0, help="colour distance still counted as background")
    parser.add_argument("--margin", type=float, default=0.08)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args.dst.mkdir(parents=True, exist_ok=True)

    icons = []
    for src in sorted(args.src.glob("*.png")):
        img = Image.open(src)
        side = min(img.size)
        img = img.crop(((img.width - side) // 2, (img.height - side) // 2,
                        (img.width + side) // 2, (img.height + side) // 2)).resize((512, 512), Image.LANCZOS)
        icon = frame(cut_out(img, args.tolerance), args.size, args.margin)
        icon.save(args.dst / src.name)
        kept = np.asarray(icon.getchannel("A")).mean() / 255
        log.info("%-20s %3.0f%% opaque", src.stem, kept * 100)
        icons.append((src.stem, icon))

    # Contact sheet: each icon on a slot-coloured tile, so the cut-outs can be checked at a glance.
    cols = 6
    tile = args.size + 16
    sheet = Image.new("RGBA", (cols * tile, ((len(icons) + cols - 1) // cols) * tile), (40, 42, 44, 255))
    for i, (_, icon) in enumerate(icons):
        x, y = (i % cols) * tile + 8, (i // cols) * tile + 8
        sheet.paste(Image.new("RGBA", icon.size, (62, 66, 70, 255)), (x, y))
        sheet.paste(icon, (x, y), icon)
    Path(".shots").mkdir(exist_ok=True)
    sheet.save(".shots/icons_sheet.png")
    log.info("sheet -> .shots/icons_sheet.png")


if __name__ == "__main__":
    main()
