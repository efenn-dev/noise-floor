"""Industrial press (metal plate -> nails). Written by Codex, moved onto kit.py.

    blender.exe -b --factory-startup --python tools/art/press.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")

# Heavy base and lower frame.
box("Base_Plate", (1.50, 1.10, 0.14), (0.0, 0.0, 0.07), body_dark, 0.035)
box("Base_Raised_Pad", (1.20, 0.82, 0.12), (0.0, 0.03, 0.18), body, 0.025)
for x in (-0.63, 0.63):
    for y in (-0.43, 0.43):
        cylinder(f"Anchor_Bolt_{x}_{y}", 0.035, 0.035, (x, y, 0.155), bare_edge, 10)

# Four guide columns with chunky collars top and bottom.
for xi, x in enumerate((-0.51, 0.51)):
    for yi, y in enumerate((-0.27, 0.27)):
        cylinder(f"Guide_Column_{xi}_{yi}", 0.062, 0.93, (x, y, 0.70), bare, 12)
        cylinder(f"Lower_Collar_{xi}_{yi}", 0.092, 0.075, (x, y, 0.285), bare_edge, 12, bevel=0.008)
        cylinder(f"Upper_Collar_{xi}_{yi}", 0.092, 0.075, (x, y, 1.115), bare_edge, 12, bevel=0.008)

# Die bed and stepped tool block.
box("Die_Bed", (1.12, 0.67, 0.15), (0.0, 0.0, 0.34), bare, 0.025)
box("Lower_Die", (0.70, 0.40, 0.095), (0.0, -0.01, 0.455), bare_edge, 0.016)
box("Die_Insert", (0.42, 0.24, 0.045), (0.0, -0.01, 0.525), mat("black"), 0.008)

# Ram/platen, hydraulic rod and barrel.
box("Ram_Platen", (1.02, 0.61, 0.17), (0.0, 0.0, 0.70), bare, 0.025)
box("Ram_Wear_Plate", (0.79, 0.44, 0.075), (0.0, -0.005, 0.585), bare_edge, 0.012)
cylinder("Hydraulic_Rod", 0.072, 0.25, (0.0, 0.0, 0.88), bare_edge, 14, bevel=0.008)
cylinder("Hydraulic_Cylinder", 0.175, 0.37, (0.0, 0.0, 1.075), body_dark, 14, bevel=0.012)
cylinder("Cylinder_Lower_Flange", 0.215, 0.065, (0.0, 0.0, 0.91), bare, 14, bevel=0.009)
cylinder("Cylinder_Upper_Flange", 0.215, 0.065, (0.0, 0.0, 1.24), bare, 14, bevel=0.009)

# Overhead frame: a low central crown (the lamp sits on it) plus taller side shoulders.
box("Crown_Beam", (1.34, 0.72, 0.16), (0.0, 0.0, 1.25), body, 0.03)
for x in (-0.63, 0.63):
    box(f"Crown_Shoulder_{x}", (0.19, 0.72, 0.22), (x, 0.0, 1.29), body_dark, 0.025)
    box(f"Side_Gusset_{x}", (0.20, 0.48, 0.28), (x, 0.0, 1.06), body, 0.025)
lamp((0.0, 0.0, 1.33))

# Hazard stripes on the front of the ram.
hazard_stripes("Ram_Hazard", (0.0, -0.314, 0.70), 0.76, 0.13, 5, "-Y")

# Side-mounted scavenged control box. Button points out along +X.
box("Control_Box", (0.22, 0.31, 0.29), (0.64, -0.02, 0.81), body_dark, 0.025)
box("Control_Box_Face", (0.025, 0.245, 0.225), (0.762, -0.02, 0.81), bare, 0.007)
cylinder("Red_Stop_Button", 0.056, 0.042, (0.795, -0.02, 0.85), mat("red"), 14, rotation=(0.0, deg(90), 0.0), bevel=0.007)
cylinder("Button_Bezel", 0.076, 0.022, (0.778, -0.02, 0.85), mat("black"), 14, rotation=(0.0, deg(90), 0.0), bevel=0.005)

# OUTPUT (front, -Y): orange sloped chute with a rubber catch lip.
tilt = (deg(18), 0.0, 0.0)
box("Output_Chute", (0.68, 0.37, 0.055), (0.0, -0.47, 0.285), mat("output_orange"), 0.012, rotation=tilt)
box("Chute_Left_Rail", (0.055, 0.37, 0.105), (-0.34, -0.47, 0.32), body_dark, 0.01, rotation=tilt)
box("Chute_Right_Rail", (0.055, 0.37, 0.105), (0.34, -0.47, 0.32), body_dark, 0.01, rotation=tilt)
box("Chute_Rubber_Lip", (0.76, 0.065, 0.075), (0.0, -0.645, 0.225), mat("rubber"), 0.012)

# INPUT (back, +Y): blue feed tray sloping down into the die.
back_tilt = (deg(-20), 0.0, 0.0)
box("Feed_Tray", (0.62, 0.34, 0.05), (0.0, 0.50, 0.50), mat("input_blue"), 0.012, rotation=back_tilt)
for x in (-0.33, 0.33):
    box(f"Feed_Rail_{x}", (0.05, 0.34, 0.11), (x, 0.50, 0.54), body_dark, 0.01, rotation=back_tilt)
for x in (-0.24, 0.24):
    box(f"Feed_Leg_{x}", (0.05, 0.05, 0.36), (x, 0.60, 0.25), bare, 0.008)

# Repair plates sell the worn, scavenged build without texture detail.
box("Left_Repair_Plate", (0.17, 0.025, 0.25), (-0.675, 0.20, 0.72), bare_edge, 0.01)
box("Back_Service_Plate", (0.36, 0.025, 0.25), (0.22, 0.372, 0.82), body_dark, 0.012)
for i, z in enumerate((0.74, 0.90)):
    cylinder(f"Service_Bolt_{i}", 0.022, 0.03, (0.22, 0.393, z), bare_edge, 8, rotation=(deg(90), 0.0, 0.0))

finish("press", (1.7, 1.4, 1.7))
