"""Fuel-burning generator. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/generator.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
fuel_red = material("Fuel Tank Red", (0.46, 0.055, 0.035), 0.25, 0.76)
engine_grey = material("Engine Grey", (0.20, 0.22, 0.21), 0.70, 0.60)
soot = material("Soot", (0.012, 0.010, 0.009), 0.05, 0.96)


def tube_x(name, length, location, radius=0.035, material_=None):
    """Low-poly cage tube running along X."""
    return cylinder(name, radius, length, location, material_ or bare, 10,
                    rotation=(0.0, deg(90), 0.0))


def tube_y(name, length, location, radius=0.035, material_=None):
    """Low-poly cage tube running along Y."""
    return cylinder(name, radius, length, location, material_ or bare, 10,
                    rotation=(deg(90), 0.0, 0.0))


# Wide steel skid, fork channels and four battered mounting feet.
box("Skid_Left", (0.16, 1.08, 0.12), (-0.65, 0.0, 0.08), body_dark, 0.025)
box("Skid_Right", (0.16, 1.08, 0.12), (0.65, 0.0, 0.08), body_dark, 0.025)
box("Skid_Front_Tie", (1.45, 0.13, 0.10), (0.0, -0.48, 0.11), bare, 0.02)
box("Skid_Back_Tie", (1.45, 0.13, 0.10), (0.0, 0.48, 0.11), bare, 0.02)
for xi, x in enumerate((-0.65, 0.65)):
    for yi, y in enumerate((-0.42, 0.42)):
        box(f"Rubber_Foot_{xi}_{yi}", (0.23, 0.20, 0.07), (x, y, 0.035), mat("rubber"), 0.018)
        cylinder(f"Skid_Bolt_{xi}_{yi}", 0.027, 0.032, (x, y, 0.175), bare_edge, 8)

# Open tubular roll cage. Uprights and roof rails make the silhouette legible at distance.
for xi, x in enumerate((-0.70, 0.70)):
    for yi, y in enumerate((-0.47, 0.47)):
        cylinder(f"Cage_Upright_{xi}_{yi}", 0.038, 1.05, (x, y, 0.65), bare, 10)
for yi, y in enumerate((-0.47, 0.47)):
    tube_x(f"Cage_Roof_X_{yi}", 1.40, (0.0, y, 1.175), 0.038)
for xi, x in enumerate((-0.70, 0.70)):
    tube_y(f"Cage_Roof_Y_{xi}", 0.94, (x, 0.0, 1.175), 0.038)

# Faded red top tank with chunky straps, filler neck and cap.
box("Fuel_Tank", (0.92, 0.66, 0.25), (-0.16, 0.04, 0.985), fuel_red, 0.065)
for x in (-0.47, 0.15):
    box(f"Tank_Strap_{x}", (0.075, 0.69, 0.27), (x, 0.04, 0.988), bare, 0.012)
cylinder("Filler_Neck", 0.060, 0.055, (-0.43, -0.08, 1.135), bare_edge, 12)
cylinder("Filler_Cap", 0.082, 0.035, (-0.43, -0.08, 1.175), body_dark, 12)
for angle in (0, 90):
    box(f"Cap_Grip_{angle}", (0.11, 0.025, 0.018), (-0.43, -0.08, 1.196), bare_edge, 0.004,
        rotation=(0.0, 0.0, deg(angle)))

# Cast engine block, head and clearly stacked cooling fins.
box("Engine_Crankcase", (0.62, 0.54, 0.40), (-0.13, 0.08, 0.43), engine_grey, 0.045)
box("Engine_Head", (0.52, 0.46, 0.19), (-0.13, 0.08, 0.695), engine_grey, 0.03)
for i, z in enumerate((0.625, 0.675, 0.725, 0.775)):
    box(f"Cooling_Fin_{i}", (0.66, 0.57, 0.026), (-0.13, 0.08, z), bare_edge, 0.006)
for x in (-0.34, 0.08):
    cylinder(f"Head_Bolt_{x}", 0.024, 0.035, (x, -0.165, 0.75), bare_edge, 8,
             rotation=(deg(90), 0.0, 0.0))

# Alternator drum on the -X side with end plate, vents, and shaft boss.
cylinder("Alternator_Drum", 0.245, 0.40, (-0.51, 0.08, 0.43), body, 14,
         rotation=(0.0, deg(90), 0.0), bevel=0.018)
cylinder("Alternator_End", 0.225, 0.045, (-0.725, 0.08, 0.43), body_dark, 14,
         rotation=(0.0, deg(90), 0.0))
cylinder("Alternator_Boss", 0.075, 0.065, (-0.755, 0.08, 0.43), bare_edge, 12,
         rotation=(0.0, deg(90), 0.0))
for i, z in enumerate((0.31, 0.39, 0.47, 0.55)):
    box(f"Alternator_Vent_{i}", (0.018, 0.23, 0.032), (-0.750, 0.08, z), mat("black"), 0.005)

# Recoil pull-start on the front-left, including handle and a short hanging cord.
cylinder("Recoil_Housing", 0.205, 0.075, (-0.31, -0.245, 0.43), body_dark, 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Recoil_Hub", 0.065, 0.085, (-0.31, -0.287, 0.43), bare_edge, 12,
         rotation=(deg(90), 0.0, 0.0))
for i, angle in enumerate((0, 60, 120)):
    box(f"Recoil_Slot_{i}", (0.035, 0.014, 0.19), (-0.31, -0.329, 0.43), mat("black"), 0.005,
        rotation=(0.0, deg(angle), 0.0))
cylinder("Pull_Cord", 0.012, 0.20, (-0.49, -0.335, 0.35), mat("rubber"), 8,
         rotation=(0.0, deg(9), 0.0))
box("Pull_Handle", (0.16, 0.055, 0.055), (-0.52, -0.34, 0.245), mat("rubber"), 0.018,
    rotation=(0.0, deg(-8), 0.0))

# +X muffler can and exhaust stack, all kept below the cage top.
cylinder("Muffler", 0.145, 0.43, (0.48, 0.18, 0.66), bare, 12, bevel=0.014)
cylinder("Muffler_Lower_Clamp", 0.164, 0.045, (0.48, 0.18, 0.48), body_dark, 12)
cylinder("Muffler_Upper_Clamp", 0.164, 0.045, (0.48, 0.18, 0.84), body_dark, 12)
cylinder("Exhaust_Riser", 0.052, 0.22, (0.48, 0.18, 0.975), bare, 10)
cylinder("Sooty_Exhaust_Tip", 0.060, 0.10, (0.48, 0.18, 1.135), soot, 10)
box("Muffler_Bracket", (0.34, 0.065, 0.07), (0.46, 0.36, 0.67), bare_edge, 0.008)

# Front-facing control panel, outlets, breaker toggles and prominent kill switch.
box("Control_Panel", (0.58, 0.105, 0.32), (0.30, -0.435, 0.44), body_dark, 0.025)
box("Control_Face", (0.52, 0.025, 0.265), (0.30, -0.501, 0.44), bare, 0.012)
hazard_stripes("Control_Hazard", (0.30, -0.516, 0.545), 0.48, 0.055, 5, "-Y")
for i, x in enumerate((0.16, 0.31)):
    cylinder(f"Outlet_{i}", 0.057, 0.028, (x, -0.530, 0.405), mat("black"), 12,
             rotation=(deg(90), 0.0, 0.0))
    for j, dx in enumerate((-0.016, 0.016)):
        box(f"Outlet_Slot_{i}_{j}", (0.010, 0.012, 0.030), (x + dx, -0.547, 0.414), bare_edge, 0.002)
for i, x in enumerate((0.12, 0.22, 0.32)):
    box(f"Breaker_{i}", (0.045, 0.026, 0.075), (x, -0.532, 0.495), mat("black"), 0.006)
cylinder("Kill_Switch_Bezel", 0.075, 0.025, (0.47, -0.532, 0.445), mat("black"), 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Kill_Switch", 0.052, 0.050, (0.47, -0.565, 0.445), mat("red"), 14,
         rotation=(deg(90), 0.0, 0.0))

# Scavenged repair plates and exposed fasteners break up the clean primitives.
box("Tank_Repair_Plate", (0.25, 0.025, 0.13), (-0.10, -0.301, 0.985), bare_edge, 0.012,
    rotation=(0.0, 0.0, deg(-4)))
for x in (-0.19, -0.01):
    for z in (0.945, 1.025):
        cylinder(f"Tank_Repair_Bolt_{x}_{z}", 0.015, 0.025, (x, -0.321, z), bare, 8,
                 rotation=(deg(90), 0.0, 0.0))
box("Engine_Repair_Plate", (0.025, 0.24, 0.20), (0.195, 0.07, 0.43), body_dark, 0.009)
for y in (-0.01, 0.15):
    for z in (0.37, 0.49):
        cylinder(f"Engine_Repair_Bolt_{y}_{z}", 0.015, 0.028, (0.215, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))

# Status lamp at the -X end, safely separated from the exhaust.
box("Lamp_Mount", (0.24, 0.18, 0.045), (-0.54, -0.23, 1.175), body_dark, 0.012)
lamp((-0.54, -0.23, 1.197))

finish("generator", (1.6, 1.3, 1.2))
