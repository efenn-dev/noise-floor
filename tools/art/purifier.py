"""Powered water purifier (dirty water -> clean water). Written by Codex for kit.py.

    blender.exe -b --factory-startup --python tools/art/purifier.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
gauge_white = material("Gauge White", (0.78, 0.76, 0.66), 0.05, 0.72)
copper = material("Copper Pipe", (0.34, 0.13, 0.055), 0.8, 0.48)


def pipe_y(name, radius, depth, location, material_=copper, vertices=12):
    """A horizontal pipe running front-to-back."""
    return cylinder(name, radius, depth, location, material_, vertices, rotation=(deg(90), 0.0, 0.0))


def pipe_x(name, radius, depth, location, material_=copper, vertices=12):
    """A horizontal pipe running left-to-right."""
    return cylinder(name, radius, depth, location, material_, vertices, rotation=(0.0, deg(90), 0.0))


def handwheel(name, location, radius=0.105):
    """Chunky front-facing valve wheel assembled from a hub, rim blocks, and spokes."""
    x, y, z = location
    cylinder(f"{name}_Hub", 0.034, 0.065, location, bare_edge, 12,
             rotation=(deg(90), 0.0, 0.0))
    for angle in (0, 45, 90, 135):
        box(f"{name}_Spoke_{angle}", (radius * 1.62, 0.035, 0.025), (x, y, z), bare_edge,
            rotation=(0.0, deg(angle), 0.0))
    for angle in range(0, 360, 45):
        a = deg(angle)
        box(f"{name}_Rim_{angle}", (0.060, 0.045, 0.033),
            (x + radius * __import__('math').cos(a), y, z + radius * __import__('math').sin(a)),
            bare_edge, rotation=(0.0, -a, 0.0))


# Low steel skid with feet, cross rails, and exposed anchor bolts.
box("Skid_Left_Rail", (0.24, 1.18, 0.14), (-0.48, 0.0, 0.11), body_dark, 0.025)
box("Skid_Right_Rail", (0.24, 1.18, 0.14), (0.48, 0.0, 0.11), body_dark, 0.025)
for y in (-0.45, 0.0, 0.45):
    box(f"Skid_Crossbar_{y}", (1.18, 0.14, 0.11), (0.0, y, 0.20), body)
for x in (-0.54, 0.54):
    for y in (-0.50, 0.50):
        box(f"Skid_Foot_{x}_{y}", (0.18, 0.18, 0.08), (x, y, 0.04), bare)
        cylinder(f"Anchor_Bolt_{x}_{y}", 0.025, 0.038, (x, y, 0.105), bare_edge, 8)

# Twin tall filter canisters, deliberately faceted for the low-poly silhouette.
for side, x in (("Left", -0.34), ("Right", 0.34)):
    cylinder(f"{side}_Canister", 0.225, 0.72, (x, 0.08, 0.72), body, 14, bevel=0.016)
    cylinder(f"{side}_Lower_Flange", 0.255, 0.075, (x, 0.08, 0.37), bare, 14)
    cylinder(f"{side}_Upper_Flange", 0.255, 0.075, (x, 0.08, 1.07), bare, 14)
    # Stepped, domed-looking cap and central plumbing boss.
    cylinder(f"{side}_Cap_Lower", 0.215, 0.075, (x, 0.08, 1.135), body_dark, 14, bevel=0.012)
    cylinder(f"{side}_Cap_Upper", 0.155, 0.065, (x, 0.08, 1.195), body_dark, 14)
    cylinder(f"{side}_Cap_Boss", 0.065, 0.085, (x, 0.08, 1.265), copper, 12)
    # Vertical wear strip and clamp bands make each tank read as scavenged hardware.
    box(f"{side}_Wear_Strip", (0.075, 0.018, 0.46), (x - 0.13, -0.151, 0.72), bare_edge)
    for z in (0.52, 0.90):
        cylinder(f"{side}_Clamp_{z}", 0.233, 0.045, (x, 0.08, z), bare_edge, 14)

# Copper manifold: two risers joined across the top, with chunky elbow blocks.
for x in (-0.34, 0.34):
    cylinder(f"Top_Riser_{x}", 0.045, 0.15, (x, 0.08, 1.355), copper, 12)
    cylinder(f"Top_Elbow_{x}", 0.070, 0.070, (x, 0.08, 1.415), copper, 12)
pipe_x("Top_Manifold", 0.045, 0.68, (0.0, 0.08, 1.415), copper, 12)
for x in (-0.34, 0.34):
    cylinder(f"Manifold_Collar_{x}", 0.073, 0.055, (x, 0.08, 1.32), bare, 12)

# Front valve stems and handwheels, one per filter stage.
for side, x in (("Left", -0.34), ("Right", 0.34)):
    pipe_y(f"{side}_Valve_Stem", 0.036, 0.19, (x, -0.22, 1.10), copper, 12)
    cylinder(f"{side}_Valve_Body", 0.075, 0.095, (x, -0.12, 1.10), bare, 12,
             rotation=(deg(90), 0.0, 0.0))
    handwheel(f"{side}_Handwheel", (x, -0.335, 1.10), 0.105)

# Small pump motor low on the front-left, with drive housing and pipe connection.
cylinder("Pump_Motor", 0.15, 0.32, (-0.36, -0.31, 0.34), body_dark, 14,
         rotation=(0.0, deg(90), 0.0), bevel=0.016)
cylinder("Pump_Endbell", 0.165, 0.065, (-0.53, -0.31, 0.34), bare, 14,
         rotation=(0.0, deg(90), 0.0))
cylinder("Pump_Drive_Housing", 0.125, 0.16, (-0.15, -0.31, 0.34), bare, 14,
         rotation=(0.0, deg(90), 0.0))
box("Pump_Mount", (0.54, 0.28, 0.075), (-0.31, -0.31, 0.225), bare_edge)
for x in (-0.49, -0.13):
    cylinder(f"Pump_Mount_Bolt_{x}", 0.022, 0.035, (x, -0.43, 0.28), bare_edge, 8)

# Pressure gauge on a central bracket, with an off-white face and simple black needle.
box("Gauge_Bracket", (0.18, 0.11, 0.22), (0.0, -0.13, 1.24), bare)
pipe_y("Gauge_Neck", 0.035, 0.12, (0.0, -0.22, 1.31), copper, 10)
cylinder("Gauge_Bezel", 0.135, 0.055, (0.0, -0.31, 1.31), mat("black"), 12,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Gauge_Face", 0.108, 0.012, (0.0, -0.342, 1.31), gauge_white, 12,
         rotation=(deg(90), 0.0, 0.0))
box("Gauge_Needle", (0.018, 0.012, 0.075), (0.025, -0.350, 1.335), mat("black"),
    0.002, rotation=(0.0, deg(-35), 0.0))
cylinder("Gauge_Pivot", 0.018, 0.015, (0.0, -0.354, 1.31), bare, 10,
         rotation=(deg(90), 0.0, 0.0))

# Right-side control box and its unmistakable front-facing emergency button.
box("Control_Box", (0.27, 0.25, 0.36), (0.535, -0.20, 0.72), body_dark, 0.025)
box("Control_Face", (0.22, 0.025, 0.29), (0.535, -0.338, 0.72), bare)
cylinder("Button_Bezel", 0.066, 0.025, (0.535, -0.357, 0.77), mat("black"), 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Red_Button", 0.047, 0.042, (0.535, -0.383, 0.77), mat("red"), 14,
         rotation=(deg(90), 0.0, 0.0))
hazard_stripes("Control_Hazard", (0.535, -0.352, 0.62), 0.17, 0.075, 4, "-Y")

# A bolted repair patch on the more visible left tank.
box("Tank_Repair_Plate", (0.18, 0.025, 0.23), (-0.34, -0.158, 0.72), bare_edge, 0.012)
for x in (-0.405, -0.275):
    for z in (0.64, 0.80):
        pipe_y(f"Repair_Bolt_{x}_{z}", 0.014, 0.034, (x, -0.179, z), bare, 8)

# INPUT (back, +Y): blue intake flange, supported by an otherwise copper feed pipe.
pipe_y("Intake_Pipe", 0.070, 0.43, (-0.34, 0.43, 0.48), copper, 14)
cylinder("Input_Flange", 0.145, 0.075, (-0.34, 0.650, 0.48), mat("input_blue"), 12,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Input_Mouth", 0.090, 0.035, (-0.34, 0.670, 0.48), mat("input_blue"), 16,
         rotation=(deg(90), 0.0, 0.0))

# OUTPUT (front, -Y): orange spigot housing and nozzle on the clean-water side.
pipe_y("Outlet_Pipe", 0.060, 0.35, (0.34, -0.40, 0.48), copper, 14)
cylinder("Output_Housing", 0.135, 0.14, (0.34, -0.575, 0.48), mat("output_orange"), 16,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Output_Nozzle", 0.075, 0.070, (0.34, -0.660, 0.48), mat("output_orange"), 14,
         rotation=(deg(90), 0.0, 0.0))

# Status beacon sits on a welded centre bracket above the gauge/manifold.
box("Lamp_Bracket", (0.22, 0.18, 0.045), (0.0, -0.05, 1.425), body_dark)
lamp((0.0, -0.05, 1.448))

finish("purifier", (1.4, 1.5, 1.4))
