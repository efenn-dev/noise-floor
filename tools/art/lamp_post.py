"""Street lamp post with a lantern on top (A1 street dressing). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/lamp_post.py

The lantern glass is the separate "Lamp" object: StreetView makes it glow warm at night and hangs a
small omni light in it. Symmetric, so it needs no facing.
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, finish, material, reset  # noqa: E402

reset()
iron = material("Cast Iron Green", (0.035, 0.06, 0.05), 0.55, 0.6)
iron_edge = material("Worn Iron", (0.10, 0.12, 0.11), 0.7, 0.5)
glass = material("Lamp", (0.55, 0.50, 0.38), 0.0, 0.3)

# A heavy footing, a fluted base and a tapering pole.
cylinder("Footing", 0.17, 0.08, (0.0, 0.0, 0.04), iron_edge, 8)
cylinder("Base", 0.13, 0.42, (0.0, 0.0, 0.29), iron, 8, bevel=0.01)
cylinder("Base_Ring", 0.145, 0.05, (0.0, 0.0, 0.52), iron_edge, 8)
bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.065, radius2=0.045, depth=2.75, end_fill_type="NGON",
                                location=(0.0, 0.0, 0.545 + 1.375))
pole = bpy.context.object
pole.name = "Pole"
pole.data.materials.append(iron)
cylinder("Collar", 0.08, 0.08, (0.0, 0.0, 3.30), iron_edge, 8)

# The lantern: a tray, four corner posts round the glass, a pyramid cap and a finial.
box("Tray", (0.30, 0.30, 0.04), (0.0, 0.0, 3.36), iron, 0.008)
for i, (x, y) in enumerate(((-0.13, -0.13), (0.13, -0.13), (-0.13, 0.13), (0.13, 0.13))):
    box(f"Lantern_Post_{i}", (0.025, 0.025, 0.40), (x, y, 3.58), iron, 0.0)
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.24, radius2=0.03, depth=0.20, end_fill_type="NGON",
                                location=(0.0, 0.0, 3.88), rotation=(0.0, 0.0, 0.785398))
cap = bpy.context.object
cap.name = "Cap"
cap.data.materials.append(iron)
cylinder("Finial", 0.025, 0.10, (0.0, 0.0, 4.03), iron_edge, 6)
cylinder("Lamp", 0.115, 0.38, (0.0, 0.0, 3.57), glass, 8)

finish("lamp_post", (0.4, 4.1, 0.4), max_triangles=1500)
