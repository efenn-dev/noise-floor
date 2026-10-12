"""Scavenged base door. Written by Codex, using kit.py.

    blender.exe -b --factory-startup --python tools/art/door.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
wood = material("Weathered Wood", (0.24, 0.19, 0.14), 0.05, 0.88)
sheet = material("Sheet Metal", (0.38, 0.40, 0.39), 0.70, 0.55)


def face_bolt(name: str, x: float, z: float, side: int, radius: float = 0.018) -> None:
    """A low-profile bolt head on either broad face, kept inside the thin collision box."""
    cylinder(name, radius, 0.012, (x, side * 0.053, z), bare_edge, 6,
             rotation=(deg(90), 0.0, 0.0))


def diagonal_bar(name: str, start: tuple[float, float], end: tuple[float, float],
                 y: float, material_) -> None:
    """A box aligned between two X/Z points, used for the welded Z brace."""
    x1, z1 = start
    x2, z2 = end
    dx, dz = x2 - x1, z2 - z1
    length = (dx * dx + dz * dz) ** 0.5
    angle = -__import__("math").atan2(dz, dx)
    box(name, (length, 0.016, 0.105), ((x1 + x2) / 2, y, (z1 + z2) / 2),
        material_, 0.008, rotation=(0.0, angle, 0.0))


# A single welded slab: inset salvaged panels inside a deep perimeter frame.
box("Left_Stile", (0.14, 0.072, 2.32), (-0.91, 0.0, 1.20), body_dark, 0.018)
box("Hinge_Stile", (0.14, 0.072, 2.32), (0.91, 0.0, 1.20), body_dark, 0.018)
box("Bottom_Rail", (1.82, 0.072, 0.13), (0.0, 0.0, 0.105), body_dark, 0.018)
box("Top_Rail", (1.82, 0.072, 0.13), (0.0, 0.0, 2.295), body_dark, 0.018)

# Dull sheet-metal bays and narrow grey-brown boards make the infill feel scavenged.
box("Left_Sheet", (0.545, 0.034, 2.03), (-0.565, 0.0, 1.20), sheet, 0.010)
box("Centre_Sheet", (0.545, 0.034, 2.03), (0.0, 0.0, 1.20), body, 0.010)
for i, x in enumerate((0.405, 0.575, 0.745)):
    box(f"Wood_Plank_{i}", (0.145, 0.038, 2.03), (x, 0.0, 1.20), wood, 0.009)
for x in (-0.285, 0.295):
    box(f"Panel_Seam_{x}", (0.045, 0.064, 2.08), (x, 0.0, 1.20), bare, 0.008)

# The outer rails and this diagonal read as a Z brace from either side.
for side, label in ((-1, "Front"), (1, "Back")):
    diagonal_bar(f"{label}_Z_Brace", (-0.77, 2.12), (0.77, 0.28), side * 0.044, bare)

# Mirrored repair work gives both faces a finished, used history.
for side, label in ((-1, "Front"), (1, "Back")):
    box(f"{label}_Lower_Patch", (0.31, 0.012, 0.27), (-0.50, side * 0.043, 0.53),
        bare_edge, 0.008, rotation=(0.0, 0.0, deg(side * 3)))
    box(f"{label}_Upper_Patch", (0.26, 0.012, 0.34), (0.48, side * 0.043, 1.75),
        sheet, 0.008, rotation=(0.0, 0.0, deg(side * -4)))
    for j, (x, z) in enumerate(((-0.61, 0.43), (-0.39, 0.62), (0.39, 1.62), (0.57, 1.88))):
        face_bolt(f"{label}_Patch_Bolt_{j}", x, z, side)

# Compact warning bands stay visible low on both faces without dominating the door.
hazard_stripes("Front_Hazard", (0.48, -0.047, 0.32), 0.40, 0.105, 4, "-Y")
hazard_stripes("Back_Hazard", (0.48, 0.047, 0.32), 0.40, 0.105, 4, "+Y")

# Three vertical hinge knuckles and welded leaves along Blender +X.
for i, z in enumerate((0.45, 1.20, 1.95)):
    cylinder(f"Hinge_Knuckle_{i}", 0.047, 0.29, (0.925, 0.0, z), bare, 10, bevel=0.005)
    cylinder(f"Hinge_Pin_{i}", 0.025, 0.335, (0.925, 0.0, z), bare_edge, 8)
    for side, label in ((-1, "Front"), (1, "Back")):
        box(f"{label}_Hinge_Leaf_{i}", (0.20, 0.012, 0.19), (0.82, side * 0.043, z),
            body_dark, 0.006)
        face_bolt(f"{label}_Hinge_Bolt_{i}", 0.77, z, side, 0.016)

# Latch and horizontal handle sit 0.28 m in from the -X edge, on both faces.
for side, label in ((-1, "Front"), (1, "Back")):
    box(f"{label}_Latch_Plate", (0.25, 0.012, 0.27), (-0.72, side * 0.047, 1.05),
        bare, 0.008)
    box(f"{label}_Latch_Bolt", (0.31, 0.016, 0.055), (-0.53, side * 0.047, 1.10),
        bare_edge, 0.006)
    cylinder(f"{label}_Handle_Rose", 0.060, 0.016, (-0.72, side * 0.047, 1.02),
             body_dark, 12, rotation=(deg(90), 0.0, 0.0), bevel=0.004)
    cylinder(f"{label}_Handle_Standoff", 0.030, 0.035, (-0.72, side * 0.038, 1.02),
             bare_edge, 10, rotation=(deg(90), 0.0, 0.0))
    cylinder(f"{label}_Handle_Grip", 0.024, 0.25, (-0.585, side * 0.034, 1.02),
             mat("black"), 10, rotation=(0.0, deg(90), 0.0), bevel=0.003)

finish("door", (2.0, 2.4, 0.12))
