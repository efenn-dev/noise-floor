"""Purpose-built machined suppressor. Rear (+Y) screws to the muzzle; front points -Y."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, deg, finish, material, reset  # noqa: E402

reset()
metal = material("Gun Metal", (0.035, 0.042, 0.047), 0.86, 0.32)
rubber = material("Gun Rubber", (0.008, 0.010, 0.011), 0.0, 0.94)

cylinder("Suppressor_Tube", 0.023, 0.172, (0.0, -0.008, 0.0), metal, vertices=32,
         rotation=(deg(90), 0.0, 0.0), bevel=0.0015)
for i in range(5):
    cylinder(f"Cooling_Ring_{i}", 0.0245, 0.004, (0.0, -0.066 + i * 0.026, 0.0), metal,
             vertices=32, rotation=(deg(90), 0.0, 0.0), bevel=0.0005)
cylinder("Mount", 0.016, 0.028, (0.0, 0.092, 0.0), metal, vertices=28,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Bore", 0.0045, 0.008, (0.0, -0.098, 0.0), rubber, vertices=18,
         rotation=(deg(90), 0.0, 0.0))

finish("part_machined_suppressor", (0.052, 0.052, 0.21), max_triangles=5000)
