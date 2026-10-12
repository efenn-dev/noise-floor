"""Conveyor belt. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/belt.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, quad, reset  # noqa: E402

reset()
body_dark, bare, bare_edge = mat("body_dark"), mat("bare"), mat("bare_edge")
rubber, yellow = mat("rubber"), mat("yellow")

# Low scavenged frame: the belt remains the highest broad, flat surface.
for x in (-0.445, 0.445):
    box(f"Side_Rail_{x}", (0.09, 1.94, 0.085), (x, 0.0, 0.0875), body_dark, 0.012)
for y in (-0.70, 0.0, 0.70):
    box(f"Frame_Crossbar_{y}", (0.80, 0.09, 0.045), (0.0, y, 0.0575), bare, 0.007)

# Short feet keep the silhouette planted without exceeding the shallow collision box.
for x in (-0.40, 0.40):
    for y in (-0.72, 0.0, 0.72):
        box(f"Foot_{x}_{y}", (0.12, 0.18, 0.035), (x, y, 0.0175), body_dark, 0.009)

# End rollers are deliberately exposed beyond the rubber run and lie along X.
for label, y in (("Front", -0.90), ("Back", 0.90)):
    cylinder(f"{label}_Roller", 0.055, 0.80, (0.0, y, 0.082), bare_edge, 8,
             rotation=(0.0, deg(90), 0.0), bevel=0.006)
    cylinder(f"{label}_Axle_Left", 0.025, 0.09, (-0.445, y, 0.082), bare, 8,
             rotation=(0.0, deg(90), 0.0))
    cylinder(f"{label}_Axle_Right", 0.025, 0.09, (0.445, y, 0.082), bare, 8,
             rotation=(0.0, deg(90), 0.0))

# A broad, uninterrupted rubber deck for carried items.
box("Rubber_Belt", (0.78, 1.73, 0.035), (0.0, 0.0, 0.1225), rubber, 0.006)

# Two painted chevrons. Each V points toward Blender -Y (the conveyor output/front).
def stripe(name, start, end, width=0.075):
    sx, sy = start
    ex, ey = end
    dx, dy = ex - sx, ey - sy
    length = (dx * dx + dy * dy) ** 0.5
    nx, ny = -dy / length * width / 2, dx / length * width / 2
    quad(name, [(sx + nx, sy + ny, 0.1401), (ex + nx, ey + ny, 0.1401),
                (ex - nx, ey - ny, 0.1401), (sx - nx, sy - ny, 0.1401)], yellow)


for index, centre_y in enumerate((-0.38, 0.38)):
    tip = (0.0, centre_y - 0.17)
    stripe(f"Chevron_{index}_Left", (-0.22, centre_y + 0.10), tip)
    stripe(f"Chevron_{index}_Right", (0.22, centre_y + 0.10), tip)

# Side bolts and one mismatched repair plate sell the repeatedly patched town equipment.
for x in (-0.494, 0.494):
    for y in (-0.58, 0.0, 0.58):
        cylinder(f"Rail_Bolt_{x}_{y}", 0.017, 0.012, (x, y, 0.09), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))
box("Repair_Plate", (0.008, 0.30, 0.055), (-0.496, 0.28, 0.083), bare_edge, 0.004)
for y in (0.18, 0.38):
    cylinder(f"Repair_Bolt_{y}", 0.013, 0.010, (-0.495, y, 0.083), bare, 8,
             rotation=(0.0, deg(90), 0.0))

finish("belt", (1.0, 0.15, 2.0), max_triangles=1500)
