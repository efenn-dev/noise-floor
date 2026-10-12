"""Spike strip floor trap. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/spikes.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, mat, material, reset  # noqa: E402

reset()
body_dark, bare, bare_edge, rust = mat("body_dark"), mat("bare"), mat("bare_edge"), mat("rust")
wood = material("Weathered Wood", (0.20, 0.155, 0.11), 0.05, 0.92)

# Low timber raft and battered steel perimeter. Everything stays ankle-high so the
# spike field is the silhouette from across a street.
for i, y in enumerate((-0.60, -0.30, 0.0, 0.30, 0.60)):
    skew = (deg(0.0), deg(0.0), deg((i - 2) * 0.7))
    box(f"Weathered_Plank_{i}", (1.48, 0.235, 0.055), (0.0, y, 0.037), wood, 0.012, skew)

box("Front_Frame", (1.72, 0.12, 0.095), (0.0, -0.80, 0.052), body_dark, 0.018)
box("Back_Frame", (1.72, 0.12, 0.095), (0.0, 0.80, 0.052), body_dark, 0.018)
box("Left_Frame", (0.12, 1.48, 0.095), (-0.80, 0.0, 0.052), body_dark, 0.018)
box("Right_Frame", (0.12, 1.48, 0.095), (0.80, 0.0, 0.052), body_dark, 0.018)

# Scrap cross straps keep the planks tied together and give the field a patched,
# improvised construction without obscuring the readable grid.
for x in (-0.47, 0.47):
    box(f"Cross_Strap_{x}", (0.09, 1.42, 0.026), (x, 0.0, 0.083), bare, 0.007)
box("Repair_Plate", (0.31, 0.25, 0.025), (0.57, 0.55, 0.087), bare_edge, 0.008, (0.0, 0.0, deg(-7)))
for x, y in ((0.47, 0.48), (0.67, 0.49), (0.48, 0.62), (0.67, 0.61)):
    cylinder(f"Repair_Rivet_{x}_{y}", 0.018, 0.018, (x, y, 0.108), bare_edge, 8, bevel=0.003)

# The front rail carries a worn caution panel; this trap has no item-flow markers.
hazard_stripes("Front_Caution", (0.0, -0.866, 0.055), 0.72, 0.065, 6, "-Y")

# kit.py owns Blender's module import. Reuse that handle so this file keeps the
# same compact import header as the reference scripts.
bpy = box.__globals__["bpy"]


def cone(name, radius, depth, location, material_, vertices=6, rotation=(0.0, 0.0, 0.0)):
    """A deliberately faceted sharpened point, aligned along local Z."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius, radius2=0.004, depth=depth,
        end_fill_type="NGON", location=location, rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


# Five by five salvaged rebar-and-nail spikes. The tables are deterministic and
# repeat visually without looking machine-perfect. Four points lean hard enough
# to read as bent/damaged while still staying inside the shallow collision box.
heights = (
    (0.145, 0.132, 0.158, 0.137, 0.151),
    (0.135, 0.155, 0.141, 0.160, 0.130),
    (0.152, 0.139, 0.162, 0.134, 0.148),
    (0.131, 0.157, 0.143, 0.153, 0.138),
    (0.149, 0.136, 0.154, 0.140, 0.159),
)
leans = (
    ((-3, 2), (2, -2), (0, 1), (-2, -1), (3, 0)),
    ((1, -3), (-4, 1), (2, 2), (0, -2), (-2, 3)),
    ((3, 1), (-1, -2), (0, 0), (2, -3), (-3, -1)),
    ((-2, 2), (3, -1), (-1, 3), (4, 1), (1, -2)),
    ((2, -1), (-3, 0), (1, 2), (-2, -3), (3, 2)),
)
bent = {(0, 4), (1, 1), (3, 3), (4, 0)}
grid = (-0.61, -0.305, 0.0, 0.305, 0.61)

for row, y in enumerate(grid):
    for col, x in enumerate(grid):
        total = heights[row][col]
        rx, ry = leans[row][col]
        rotation = (deg(rx), deg(ry), 0.0)
        spike_mat = rust if (row + col) % 3 else bare
        sides = 5 if (row + col) % 2 else 6
        base_z = 0.088
        if (row, col) in bent:
            lower = total * 0.48
            upper = total - lower
            cylinder(f"Bent_Shaft_{row}_{col}", 0.024, lower, (x, y, base_z + lower / 2), spike_mat, sides, rotation=rotation)
            kick_x = -10 if (row + col) % 2 else 11
            kick_y = 8 if row % 2 else -9
            bend_rotation = (deg(rx + kick_x), deg(ry + kick_y), 0.0)
            cone(f"Bent_Point_{row}_{col}", 0.029, upper, (x, y, base_z + lower + upper / 2 - 0.002), rust, sides, bend_rotation)
        else:
            shaft = total * 0.45
            point = total - shaft
            cylinder(f"Spike_Shaft_{row}_{col}", 0.023, shaft, (x, y, base_z + shaft / 2), spike_mat, sides, rotation=rotation)
            cone(f"Spike_Point_{row}_{col}", 0.030, point, (x, y, base_z + shaft + point / 2 - 0.002), rust, sides, rotation)

finish("spikes", (1.8, 0.25, 1.8), max_triangles=2500)
