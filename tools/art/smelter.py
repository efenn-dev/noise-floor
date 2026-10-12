"""Powered smelter (scrap -> metal plate).

    blender.exe -b --factory-startup --python tools/art/smelter.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
firebrick = material("Firebrick", (0.30, 0.095, 0.055), 0.05, 0.94)
glow = material("Furnace Glow", (1.0, 0.72, 0.24), 0.0, 0.32, emission=4.0)
soot = material("Soot", (0.012, 0.014, 0.013), 0.05, 0.96)

# Broad skid and insulated furnace carcass.
box("Base_Skid", (1.56, 1.34, 0.13), (0.0, 0.0, 0.065), body_dark, 0.035)
for x in (-0.66, 0.66):
    box(f"Skid_Rail_{x}", (0.13, 1.48, 0.11), (x, 0.0, 0.135), bare, 0.025)
    for y in (-0.53, 0.53):
        cylinder(f"Anchor_Bolt_{x}_{y}", 0.035, 0.035, (x, y, 0.205), bare_edge, 10)

box("Furnace_Lower", (1.30, 1.05, 0.71), (0.0, 0.02, 0.545), body, 0.055)
box("Furnace_Upper", (1.22, 0.99, 0.32), (0.0, 0.02, 1.045), body_dark, 0.045)
box("Heat_Blackened_Top", (1.25, 1.02, 0.09), (0.0, 0.02, 1.245), soot, 0.035)

# Firebrick seams visible around the side access door on +X.
box("Door_Brick_Lintel", (0.035, 0.54, 0.10), (0.668, -0.04, 0.775), firebrick, 0.012)
box("Door_Brick_Sill", (0.035, 0.54, 0.10), (0.668, -0.04, 0.355), firebrick, 0.012)
for y in (-0.275, 0.195):
    box(f"Door_Brick_Jamb_{y}", (0.035, 0.10, 0.34), (0.668, y, 0.565), firebrick, 0.012)
box("Furnace_Door", (0.075, 0.43, 0.34), (0.695, -0.04, 0.565), bare, 0.025)
box("Door_Inner_Panel", (0.028, 0.31, 0.22), (0.741, -0.04, 0.565), soot, 0.012)
box("Door_Glow_Slit", (0.018, 0.235, 0.045), (0.759, -0.04, 0.585), glow, 0.006)
box("Door_Hinge_Top", (0.045, 0.085, 0.07), (0.754, 0.185, 0.675), bare_edge, 0.008)
box("Door_Hinge_Bottom", (0.045, 0.085, 0.07), (0.754, 0.185, 0.455), bare_edge, 0.008)
cylinder("Door_Wheel_Hub", 0.075, 0.055, (0.775, -0.245, 0.565), bare_edge, 12,
         rotation=(0.0, deg(90), 0.0), bevel=0.008)
for z in (0.495, 0.635):
    box(f"Door_Wheel_Spoke_{z}", (0.045, 0.035, 0.14), (0.808, -0.245, z), bare_edge, 0.006)

# Short offset flue, with a bolted collar, kept below the collision-box ceiling.
cylinder("Flue_Collar", 0.225, 0.075, (-0.31, 0.15, 1.325), bare, 14, bevel=0.012)
cylinder("Flue_Stack", 0.155, 0.24, (-0.31, 0.15, 1.455), soot, 14, bevel=0.012)
cylinder("Flue_Rim", 0.185, 0.055, (-0.31, 0.15, 1.545), bare_edge, 14, bevel=0.009)

# Thick scavenged power conduit down the -X side into a junction box.
box("Junction_Box", (0.22, 0.36, 0.31), (-0.70, 0.05, 0.48), body_dark, 0.025)
box("Junction_Face", (0.025, 0.27, 0.22), (-0.823, 0.05, 0.48), bare, 0.007)
cylinder("Conduit_Vertical", 0.055, 0.66, (-0.70, 0.05, 0.92), mat("rubber"), 12, bevel=0.008)
cylinder("Conduit_Top_Run", 0.055, 0.25, (-0.575, 0.05, 1.22), mat("rubber"), 12,
         rotation=(0.0, deg(90), 0.0), bevel=0.008)
for z in (0.72, 1.10):
    cylinder(f"Conduit_Clamp_{z}", 0.075, 0.045, (-0.70, 0.05, z), bare_edge, 12, bevel=0.006)
for y in (-0.055, 0.155):
    cylinder(f"Junction_Bolt_{y}", 0.022, 0.025, (-0.84, y, 0.48), bare_edge, 8,
             rotation=(0.0, deg(90), 0.0))

# INPUT (back, +Y): blue scrap funnel narrowing into the chamber.
hopper_tilt = deg(24)
box("Input_Hopper_Floor", (0.72, 0.43, 0.055), (0.0, 0.57, 0.92), mat("input_blue"), 0.012,
    rotation=(hopper_tilt, 0.0, 0.0))
for x, roll in ((-0.40, -12), (0.40, 12)):
    box(f"Input_Hopper_Wall_{x}", (0.075, 0.49, 0.34), (x, 0.58, 1.04), mat("input_blue"), 0.014,
        rotation=(hopper_tilt, deg(roll), 0.0))
box("Input_Hopper_Back", (0.86, 0.065, 0.38), (0.0, 0.75, 1.08), mat("input_blue"), 0.014,
    rotation=(hopper_tilt, 0.0, 0.0))
box("Input_Throat", (0.54, 0.18, 0.18), (0.0, 0.505, 0.82), mat("input_blue"), 0.018)
for x in (-0.30, 0.30):
    box(f"Hopper_Brace_{x}", (0.055, 0.055, 0.46), (x, 0.56, 0.70), bare, 0.009,
        rotation=(deg(-14), 0.0, 0.0))

# OUTPUT (front, -Y): orange pour nose and shallow plate-catching tray.
box("Output_Pour_Block", (0.47, 0.20, 0.19), (0.0, -0.555, 0.53), mat("output_orange"), 0.025)
box("Output_Pour_Lip", (0.34, 0.27, 0.075), (0.0, -0.635, 0.455), mat("output_orange"), 0.014,
    rotation=(deg(-16), 0.0, 0.0))
box("Output_Plate_Tray", (0.90, 0.43, 0.065), (0.0, -0.575, 0.285), mat("output_orange"), 0.016,
    rotation=(deg(7), 0.0, 0.0))
for x in (-0.46, 0.46):
    box(f"Tray_Rail_{x}", (0.055, 0.43, 0.13), (x, -0.575, 0.335), body_dark, 0.01,
        rotation=(deg(7), 0.0, 0.0))
box("Tray_Stop", (0.98, 0.065, 0.15), (0.0, -0.765, 0.325), body_dark, 0.014)
for x in (-0.35, 0.35):
    box(f"Tray_Leg_{x}", (0.07, 0.07, 0.24), (x, -0.61, 0.15), bare, 0.012)

# Front warning panel and mismatched repair plates sell the scavenged construction.
hazard_stripes("Front_Hazard", (0.0, -0.516, 0.90), 0.72, 0.15, 5, "-Y")
box("Front_Repair_Plate", (0.33, 0.026, 0.22), (-0.39, -0.523, 0.67), bare_edge, 0.012,
    rotation=(0.0, 0.0, deg(-4)))
for x in (-0.50, -0.28):
    for z in (0.59, 0.75):
        cylinder(f"Repair_Bolt_{x}_{z}", 0.018, 0.03, (x, -0.542, z), mat("rust"), 8,
                 rotation=(deg(90), 0.0, 0.0))
box("Side_Patch", (0.026, 0.26, 0.25), (-0.662, -0.25, 0.83), body_dark, 0.01,
    rotation=(deg(3), 0.0, 0.0))

# The flue is offset so the game-controlled status beacon remains near the visual centre.
lamp((0.13, -0.08, 1.29))

finish("smelter", (1.7, 1.6, 1.7))
