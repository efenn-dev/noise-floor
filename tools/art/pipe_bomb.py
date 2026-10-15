"""V30 throwable pipe bomb."""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.16, 0.17, 0.17), 0.72, 0.58)
rubber = material("Gun Rubber", (0.018, 0.020, 0.020), 0.0, 0.94)
wood = material("Gun Wood", (0.22, 0.10, 0.035), 0.0, 0.85)
cylinder("Pipe", 0.036, 0.230, (0.0, 0.0, 0.0), metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.003)
for y in (-0.132, 0.132):
    cylinder("End_Cap", 0.047, 0.042, (0.0, y, 0.0), metal, vertices=12,
             rotation=(deg(90), 0.0, 0.0), bevel=0.004)
for y in (-0.045, 0.0, 0.045):
    cylinder("Tape", 0.039, 0.025, (0.0, y, 0.0), rubber, vertices=20,
             rotation=(deg(90), 0.0, 0.0))
cylinder("Fuse", 0.004, 0.105, (0.0, -0.180, 0.026), wood, vertices=10,
         rotation=(deg(68), 0.0, 0.0))
finish("pipe_bomb", (0.11, 0.11, 0.39), max_triangles=5000)
