"""Extended detachable magazine, with its feed end at the top."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.045, 0.052, 0.058), 0.78, 0.43)
polymer = material("Gun Polymer", (0.018, 0.021, 0.024), 0.04, 0.72)
rubber = material("Gun Rubber", (0.009, 0.011, 0.012), 0.0, 0.94)

# Three overlapping sections suggest a gently swept magazine without a toy-like single box.
box("Magazine_Upper", (0.034, 0.052, 0.070), (0.0, 0.004, 0.043), metal, 0.003,
    rotation=(deg(-3), 0.0, 0.0))
box("Magazine_Lower", (0.036, 0.054, 0.085), (0.0, 0.010, -0.030), polymer, 0.004,
    rotation=(deg(-7), 0.0, 0.0))
box("Feed_Lips", (0.030, 0.042, 0.012), (0.0, 0.001, 0.084), metal, 0.0015)
box("Base_Plate", (0.041, 0.059, 0.010), (0.0, 0.015, -0.078), rubber, 0.002)

finish("part_extended_mag", (0.046, 0.18, 0.075), max_triangles=3000)
