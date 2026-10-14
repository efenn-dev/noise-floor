"""Compact hunting optic. Its tube axis is along -Y and 35 mm above the rail feet."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.035, 0.043, 0.048), 0.76, 0.38)
rubber = material("Gun Rubber", (0.009, 0.011, 0.012), 0.0, 0.92)
glass = material("Gun Glass", (0.025, 0.09, 0.11), 0.12, 0.12)

cylinder("Scope_Tube", 0.017, 0.205, (0.0, -0.005, 0.045), metal, vertices=32,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Objective_Bell", 0.027, 0.050, (0.0, -0.104, 0.045), metal, vertices=32,
         rotation=(deg(90), 0.0, 0.0), bevel=0.002)
cylinder("Eye_Bell", 0.022, 0.040, (0.0, 0.105, 0.045), rubber, vertices=32,
         rotation=(deg(90), 0.0, 0.0), bevel=0.002)
cylinder("Front_Lens", 0.0225, 0.002, (0.0, -0.130, 0.045), glass, vertices=32,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Rear_Lens", 0.0175, 0.002, (0.0, 0.126, 0.045), glass, vertices=32,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Turret", 0.010, 0.020, (0.0, -0.010, 0.070), metal, vertices=20, bevel=0.001)
for y in (-0.055, 0.050):
    box("Scope_Ring" if y < 0 else "Scope_Ring_Rear", (0.040, 0.012, 0.050),
        (0.0, y, 0.037), metal, 0.002)
    box("Rail_Foot" if y < 0 else "Rail_Foot_Rear", (0.034, 0.022, 0.010),
        (0.0, y, 0.005), metal, 0.0015)

finish("part_scope", (0.06, 0.09, 0.26), max_triangles=8000)
