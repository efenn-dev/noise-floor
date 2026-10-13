"""Bathtub, long side against a wall (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/bathtub.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, finish, material, reset  # noqa: E402

reset()

W, D, H = 1.6, 0.75, 0.55
enamel = material("Tub Enamel", (0.78, 0.78, 0.74), 0.0, 0.4)
inside = material("Tub Inside", (0.60, 0.62, 0.60), 0.0, 0.5)
chrome = material("Tap Chrome", (0.55, 0.56, 0.58), 0.9, 0.25)  # the taps, at the back: test_art_models checks +Z
grime = material("Tub Grime", (0.30, 0.26, 0.18), 0.0, 0.9)

# The shell: a floor and four walls with a rounded rim, so it reads as hollow from above.
box("Shell_Floor", (W, D, 0.12), (0.0, 0.0, 0.06), enamel, 0.03)
box("Wall_Front", (W, 0.08, H), (0.0, -D / 2 + 0.04, H / 2), enamel, 0.03)
box("Wall_Back", (W, 0.08, H), (0.0, D / 2 - 0.04, H / 2), enamel, 0.03)
for sx in (-1, 1):
    box(f"Wall_End_{sx}", (0.10, D, H), (sx * (W / 2 - 0.05), 0.0, H / 2), enamel, 0.03)
box("Inner_Floor", (W - 0.22, D - 0.18, 0.02), (0.0, 0.0, 0.13), inside)
box("Grime_Line", (W - 0.22, D - 0.18, 0.006), (0.0, 0.0, 0.25), grime)
box("Drain", (0.06, 0.06, 0.006), (-W / 2 + 0.2, 0.0, 0.142), chrome)

# Taps and a spout on the back rim.
box("Tap_Plate", (0.30, 0.06, 0.02), (0.0, D / 2 - 0.05, H + 0.01), chrome)
box("Spout", (0.04, 0.14, 0.035), (0.0, D / 2 - 0.12, H + 0.02), chrome, 0.008)
for x in (-0.11, 0.11):
    cylinder(f"Tap_{x}", 0.025, 0.04, (x, D / 2 - 0.05, H + 0.02), chrome, 10)

finish("bathtub", (1.6, 0.6, 0.75), max_triangles=2000)
