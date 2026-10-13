"""Plastic trash can with a lid (A1 street dressing; searchable in the game). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/trash_can.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, finish, material, reset  # noqa: E402

reset()
plastic = material("Bin Plastic", (0.06, 0.12, 0.08), 0.0, 0.7)
rim = material("Bin Rim", (0.035, 0.07, 0.05), 0.0, 0.65)
grime = material("Bin Grime", (0.10, 0.09, 0.06), 0.0, 0.95)

cylinder("Foot", 0.26, 0.06, (0.0, 0.0, 0.03), rim, 12)
cylinder("Body", 0.29, 0.84, (0.0, 0.0, 0.48), plastic, 12)
for z in (0.30, 0.62):
    cylinder(f"Rib_{z}", 0.30, 0.035, (0.0, 0.0, z), rim, 12)
cylinder("Grime_Band", 0.295, 0.12, (0.0, 0.0, 0.12), grime, 12)
cylinder("Lid", 0.315, 0.06, (0.0, 0.0, 0.93), rim, 12, bevel=0.01)
cylinder("Lid_Top", 0.25, 0.03, (0.0, 0.0, 0.975), plastic, 12)
box("Lid_Handle", (0.18, 0.04, 0.03), (0.0, 0.0, 1.0), rim, 0.006)
for sx in (-1, 1):
    box(f"Side_Handle_{sx}", (0.03, 0.12, 0.05), (sx * 0.30, 0.0, 0.80), rim, 0.006)

finish("trash_can", (0.66, 1.05, 0.66), max_triangles=1000)
