"""Industrial canner (food -> canned food). Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/canner.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
rust = mat("rust")
tin = material("Tin", (0.62, 0.66, 0.64), 0.9, 0.3)
label_paper = material("Label Paper", (0.64, 0.55, 0.37), 0.05, 0.82)


def can(name: str, location: tuple[float, float, float], labelled: bool = False) -> None:
    """A chunky low-poly food can with raised lid and base rims."""
    x, y, z = location
    cylinder(f"{name}_Body", 0.082, 0.19, (x, y, z), tin, 12)
    cylinder(f"{name}_Top_Rim", 0.088, 0.018, (x, y, z + 0.091), bare_edge, 12)
    cylinder(f"{name}_Bottom_Rim", 0.088, 0.018, (x, y, z - 0.091), bare_edge, 12)
    if labelled:
        cylinder(f"{name}_Label", 0.084, 0.095, (x, y, z - 0.005), label_paper, 12)


# Cabinet base: broad, battered and nearly fills the collision footprint.
box("Cabinet_Foot", (1.46, 1.18, 0.12), (0.0, 0.02, 0.06), body_dark, 0.035)
box("Cabinet", (1.36, 1.04, 0.52), (0.0, 0.04, 0.37), body, 0.045)
box("Cabinet_Top", (1.46, 1.12, 0.10), (0.0, 0.02, 0.67), bare, 0.025)
for x in (-0.62, 0.62):
    for y in (-0.43, 0.43):
        cylinder(f"Mount_Bolt_{x}_{y}", 0.027, 0.025, (x, y, 0.735), bare_edge, 8)

# Front access doors, hinges and a deliberately mismatched repair plate.
for x in (-0.32, 0.32):
    box(f"Access_Door_{x}", (0.56, 0.025, 0.36), (x, -0.495, 0.37), body_dark, 0.018)
    box(f"Door_Handle_{x}", (0.055, 0.035, 0.17), (x + 0.20, -0.525, 0.39), bare_edge, 0.012)
    for z in (0.24, 0.50):
        cylinder(f"Door_Hinge_{x}_{z}", 0.025, 0.08, (x - 0.23, -0.527, z), bare, 8)
box("Cabinet_Repair_Plate", (0.25, 0.024, 0.20), (-0.48, -0.511, 0.36), bare_edge, 0.012, rotation=(0.0, deg(-5), 0.0))
for x in (-0.57, -0.39):
    for z in (0.30, 0.43):
        cylinder(f"Repair_Rivet_{x}_{z}", 0.014, 0.018, (x, -0.535, z), rust, 8, rotation=(deg(90), 0.0, 0.0))

# Short front-to-back conveyor, rollers, and guide rails.
box("Conveyor_Bed", (0.57, 1.29, 0.09), (-0.08, 0.0, 0.76), bare, 0.018)
box("Conveyor_Belt", (0.46, 1.25, 0.035), (-0.08, 0.0, 0.825), mat("rubber"), 0.012)
for y in (-0.52, -0.26, 0.0, 0.26, 0.52):
    cylinder(f"Conveyor_Roller_{y}", 0.035, 0.55, (-0.08, y, 0.80), bare_edge, 10,
             rotation=(0.0, deg(90), 0.0))
for x in (-0.39, 0.23):
    box(f"Conveyor_Rail_{x}", (0.055, 1.29, 0.12), (x, 0.0, 0.84), body_dark)

# Sealing head and its asymmetric supporting column.
box("Head_Column", (0.25, 0.38, 0.70), (0.47, 0.04, 1.08), body_dark, 0.03)
box("Head_Crossarm", (0.93, 0.43, 0.20), (0.09, 0.04, 1.35), body, 0.035)
box("Head_Underside", (0.70, 0.34, 0.07), (-0.08, 0.04, 1.225), bare, 0.014)
cylinder("Sealer_Ram", 0.075, 0.25, (-0.08, 0.04, 1.13), bare_edge, 14)
cylinder("Seaming_Chuck", 0.145, 0.10, (-0.08, 0.04, 0.975), bare, 14)
cylinder("Chuck_Wear_Ring", 0.158, 0.035, (-0.08, 0.04, 0.93), rust, 14)
hazard_stripes("Head_Hazard", (-0.16, -0.181, 1.35), 0.56, 0.12, 5, "-Y")
lamp((0.09, 0.04, 1.46), 0.065)

# Crank/gear housing on the right side, with a hand crank facing +X.
cylinder("Gear_Housing", 0.24, 0.15, (0.59, 0.05, 1.05), body_dark, 14,
         rotation=(0.0, deg(90), 0.0))
cylinder("Gear_Hub", 0.085, 0.19, (0.69, 0.05, 1.05), bare_edge, 12,
         rotation=(0.0, deg(90), 0.0))
box("Crank_Arm", (0.035, 0.055, 0.31), (0.705, 0.05, 1.18), bare, 0.012,
    rotation=(deg(18), 0.0, deg(-10)))
cylinder("Crank_Handle", 0.045, 0.15, (0.72, 0.00, 1.33), mat("rubber"), 10,
         rotation=(deg(90), 0.0, 0.0))

# Side control box; its single red mushroom button points toward the operator.
box("Control_Box", (0.32, 0.22, 0.31), (0.50, -0.35, 1.12), body_dark, 0.028)
box("Control_Face", (0.25, 0.025, 0.24), (0.50, -0.473, 1.12), bare, 0.010)
cylinder("Stop_Button_Bezel", 0.065, 0.025, (0.50, -0.495, 1.15), mat("black"), 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Red_Stop_Button", 0.047, 0.045, (0.50, -0.528, 1.15), mat("red"), 14,
         rotation=(deg(90), 0.0, 0.0))

# Empty-can staging rack at the left side, with two neat scavenged stacks.
box("Can_Rack_Shelf", (0.35, 0.58, 0.055), (-0.53, 0.18, 0.91), bare, 0.012)
for x in (-0.61, -0.45):
    for y in (0.04, 0.24):
        for level in range(2):
            can(f"Empty_Can_{x}_{y}_{level}", (x, y, 1.02 + level * 0.19))
for x in (-0.70, -0.36):
    box(f"Rack_Guard_{x}", (0.035, 0.58, 0.17), (x, 0.18, 0.98), body_dark)

# INPUT (back, +Y): a conspicuous food hopper feeding down to the belt.
box("Input_Hopper_Back", (0.62, 0.055, 0.31), (-0.08, 0.69, 1.03), mat("input_blue"), 0.015,
    rotation=(deg(-12), 0.0, 0.0))
box("Input_Hopper_Floor", (0.62, 0.34, 0.055), (-0.08, 0.57, 0.89), mat("input_blue"), 0.012,
    rotation=(deg(-18), 0.0, 0.0))
for x in (-0.41, 0.25):
    box(f"Input_Hopper_Side_{x}", (0.055, 0.34, 0.27), (x, 0.57, 0.99), mat("input_blue"),
        rotation=(deg(-10), 0.0, 0.0))

# OUTPUT (front, -Y): orange delivery tray with several clearly finished cans.
tray_tilt = (deg(9), 0.0, 0.0)
box("Output_Tray", (0.68, 0.38, 0.055), (-0.08, -0.60, 0.77), mat("output_orange"), 0.014,
    rotation=tray_tilt)
for x in (-0.45, 0.29):
    box(f"Output_Tray_Rail_{x}", (0.055, 0.38, 0.13), (x, -0.60, 0.82), body_dark,
        rotation=tray_tilt)
box("Output_Stop_Lip", (0.79, 0.055, 0.13), (-0.08, -0.765, 0.76), mat("output_orange"), 0.012)
can("Finished_Can_Left", (-0.24, -0.55, 0.91), True)
can("Finished_Can_Right", (0.08, -0.62, 0.90), True)

finish("canner", (1.6, 1.5, 1.6))
