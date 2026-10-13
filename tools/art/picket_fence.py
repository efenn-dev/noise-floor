"""One 2 m section of low white picket fence (A1 street dressing). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/picket_fence.py

Runs along X; the street plan lays sections end to end along the side boundary between two lots.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, deg, finish, material, reset  # noqa: E402

reset()
white = material("Fence Paint", (0.78, 0.77, 0.72), 0.0, 0.85)
worn = material("Fence Weathered", (0.52, 0.50, 0.45), 0.0, 0.9)

LENGTH, HEIGHT = 2.0, 0.95
for sx in (-1, 1):
    box(f"Post_{sx}", (0.09, 0.09, HEIGHT), (sx * (LENGTH / 2 - 0.045), 0.0, HEIGHT / 2), worn, 0.008)
for z in (0.22, 0.62):
    box(f"Rail_{z}", (LENGTH - 0.02, 0.035, 0.075), (0.0, 0.025, z), white, 0.005)
COUNT = 13
pitch = (LENGTH - 0.12) / COUNT
for i in range(COUNT):
    x = -LENGTH / 2 + 0.06 + pitch * (i + 0.5)
    h = 0.78 - 0.03 * ((i * 7) % 3)  # a little uneven
    paint = white if i % 5 else worn
    box(f"Picket_{i}", (0.075, 0.02, h), (x, -0.02, 0.06 + h / 2), paint, 0.0)
    box(f"Picket_Tip_{i}", (0.053, 0.02, 0.053), (x, -0.02, 0.06 + h), paint, 0.0, rotation=(0.0, deg(45), 0.0))

finish("picket_fence", (2.0, 0.95, 0.12), max_triangles=1200)
