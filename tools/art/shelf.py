"""Bookshelf, back against a wall, with a few books as coloured blocks (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/shelf.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, deg, finish, material, reset  # noqa: E402

reset()

W, D, H = 1.0, 0.35, 1.8
wood = material("Shelf Wood", (0.38, 0.27, 0.16), 0.0, 0.85)
back = material("Shelf Back", (0.22, 0.15, 0.09), 0.0, 0.9)  # the back panel: test_art_models checks it is at +Z
books = [material("Book Red", (0.50, 0.08, 0.06), 0.0, 0.8), material("Book Blue", (0.08, 0.16, 0.40), 0.0, 0.8),
         material("Book Green", (0.12, 0.30, 0.14), 0.0, 0.8), material("Book Cream", (0.70, 0.64, 0.48), 0.0, 0.8)]

box("Side_L", (0.03, D, H), (-W / 2 + 0.015, 0.0, H / 2), wood)
box("Side_R", (0.03, D, H), (W / 2 - 0.015, 0.0, H / 2), wood)
box("Top", (W, D, 0.03), (0.0, 0.0, H - 0.015), wood)
box("Plinth", (W - 0.06, 0.03, 0.08), (0.0, -D / 2 + 0.03, 0.04), wood)
box("Back", (W - 0.06, 0.02, H - 0.03), (0.0, D / 2 - 0.01, (H - 0.03) / 2), back)
levels = (0.08, 0.50, 0.92, 1.34)
for i, z in enumerate(levels):
    box(f"Board_{i}", (W - 0.06, D - 0.02, 0.025), (0.0, -0.01, z + 0.0125), wood)

# Books: rows of blocks of varied height and width, a gap here and there, one leaning per row.
rows = [
    [(0.05, 0.30, 0), (0.04, 0.27, 1), (0.06, 0.32, 3), (0.04, 0.25, 2), (0.05, 0.29, 0), (0.07, 0.24, 1)],
    [(0.04, 0.26, 2), (0.05, 0.30, 3), (0.05, 0.28, 0), (0.03, 0.22, 1), (0.06, 0.31, 2)],
    [(0.06, 0.28, 1), (0.04, 0.33, 0), (0.05, 0.26, 3), (0.05, 0.30, 2)],
    [(0.05, 0.24, 3), (0.04, 0.29, 1), (0.06, 0.27, 0)],
]
for r, row in enumerate(rows):
    z0 = levels[r] + 0.025
    x = -W / 2 + 0.06 + 0.05 * (r % 2)
    for j, (w, h, c) in enumerate(row):
        box(f"Book_{r}_{j}", (w, 0.22, h), (x + w / 2, -0.02, z0 + h / 2), books[c])
        x += w + 0.004
    box(f"Leaning_Book_{r}", (0.05, 0.22, 0.26), (x + 0.08, -0.02, z0 + 0.13), books[(r + 2) % 4],
        rotation=(0.0, deg(18), 0.0))
box("Book_Stack", (0.26, 0.20, 0.10), (0.30, -0.03, levels[3] + 0.075), books[3])

finish("shelf", (1.0, 1.8, 0.35), max_triangles=2000)
