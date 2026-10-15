"""V30 shotgun choke, centred; attaching face is its +Y end before export."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.055, 0.062, 0.065), 0.88, 0.30)
cylinder("Choke", 0.015, 0.090, (0.0, 0.0, 0.0), metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
for y in (-0.022, -0.011, 0.0, 0.011, 0.022):
    cylinder("Knurl", 0.0162, 0.004, (0.0, y, 0.0), metal, vertices=20,
             rotation=(deg(90), 0.0, 0.0))
finish("part_choke", (0.04, 0.04, 0.10), max_triangles=4000)
