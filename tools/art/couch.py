"""Three-seat couch, back against a wall (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/couch.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, deg, finish, material, reset  # noqa: E402

reset()

W, D = 1.76, 0.85
fabric = material("Couch Fabric", (0.33, 0.20, 0.14), 0.0, 0.95)
back = material("Couch Back", (0.27, 0.16, 0.11), 0.0, 0.95)  # the backrest: test_art_models checks it is at +Z
cushion = material("Couch Cushion", (0.40, 0.26, 0.18), 0.0, 0.95)
legs = material("Couch Legs", (0.12, 0.08, 0.05), 0.0, 0.8)
throw = material("Throw Blanket", (0.55, 0.50, 0.30), 0.0, 0.98)

# Frame, backrest along the back (+Y), two arms, stubby legs.
box("Base", (W, D - 0.02, 0.26), (0.0, 0.0, 0.19), fabric, 0.03)
box("Backrest", (W - 0.02, 0.22, 0.52), (0.0, D / 2 - 0.12, 0.58), back, 0.04)
for sx in (-1, 1):
    box(f"Arm_{sx}", (0.18, D, 0.40), (sx * (W / 2 - 0.09), 0.0, 0.46), fabric, 0.04)
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"Leg_{sx}_{sy}", (0.06, 0.06, 0.06), (sx * (W / 2 - 0.08), sy * (D / 2 - 0.08), 0.03), legs)

# Three seat cushions and three back cushions, slightly uneven.
cw = (W - 0.36) / 3
for i in range(3):
    x = -W / 2 + 0.18 + cw * (i + 0.5)
    box(f"Seat_{i}", (cw - 0.02, D - 0.30, 0.13), (x, -0.11, 0.385 + 0.006 * (i % 2)), cushion, 0.04)
    box(f"Back_Cushion_{i}", (cw - 0.03, 0.14, 0.32), (x, D / 2 - 0.30, 0.61), cushion, 0.05,
        rotation=(deg(-8 - 2 * (i % 2)), 0.0, 0.0))
box("Throw", (0.40, 0.50, 0.03), (-0.45, -0.10, 0.465), throw, 0.01, rotation=(0.0, 0.0, deg(8)))

finish("couch", (1.76, 0.85, 0.85), max_triangles=2000)
