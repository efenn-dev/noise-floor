"""Low-poly leafy tree (A1 street dressing). Built on kit.py.

    blender.exe -b --factory-startup --python tools/art/tree.py

One model; the street plan scales it (StreetPlan.TREE_SCALES) for small, medium and large trees.
Only the trunk has a collider in the game.
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import cylinder, finish, material, reset  # noqa: E402

reset()
bark = material("Bark", (0.13, 0.09, 0.06), 0.0, 0.95)
leaf = material("Leaves", (0.09, 0.20, 0.06), 0.0, 0.9)
leaf_dark = material("Leaves Dark", (0.05, 0.13, 0.04), 0.0, 0.9)

bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=0.21, radius2=0.11, depth=2.9, end_fill_type="NGON",
                                location=(0.0, 0.0, 1.45))
trunk = bpy.context.object
trunk.name = "Trunk"
trunk.data.materials.append(bark)
cylinder("Root_Flare", 0.27, 0.18, (0.0, 0.0, 0.09), bark, 7)

# Clumps of leaves: squashed icospheres round the top of the trunk.
CLUMPS = [((0.0, 0.0, 3.55), 1.25, leaf), ((0.55, 0.30, 3.05), 0.95, leaf_dark), ((-0.55, 0.25, 3.15), 0.95, leaf),
          ((0.10, -0.60, 3.10), 0.90, leaf_dark), ((-0.20, 0.10, 4.20), 0.85, leaf)]
for i, (loc, r, m) in enumerate(CLUMPS):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    clump = bpy.context.object
    clump.name = f"Clump_{i}"
    clump.scale = (1.0, 1.0, 0.82)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    clump.data.materials.append(m)

finish("tree", (3.4, 5.0, 3.4), max_triangles=800)
