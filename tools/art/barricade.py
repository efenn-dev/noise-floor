"""Hasty scavenged barricade for Noise Floor. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/barricade.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, mat, material, reset  # noqa: E402

reset()
wood = material("Weathered Wood", (0.23, 0.18, 0.13), 0.05, 0.92)
sheet = material("Sheet Metal", (0.38, 0.41, 0.40), 0.70, 0.55)
bare, bare_edge, rust = mat("bare"), mat("bare_edge"), mat("rust")

# Three mismatched upright posts make the silhouette sturdy but improvised.
post_data = (
    ("Left_Post", -0.82, 0.505, 1.01, deg(-1.5)),
    ("Middle_Post", 0.00, 0.535, 1.07, deg(1.0)),
    ("Right_Post", 0.82, 0.515, 1.03, deg(-1.0)),
)
for name, x, z, height, lean in post_data:
    box(name, (0.15, 0.18, height), (x, 0.0, z), wood, 0.018,
        rotation=(0.0, lean, 0.0))
    box(f"{name}_Foot_Band", (0.205, 0.205, 0.105), (x, 0.0, 0.105), rust, 0.012)

# Thick boards nailed across the gap at deliberately uneven angles.
planks = (
    ("Lower_Plank", 1.89, -0.035, 0.305, deg(-2.5)),
    ("Lower_Middle_Plank", 1.82, -0.028, 0.505, deg(3.0)),
    ("Upper_Middle_Plank", 1.91, -0.032, 0.715, deg(-2.0)),
    ("Upper_Plank", 1.84, -0.025, 0.915, deg(2.5)),
)
for name, width, y, z, angle in planks:
    box(name, (width, 0.075, 0.165), (0.0, y, z), wood, 0.016,
        rotation=(0.0, angle, 0.0))

# Galvanised patch: a thin plate with narrow ribs on both faces so it reads from either side.
box("Sheet_Back", (0.77, 0.026, 0.48), (0.43, 0.018, 0.615), sheet, 0.008,
    rotation=(0.0, deg(-1.5), 0.0))
for i, x in enumerate((0.10, 0.21, 0.32, 0.43, 0.54, 0.65, 0.76)):
    for side, y in (("Front", -0.002), ("Back", 0.038)):
        box(f"Sheet_Rib_{side}_{i}", (0.026, 0.026, 0.46), (x, y, 0.615),
            sheet, 0.007, rotation=(0.0, deg(-1.5), 0.0))

# Crude repair straps and bolt heads break up the broad wooden face.
box("Left_Repair_Strap", (0.105, 0.027, 0.44), (-0.54, -0.083, 0.67), bare_edge, 0.008,
    rotation=(0.0, deg(-7.0), 0.0))
box("Back_Repair_Strap", (0.34, 0.027, 0.09), (-0.32, 0.083, 0.42), rust, 0.008,
    rotation=(0.0, deg(5.0), 0.0))
for side, y, turn in (("Front", -0.086, deg(90)), ("Back", 0.061, deg(90))):
    for px in (-0.82, 0.0, 0.82):
        for pz in (0.31, 0.51, 0.71, 0.91):
            cylinder(f"Nail_{side}_{px}_{pz}", 0.026, 0.026, (px, y, pz),
                     bare, 8, rotation=(turn, 0.0, 0.0))

# A small warning plate is legible from the approach side without competing with the silhouette.
hazard_stripes("Warning_Plate", (-0.47, -0.088, 0.775), 0.31, 0.12, 4, "-Y")

# Two taut wire runs. Short crossed cylinders form chunky low-poly barbs.
for strand, (y, z) in enumerate(((-0.045, 1.115), (0.045, 1.225))):
    cylinder(f"Barbed_Wire_{strand}", 0.011, 1.87, (0.0, y, z), bare, 8,
             rotation=(0.0, deg(90), 0.0))
    for barb, x in enumerate((-0.66, -0.22, 0.22, 0.66)):
        cylinder(f"Barb_{strand}_{barb}_A", 0.008, 0.095, (x, y, z), rust, 6,
                 rotation=(0.0, deg(45), 0.0))
        cylinder(f"Barb_{strand}_{barb}_B", 0.008, 0.095, (x, y, z), rust, 6,
                 rotation=(0.0, deg(-45), 0.0))

finish("barricade", (2.0, 1.3, 0.25))
