"""Scavenged household cabinet used as a searchable prop.

    blender.exe -b --factory-startup --python tools/art/cabinet.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()

# The cabinet keeps its domestic colours, but borrows the shared dark materials for
# the empty interior, old fasteners, stains, and the split in its side.
paint = material("Cabinet Paint", (0.30, 0.40, 0.30), 0.0, 0.88)
wood = material("Weathered Wood", (0.24, 0.19, 0.14), 0.0, 0.94)
brass = material("Brass", (0.34, 0.23, 0.075), 0.8, 0.4)
dark, edge, stain = mat("black"), mat("bare_edge"), mat("rust")

# Plinth, back, and slab sides: chunky furniture rather than a factory-built machine.
box("Plinth_Foot", (0.66, 0.54, 0.10), (0.0, 0.0, 0.05), wood, 0.018)
box("Plinth_Face", (0.62, 0.08, 0.12), (0.0, -0.25, 0.12), paint, 0.014)
box("Back_Panel", (0.60, 0.055, 1.38), (0.0, 0.225, 0.83), wood, 0.012)
for x in (-0.305, 0.305):
    box(f"Side_Panel_{x}", (0.05, 0.48, 1.39), (x, 0.0, 0.84), paint, 0.014)
box("Cabinet_Floor", (0.61, 0.48, 0.07), (0.0, 0.0, 0.18), wood, 0.012)
box("Top_Slab", (0.66, 0.54, 0.085), (0.0, 0.0, 1.535), paint, 0.018)
box("Top_Wood_Wear", (0.34, 0.035, 0.025), (-0.09, -0.271, 1.555), wood, 0.006)

# The front frame surrounds two stacked cupboards. Black inset panels read as
# actual empty depth wherever a door or the centre gap exposes the interior.
box("Lower_Empty_Interior", (0.535, 0.035, 0.64), (0.0, -0.237, 0.535), dark, 0.006)
box("Upper_Empty_Interior", (0.535, 0.035, 0.50), (0.0, -0.237, 1.205), dark, 0.006)
for x in (-0.285, 0.0, 0.285):
    box(f"Front_Stile_{x}", (0.045, 0.07, 1.27), (x, -0.235, 0.86), paint)
for z in (0.205, 0.865, 1.475):
    box(f"Front_Rail_{z}", (0.61, 0.07, 0.07), (0.0, -0.235, z), paint)

# Shelves are deliberately visible behind the partly open top-left door.
for z in (1.00, 1.235):
    box(f"Upper_Shelf_{z}", (0.54, 0.39, 0.035), (0.0, -0.015, z), wood, 0.006)
    box(f"Shelf_Dark_Edge_{z}", (0.54, 0.025, 0.035), (0.0, -0.245, z), dark, 0.003)

# Bottom pair: raised painted doors with a little exposed wood where paint flaked.
for x, side in ((-0.148, "Left"), (0.148, "Right")):
    box(f"Lower_{side}_Door", (0.265, 0.045, 0.565), (x, -0.292, 0.545), paint, 0.014)
    box(f"Lower_{side}_Inset", (0.205, 0.018, 0.435), (x, -0.319, 0.545), paint, 0.008)
box("Lower_Left_Chipped_Edge", (0.075, 0.012, 0.026), (-0.247, -0.323, 0.805), wood, 0.004)
box("Lower_Right_Chipped_Corner", (0.055, 0.012, 0.034), (0.244, -0.323, 0.292), wood, 0.004)

# Right upper door remains shut. The left one rotates around its outside hinge and
# projects toward the player, revealing the empty shelves behind it.
box("Upper_Right_Door", (0.265, 0.045, 0.515), (0.148, -0.292, 1.205), paint, 0.014)
box("Upper_Right_Inset", (0.205, 0.018, 0.385), (0.148, -0.319, 1.205), paint, 0.008)

open_angle = -deg(16)
hinge_x, hinge_y = -0.280, -0.267
half_door = 0.1325
open_x = hinge_x + half_door * 0.9613
open_y = hinge_y - half_door * 0.2756
box("Upper_Left_Door_Hanging_Open", (0.265, 0.045, 0.515),
    (open_x, open_y, 1.205), paint, 0.014, rotation=(0.0, 0.0, open_angle))
box("Upper_Left_Worn_Edge", (0.035, 0.012, 0.31),
    (open_x + 0.105, open_y - 0.049, 1.205), wood, 0.004,
    rotation=(0.0, 0.0, open_angle))

# Four dull brass knobs, with the upper-left knob moving with the open door.
for name, x, y, z in (
    ("Lower_Left_Knob", -0.055, -0.344, 0.56),
    ("Lower_Right_Knob", 0.055, -0.344, 0.56),
    ("Upper_Right_Knob", 0.055, -0.344, 1.205),
    ("Upper_Left_Knob", open_x + 0.090, open_y - 0.065, 1.205),
):
    cylinder(name, 0.026, 0.050, (x, y, z), brass, 12,
             rotation=(deg(90), 0.0, 0.0), bevel=0.005)

# A tide-like water stain crosses the lower doors in a few uneven, flat patches.
for i, (x, z, width) in enumerate(((-0.18, 0.36, 0.11), (-0.055, 0.34, 0.10),
                                    (0.065, 0.355, 0.09), (0.175, 0.33, 0.075))):
    box(f"Water_Stain_{i}", (width, 0.008, 0.022), (x, -0.345, z), stain, 0.005,
        rotation=(0.0, deg(i * 2 - 3), deg(i * 3 - 4)))

# Cracked right side panel: a dark jagged split and two short branches.
box("Side_Crack_Main", (0.009, 0.018, 0.31), (0.333, 0.055, 0.94), dark, 0.002,
    rotation=(deg(-13), 0.0, 0.0))
box("Side_Crack_Upper_Branch", (0.009, 0.018, 0.15), (0.333, 0.015, 1.09), dark, 0.002,
    rotation=(deg(38), 0.0, 0.0))
box("Side_Crack_Lower_Branch", (0.009, 0.018, 0.12), (0.333, 0.105, 0.82), dark, 0.002,
    rotation=(deg(-48), 0.0, 0.0))

# A scavenged metal repair strap and square-headed screws reinforce the other side.
box("Side_Repair_Strap", (0.014, 0.12, 0.28), (-0.333, 0.02, 0.72), edge, 0.005)
for y in (-0.025, 0.065):
    for z in (0.62, 0.82):
        cylinder(f"Repair_Screw_{y}_{z}", 0.012, 0.012, (-0.344, y, z), edge, 8,
                 rotation=(0.0, deg(90), 0.0))

finish("cabinet", (0.7, 1.6, 0.7))
