"""Toilet, cistern against a wall (W1c furniture). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/toilet.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, finish, material, reset  # noqa: E402

reset()

porcelain = material("Porcelain", (0.80, 0.80, 0.76), 0.0, 0.35)
cistern = material("Cistern", (0.76, 0.76, 0.72), 0.0, 0.35)  # the tank, at the back: test_art_models checks +Z
seat = material("Toilet Seat", (0.70, 0.66, 0.56), 0.0, 0.5)
water = material("Bowl Water", (0.18, 0.22, 0.22), 0.1, 0.2)
chrome = material("Flush Chrome", (0.55, 0.56, 0.58), 0.9, 0.25)

# Pedestal and bowl toward the front (-Y), seat on top. Cylinders are stretched front to back.
box("Pedestal", (0.24, 0.36, 0.30), (0.0, -0.02, 0.15), porcelain, 0.04)
for name, radius, depth, z, material_ in (("Bowl", 0.20, 0.14, 0.34, porcelain), ("Water", 0.15, 0.01, 0.405, water),
                                          ("Seat", 0.205, 0.025, 0.425, seat)):
    obj = cylinder(name, radius, depth, (0.0, -0.10, z), material_, 16)
    obj.scale = (1.0, 1.22, 1.0)
# The cistern against the wall (+Y) with its lid and a flush button.
box("Cistern", (0.42, 0.18, 0.36), (0.0, 0.24, 0.58), cistern, 0.025)
box("Cistern_Lid", (0.44, 0.20, 0.03), (0.0, 0.24, 0.775), cistern, 0.01)
box("Cistern_Neck", (0.20, 0.14, 0.12), (0.0, 0.17, 0.40), porcelain, 0.02)
cylinder("Flush", 0.025, 0.02, (0.0, 0.24, 0.785), chrome, 10)

finish("toilet", (0.5, 0.8, 0.7), max_triangles=2000)
