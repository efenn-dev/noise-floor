"""Improvised oil-filter suppressor. Rear (+Y) screws to the muzzle; front points -Y."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.07, 0.075, 0.07), 0.72, 0.58)
rubber = material("Gun Rubber", (0.012, 0.014, 0.013), 0.0, 0.92)

# A dented automotive filter body with a narrow threaded collar and dark end cap.
cylinder("Filter_Can", 0.038, 0.180, (0.0, -0.010, 0.0), metal, vertices=28,
         rotation=(deg(90), 0.0, 0.0), bevel=0.002)
cylinder("Thread_Collar", 0.014, 0.028, (0.0, 0.094, 0.0), metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Front_Cap", 0.034, 0.010, (0.0, -0.105, 0.0), rubber, vertices=28,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Exit_Hole", 0.005, 0.011, (0.0, -0.111, 0.0), rubber, vertices=18,
         rotation=(deg(90), 0.0, 0.0))

finish("part_oil_filter_suppressor", (0.08, 0.08, 0.23), max_triangles=3500)
