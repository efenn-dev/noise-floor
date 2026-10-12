"""Storage crate for scavenged supplies. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/storage.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()
wood = material("Crate Wood", (0.43, 0.245, 0.095), 0.03, 0.88)
stencil = material("Stencil White", (0.72, 0.70, 0.62), 0.02, 0.84)
bare, bare_edge, rust = mat("bare"), mat("bare_edge"), mat("rust")

# Five separate courses on every wall leave broad, readable shadow grooves.
for row in range(5):
    z = 0.145 + row * 0.15
    box(f"Front_Plank_{row}", (1.20, 0.075, 0.132), (0.0, -0.432, z), wood)
    box(f"Back_Plank_{row}", (1.20, 0.075, 0.132), (0.0, 0.432, z), wood)
    box(f"Left_Plank_{row}", (0.075, 0.79, 0.132), (-0.602, 0.0, z), wood)
    box(f"Right_Plank_{row}", (0.075, 0.79, 0.132), (0.602, 0.0, z), wood)

# Bottom skids make the box look heavy and keep the silhouette grounded.
for x in (-0.43, 0.43):
    box(f"Bottom_Skid_{x}", (0.22, 0.90, 0.09), (x, 0.0, 0.045), wood, 0.018)

# Chunky lid, assembled from long boards with narrow gaps between them.
for i, y in enumerate((-0.36, -0.18, 0.0, 0.18, 0.36)):
    box(f"Lid_Plank_{i}", (1.28, 0.165, 0.125), (0.0, y, 0.8975), wood, 0.014)
box("Lid_Front_Edge", (1.31, 0.065, 0.13), (0.0, -0.446, 0.895), bare, 0.012)

# Four steel corners, built as paired faces so they read as angle brackets.
for side, x in (("L", -0.635), ("R", 0.635)):
    for front, y in (("F", -0.447), ("B", 0.447)):
        box(f"Corner_{side}{front}_Face", (0.09, 0.035, 0.78), (x, y, 0.45), bare)
        box(f"Corner_{side}{front}_Return", (0.035, 0.10, 0.78), (x + (0.027 if x < 0 else -0.027), y, 0.45), bare)
        for zi, z in enumerate((0.16, 0.69)):
            cylinder(f"Corner_Bolt_{side}{front}_{zi}", 0.021, 0.022,
                     (x, y + (-0.025 if y < 0 else 0.025), z), bare_edge, 8,
                     rotation=(deg(90), 0.0, 0.0))

# Two salvaged straps wrap the front, lid, and back at matching X positions.
for si, x in enumerate((-0.34, 0.34)):
    box(f"Strap_{si}_Front", (0.075, 0.025, 0.73), (x, -0.476, 0.49), bare_edge)
    box(f"Strap_{si}_Top", (0.075, 0.89, 0.025), (x, 0.0, 0.972), bare_edge)
    box(f"Strap_{si}_Back", (0.075, 0.025, 0.73), (x, 0.476, 0.49), bare_edge)
    cylinder(f"Strap_Buckle_{si}", 0.045, 0.025, (x, -0.478, 0.68), bare, 10,
             rotation=(deg(90), 0.0, 0.0))

# Rear hinges: broad leaves and low-poly hinge barrels along X.
for hi, x in enumerate((-0.40, 0.40)):
    box(f"Hinge_{hi}_Lid_Leaf", (0.24, 0.075, 0.035), (x, 0.445, 0.948), bare)
    box(f"Hinge_{hi}_Back_Leaf", (0.24, 0.025, 0.15), (x, 0.473, 0.79), bare)
    cylinder(f"Hinge_{hi}_Barrel", 0.038, 0.27, (x, 0.452, 0.875), bare_edge, 10,
             rotation=(0.0, deg(90), 0.0))

# Rectangular steel grab handles on both ends, proud but inside the footprint.
for side, x, sx in (("Left", -0.667, -1), ("Right", 0.667, 1)):
    for y in (-0.22, 0.22):
        cylinder(f"{side}_Handle_Mount_{y}", 0.045, 0.025, (x, y, 0.48), bare, 10,
                 rotation=(0.0, deg(90), 0.0))
        cylinder(f"{side}_Handle_Arm_{y}", 0.025, 0.18, (x + sx * 0.004, y, 0.39), bare_edge, 10)
    cylinder(f"{side}_Handle_Grip", 0.03, 0.44, (x + sx * 0.004, 0.0, 0.30), bare_edge, 10,
             rotation=(deg(90), 0.0, 0.0))

# Dirty front inventory plate and a simple block-stencilled number 07.
box("Number_Plate", (0.35, 0.025, 0.22), (0.0, -0.476, 0.44), stencil, 0.012)
box("Stencil_0_Left", (0.026, 0.014, 0.13), (-0.095, -0.485, 0.44), mat("black"))
box("Stencil_0_Right", (0.026, 0.014, 0.13), (-0.025, -0.485, 0.44), mat("black"))
box("Stencil_0_Top", (0.09, 0.014, 0.026), (-0.06, -0.485, 0.505), mat("black"))
box("Stencil_0_Bottom", (0.09, 0.014, 0.026), (-0.06, -0.485, 0.375), mat("black"))
box("Stencil_7_Top", (0.10, 0.014, 0.026), (0.085, -0.485, 0.505), mat("black"))
box("Stencil_7_Stem", (0.026, 0.014, 0.13), (0.115, -0.485, 0.44), mat("black"),
    rotation=(0.0, deg(-10), 0.0))

# A mismatched repair patch and exposed fasteners sell the scavenged history.
box("Front_Repair_Plate", (0.22, 0.022, 0.16), (0.43, -0.466, 0.22), rust, 0.007,
    rotation=(0.0, deg(4), deg(-3)))
for x in (0.36, 0.50):
    for z in (0.17, 0.27):
        cylinder(f"Repair_Bolt_{x}_{z}", 0.015, 0.018, (x, -0.478, z), bare_edge, 8,
                 rotation=(deg(90), 0.0, 0.0))

finish("storage", (1.4, 1.0, 1.0))
