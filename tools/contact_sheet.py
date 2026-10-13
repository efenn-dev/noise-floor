"""Builds .shots/tour/contact.png: a grid (four across) of the tour's shots, each scaled to 400 px wide, labelled.

Usage: python tools/contact_sheet.py <dir> "<name>|<label>" ...   (tools/tour.sh calls it)
"""
import argparse
import logging
from pathlib import Path

from PIL import Image, ImageDraw

TILE_W = 400
COLS = 4
LABEL_H = 22


def build(folder: Path, entries: list[str]) -> Path:
    """Lays the named PNGs out in a grid with their labels; a missing shot leaves a dark red tile."""
    tiles = []
    for entry in entries:
        name, _, label = entry.partition("|")
        path = folder / f"{name}.png"
        if path.exists():
            img = Image.open(path).convert("RGB")
            img = img.resize((TILE_W, round(img.height * TILE_W / img.width)))
        else:
            img = Image.new("RGB", (TILE_W, 225), (90, 0, 0))
        tiles.append((img, f"{name[:2]}  {label}" + ("" if path.exists() else "  (MISSING)")))
    tile_h = max(t[0].height for t in tiles) + LABEL_H
    rows = (len(tiles) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * TILE_W, rows * tile_h), (20, 20, 20))
    draw = ImageDraw.Draw(sheet)
    for i, (img, label) in enumerate(tiles):
        x, y = (i % COLS) * TILE_W, (i // COLS) * tile_h
        sheet.paste(img, (x, y + LABEL_H))
        draw.text((x + 6, y + 5), label, fill=(240, 240, 240))
    out = folder / "contact.png"
    sheet.save(out)
    return out


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="contact_sheet: %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("entries", nargs="+")
    args = parser.parse_args()
    logging.info("saved %s", build(args.folder, args.entries))


if __name__ == "__main__":
    main()
