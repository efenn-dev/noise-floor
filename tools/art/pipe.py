"""Rusty 0.60 m steel pipe, grip-centred for the first-person melee view."""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, material, reset  # noqa: E402
from melee_common import grip_anchor, held_finish  # noqa: E402

reset()
metal = material("Weapon Metal", (0.075, 0.026, 0.010), 0.72, 0.74)
grip = material("Weapon Grip", (0.022, 0.020, 0.017), 0.02, 0.95)

# Hollow pipe body. The slightly different rings and battered lips read as threaded and cut ends.
cylinder("Pipe", 0.016, 0.552, (0, 0, 0.176), metal, vertices=16, bevel=0.0012)
cylinder("Thread_Core", 0.0148, 0.054, (0, 0, 0.473), metal, vertices=16,
         bevel=0.0007)
for i in range(6):
    cylinder(f"Thread_{i}", 0.0172, 0.0032, (0, 0, 0.455 + i * 0.0060), metal,
             vertices=16, bevel=0.00045)
cylinder("Thread_Collar", 0.018, 0.012, (0, 0, 0.443), metal, vertices=16, bevel=0.0008)

# Dark openings are intentionally the grip material, avoiding a fifth authored material.
cylinder("Top_Bore", 0.0118, 0.0022, (0, 0, 0.5002), grip, vertices=16)
for i, dz in enumerate((0.0000, 0.0015, -0.0010, 0.0008)):
    a = i * 1.5708
    x, y = 0.0136 * __import__("math").cos(a), 0.0136 * __import__("math").sin(a)
    cylinder(f"Rough_Cut_{i}", 0.0038, 0.0022 + abs(dz), (x, y, -0.100 + dz * 0.35), metal,
             vertices=8, bevel=0.0005)
cylinder("Bottom_Bore", 0.0117, 0.0020, (0, 0, -0.1002), grip, vertices=16)

# Overlapping cloth tape bands make a slightly uneven 17 cm hand wrap.
for i in range(10):
    z = -0.073 + i * 0.017
    cylinder(f"Grip_Tape_{i}", 0.01715 + (0.0005 if i % 3 == 0 else 0), 0.019,
             (0, 0, z), grip, vertices=16, bevel=0.0007)

grip_anchor()
held_finish("pipe", (0.10, 0.80, 0.10), 0.60,
            ["Weapon Metal", "Weapon Grip"])
