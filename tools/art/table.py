"""Small square kitchen table with two chairs merged in, one at each end (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/table.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, deg, finish, material, reset  # noqa: E402

reset()

wood = material("Table Wood", (0.36, 0.24, 0.13), 0.0, 0.8)
chair = material("Chair Paint", (0.20, 0.30, 0.36), 0.0, 0.8)
cloth = material("Table Cloth", (0.62, 0.58, 0.50), 0.0, 0.95)

# The table: a 0.8 m square top on four legs, with a cloth runner and a plate.
box("Table_Top", (0.80, 0.80, 0.04), (0.0, 0.0, 0.74), wood, 0.008)
box("Table_Apron", (0.70, 0.70, 0.08), (0.0, 0.0, 0.68), wood)
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"Table_Leg_{sx}_{sy}", (0.05, 0.05, 0.70), (sx * 0.34, sy * 0.34, 0.35), wood)
box("Runner", (0.26, 0.80, 0.006), (0.0, 0.0, 0.763), cloth)
box("Plate", (0.20, 0.20, 0.01), (0.1, -0.15, 0.77), material("Plate", (0.80, 0.80, 0.76), 0.0, 0.5))

# Two chairs, one at each end (+X and -X), pulled up to the table, backs on the outside.
for sx in (-1, 1):
    cx = sx * 0.59
    box(f"Chair_Seat_{sx}", (0.40, 0.40, 0.04), (cx, 0.0, 0.45), chair, 0.006)
    for lx in (-1, 1):
        for ly in (-1, 1):
            box(f"Chair_Leg_{sx}_{lx}_{ly}", (0.035, 0.035, 0.43), (cx + lx * 0.17, ly * 0.17, 0.215), chair)
    bx = cx + sx * 0.18
    for ly in (-1, 1):
        box(f"Chair_Post_{sx}_{ly}", (0.035, 0.035, 0.46), (bx, ly * 0.17, 0.70), chair)
    box(f"Chair_Back_{sx}", (0.03, 0.38, 0.16), (bx, 0.0, 0.84), chair, 0.006)

finish("table", (1.6, 0.95, 0.8), max_triangles=2000)
