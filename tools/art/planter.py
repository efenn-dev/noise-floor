"""Scavenged raised crop planter. Written by Codex for Noise Floor.

    blender.exe -b --factory-startup --python tools/art/planter.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
wood = material("Weathered Wood", (0.24, 0.19, 0.14), 0.05, 0.92)
soil = material("Soil", (0.055, 0.028, 0.015), 0.0, 0.98)
leaf = material("Leaf Green", (0.16, 0.31, 0.11), 0.0, 0.70)

# Cut-down steel tub: a shallow base pan, rolled rim, and reinforcing straps.
box("Tub_Bottom", (1.60, 1.48, 0.075), (0.0, 0.0, 0.0575), body_dark, 0.025)
box("Tub_Underframe_X", (1.70, 0.13, 0.11), (0.0, 0.0, 0.09), bare, 0.018)
box("Tub_Underframe_Y", (0.13, 1.58, 0.11), (0.0, 0.0, 0.09), bare, 0.018)
for x in (-0.73, 0.73):
    for y in (-0.65, 0.65):
        box(f"Block_Foot_{x}_{y}", (0.16, 0.16, 0.10), (x, y, 0.05), body_dark, 0.022)
        cylinder(f"Foot_Bolt_{x}_{y}", 0.026, 0.025, (x, y, 0.1125), bare_edge, 8)

# Scavenged pallet boards form the raised sides. Their slight misalignment keeps the silhouette handmade.
for i, z in enumerate((0.17, 0.285)):
    box(f"Left_Pallet_Plank_{i}", (0.10, 1.52, 0.10), (-0.78, 0.0, z), wood,
        rotation=(0.0, 0.0, deg(0.7 if i == 0 else -0.5)))
    box(f"Right_Pallet_Plank_{i}", (0.10, 1.52, 0.10), (0.78, 0.0, z), wood,
        rotation=(0.0, 0.0, deg(-0.5 if i == 0 else 0.6)))

    # Front and back boards are split around the harvest tray and water connection.
    for side, x in (("L", -0.49), ("R", 0.49)):
        box(f"Front_Pallet_Plank_{i}_{side}", (0.64, 0.10, 0.10), (x, -0.76, z), wood)
        box(f"Back_Pallet_Plank_{i}_{side}", (0.64, 0.10, 0.10), (x, 0.76, z), wood)

# Steel straps and a mismatched rolled rim sell the repurposed drum/tub construction.
for i, x in enumerate((-0.72, 0.0, 0.72)):
    box(f"Front_Drum_Strap_{i}", (0.075, 0.125, 0.31), (x, -0.775, 0.235), body)
    box(f"Back_Drum_Strap_{i}", (0.075, 0.125, 0.31), (x, 0.775, 0.235), body)
for i, y in enumerate((-0.56, 0.0, 0.56)):
    box(f"Left_Drum_Strap_{i}", (0.125, 0.075, 0.31), (-0.795, y, 0.235), body)
    box(f"Right_Drum_Strap_{i}", (0.125, 0.075, 0.31), (0.795, y, 0.235), body)

box("Front_Rim", (1.66, 0.105, 0.075), (0.0, -0.775, 0.365), bare_edge, 0.025)
box("Back_Rim", (1.66, 0.105, 0.075), (0.0, 0.775, 0.365), bare_edge, 0.025)
box("Left_Rim", (0.105, 1.46, 0.075), (-0.795, 0.0, 0.365), bare_edge, 0.025)
box("Right_Rim", (0.105, 1.46, 0.075), (0.795, 0.0, 0.365), bare_edge, 0.025)

# Soil sits just under the rim so the broad dark surface reads clearly from player height.
box("Packed_Soil", (1.43, 1.31, 0.12), (0.0, 0.0, 0.37), soil, 0.035)
for y in (-0.43, 0.0, 0.43):
    box(f"Soil_Row_{y}", (1.25, 0.18, 0.035), (0.0, y, 0.442), soil)

# Black drip irrigation: two supply runs with short emitters at every crop clump.
for x in (-0.47, 0.0, 0.47):
    cylinder(f"Drip_Line_{x}", 0.017, 1.26, (x, 0.0, 0.451), mat("rubber"), 8,
             rotation=(deg(90), 0.0, 0.0))
for x in (-0.47, 0.0, 0.47):
    for y in (-0.43, 0.0, 0.43):
        cylinder(f"Drip_Emitter_{x}_{y}", 0.027, 0.028, (x, y, 0.467), mat("rubber"), 8)

# Nine chunky crop clumps. Four splayed, bevelled leaves give each plant a readable star silhouette.
for row, y in enumerate((-0.43, 0.0, 0.43)):
    for col, x in enumerate((-0.47, 0.0, 0.47)):
        cylinder(f"Crop_Stem_{row}_{col}", 0.030, 0.105, (x, y, 0.493), leaf, 7, bevel=0.008)
        angles = (15.0, 105.0, 195.0, 285.0)
        for n, angle in enumerate(angles):
            # Alternating lean gives the deterministic rows a less factory-perfect rhythm.
            lean = 18.0 if (row + col + n) % 2 == 0 else -18.0
            box(f"Crop_Leaf_{row}_{col}_{n}", (0.055, 0.205, 0.035),
                (x, y, 0.527 + (n % 2) * 0.006), leaf,
                rotation=(deg(lean), 0.0, deg(angle)))

# INPUT (back, +Y): a bright blue water valve and pipe stub feeding the drip manifold.
cylinder("Water_Inlet_Pipe", 0.060, 0.20, (0.0, 0.795, 0.315), mat("input_blue"), 12,
         rotation=(deg(90), 0.0, 0.0), bevel=0.008)
cylinder("Water_Inlet_Collar", 0.092, 0.055, (0.0, 0.852, 0.315), mat("input_blue"), 12,
         rotation=(deg(90), 0.0, 0.0), bevel=0.008)
cylinder("Water_Valve_Wheel", 0.115, 0.035, (0.0, 0.875, 0.405), mat("input_blue"), 10,
         rotation=(deg(90), 0.0, 0.0), bevel=0.006)
box("Water_Manifold", (1.02, 0.045, 0.045), (0.0, 0.655, 0.455), mat("rubber"), 0.012)

# OUTPUT (front, -Y): an orange harvest tray with steel side rails and a catch lip.
tray_tilt = (deg(-7), 0.0, 0.0)
box("Harvest_Tray", (0.72, 0.25, 0.055), (0.0, -0.765, 0.235), mat("output_orange"), 0.014,
    rotation=tray_tilt)
box("Harvest_Tray_Lip", (0.76, 0.065, 0.10), (0.0, -0.865, 0.205), mat("output_orange"), 0.014)
for x in (-0.385, 0.385):
    box(f"Harvest_Tray_Rail_{x}", (0.055, 0.25, 0.115), (x, -0.765, 0.265), body_dark, 0.012,
        rotation=tray_tilt)

# A small front warning plate and a bolted side repair patch add scavenged-machine detail.
hazard_stripes("Front_Hazard", (-0.52, -0.839, 0.295), 0.31, 0.085, 4, "-Y")
box("Side_Repair_Plate", (0.025, 0.34, 0.17), (0.858, 0.18, 0.245), body_dark, 0.01)
for y in (0.06, 0.30):
    for z in (0.205, 0.285):
        cylinder(f"Repair_Bolt_{y}_{z}", 0.018, 0.030, (0.877, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))

# Status lamp on a short back-corner post, clear of the crop canopy.
box("Lamp_Post", (0.075, 0.075, 0.16), (0.70, 0.65, 0.48), body_dark, 0.012)
box("Lamp_Post_Bracket", (0.16, 0.16, 0.04), (0.70, 0.65, 0.405), bare, 0.012)
lamp((0.70, 0.65, 0.56), radius=0.065)

finish("planter", (1.8, 0.6, 1.8))
