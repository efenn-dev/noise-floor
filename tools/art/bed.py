"""Scavenged survivor bed. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/bed.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()

# The three bed-specific finishes allowed by the brief.  They are deliberately
# dull and low-contrast so the prop belongs beside the shared industrial set.
mattress = material("Mattress", (0.48, 0.44, 0.34), 0.0, 0.92)
blanket = material("Blanket", (0.25, 0.27, 0.15), 0.0, 0.98)
wood = material("Weathered Wood", (0.25, 0.20, 0.15), 0.0, 0.94)
bare, bare_edge, body_dark = mat("bare"), mat("bare_edge"), mat("body_dark")

# A rough pallet base: three heavy runners, end blocks, and uneven slats.  Tiny
# deterministic offsets keep it from looking like newly manufactured furniture.
for i, x in enumerate((-0.34, 0.0, 0.34)):
    box(f"Pallet_Runner_{i}", (0.14, 1.74, 0.10), (x, 0.0, 0.05), wood)

for row, y in enumerate((-0.69, 0.0, 0.69)):
    for col, x in enumerate((-0.34, 0.0, 0.34)):
        box(f"Pallet_Block_{row}_{col}", (0.18, 0.22, 0.105),
            (x, y, 0.082), wood, rotation=(0.0, 0.0, deg((row + col) * 0.35)))

slat_y = (-0.77, -0.55, -0.33, -0.11, 0.11, 0.33, 0.55, 0.77)
slat_z = (0.135, 0.139, 0.136, 0.141, 0.137, 0.140, 0.135, 0.138)
slat_turn = (-0.4, 0.25, -0.2, 0.35, -0.3, 0.15, -0.25, 0.3)
for i, (y, z, turn) in enumerate(zip(slat_y, slat_z, slat_turn)):
    box(f"Pallet_Top_Slat_{i}", (0.92, 0.17, 0.065), (0.0, y, z), wood,
        0.012 if i in (0, 2, 4, 6, 7) else 0.0, rotation=(0.0, 0.0, deg(turn)))

# Bent steel straps and large fasteners make the base visibly scavenged.  The
# right strap is a separate repair rather than a mirrored factory detail.
box("Left_Repair_Strap", (0.025, 0.48, 0.115), (-0.472, 0.22, 0.105), bare_edge, 0.006,
    rotation=(deg(-2), 0.0, 0.0))
box("Right_Repair_Strap", (0.025, 0.34, 0.105), (0.472, -0.46, 0.112), bare, 0.006,
    rotation=(deg(3), 0.0, 0.0))
for side, x, ys in (("L", -0.486, (0.05, 0.37)), ("R", 0.486, (-0.57, -0.36))):
    for i, y in enumerate(ys):
        cylinder(f"Strap_Bolt_{side}_{i}", 0.026, 0.025, (x, y, 0.112), bare_edge, 10,
                 rotation=(0.0, deg(90), 0.0), bevel=0.004)

# Thick stained mattress with a dark ticking seam around the visible front and
# sides.  It fills the collision footprint but leaves the pallet ends readable.
box("Worn_Mattress", (0.94, 1.72, 0.155), (0.0, -0.005, 0.245), mattress, 0.045)
box("Front_Mattress_Seam", (0.78, 0.018, 0.018), (0.0, -0.872, 0.245), body_dark, 0.005)
for x in (-0.476, 0.476):
    box(f"Side_Mattress_Seam_{x}", (0.016, 1.46, 0.018), (x, -0.02, 0.242),
        body_dark, 0.004)

# A compressed pillow at the FRONT (-Y) end.  Two overlapping padded slabs give
# it a lopsided, slept-in outline while remaining chunky at gameplay distance.
box("Pillow_Lower", (0.70, 0.39, 0.085), (-0.02, -0.615, 0.350), mattress, 0.038,
    rotation=(deg(-2.0), deg(1.5), deg(-2.0)))
box("Pillow_Crown", (0.58, 0.31, 0.070), (0.055, -0.625, 0.401), mattress, 0.032,
    rotation=(deg(-1.0), deg(-2.0), deg(1.5)))
box("Pillow_Centre_Dent", (0.22, 0.16, 0.018), (0.03, -0.64, 0.438), body_dark, 0.008,
    rotation=(0.0, deg(2.0), deg(2.0)))

# Rumpled blanket over the back two-thirds.  Broad overlapping slabs read as one
# folded wool cover; alternating pitches form a simple low-poly ridge pattern.
blanket_rows = (
    (-0.18, 0.34, 0.350, -2.0, 1.6, -0.5),
    (0.08, 0.36, 0.365, 2.4, -1.8, 0.7),
    (0.35, 0.35, 0.354, -2.8, 1.2, -0.6),
    (0.61, 0.35, 0.367, 2.0, -1.4, 0.5),
    (0.79, 0.20, 0.350, -1.2, 0.8, -0.4),
)
for i, (y, depth, z, pitch, roll, yaw) in enumerate(blanket_rows):
    box(f"Rumpled_Blanket_{i}", (0.89, depth, 0.075), (0.0, y, z), blanket, 0.025,
        rotation=(deg(pitch), deg(roll), deg(yaw)))

# One patched corner and a small folded towel/book-like bundle at the foot add
# story detail without introducing another material or stealing the silhouette.
box("Blanket_Patch", (0.24, 0.23, 0.018), (-0.23, 0.34, 0.410), body_dark, 0.006,
    rotation=(deg(-2.0), deg(1.0), deg(-5.0)))
for x, y in ((-0.32, 0.26), (-0.14, 0.25), (-0.31, 0.43), (-0.13, 0.42)):
    cylinder(f"Patch_Stitch_{x}_{y}", 0.009, 0.014, (x, y, 0.425), bare_edge, 8,
             bevel=0.002)

box("Folded_Towel_Lower", (0.27, 0.20, 0.045), (0.27, -0.39, 0.344), blanket, 0.014,
    rotation=(0.0, 0.0, deg(-5.0)))
box("Folded_Towel_Upper", (0.25, 0.18, 0.040), (0.255, -0.40, 0.383), blanket, 0.013,
    rotation=(0.0, 0.0, deg(3.0)))

finish("bed", (1.0, 0.5, 1.9), max_triangles=2000)
