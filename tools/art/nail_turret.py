"""Automated nail turret. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/nail_turret.py
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, mat, material, part, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
rubber, black = mat("rubber"), mat("black")
gun_metal = material("Gun Metal", (0.055, 0.075, 0.085), 0.85, 0.35)

# Weighted footprint, battered mounting pad, and exposed anchors.
box("Weighted_Base", (0.92, 0.82, 0.10), (0.0, 0.0, 0.05), body_dark, 0.025)
box("Base_Top_Plate", (0.68, 0.58, 0.075), (0.0, 0.0, 0.125), body, 0.018)
for xi, x in enumerate((-0.36, 0.36)):
    for yi, y in enumerate((-0.31, 0.31)):
        cylinder(f"Base_Anchor_{xi}_{yi}", 0.037, 0.035, (x, y, 0.115), bare_edge, 10)

# A welded three-leg stand: central mast, front splayed legs, and a rear kick brace.
cylinder("Mast_Foot", 0.18, 0.10, (0.0, 0.0, 0.205), bare, 12)
cylinder("Main_Mast", 0.095, 0.76, (0.0, 0.0, 0.61), body_dark, 12)
cylinder("Mast_Wear_Collar", 0.128, 0.09, (0.0, 0.0, 0.37), bare_edge, 12)
cylinder("Head_Bearing_Base", 0.155, 0.09, (0.0, 0.0, 1.01), bare, 14, bevel=0.009)

for side, x in (("L", -0.255), ("R", 0.255)):
    box(f"Front_Leg_{side}", (0.105, 0.13, 0.63), (x, -0.19, 0.42), bare, 0.014,
        rotation=(0.0, deg(-22 if x < 0 else 22), 0.0))
    box(f"Front_Leg_Foot_{side}", (0.28, 0.22, 0.065), (x * 1.33, -0.29, 0.18), body_dark, 0.014)
box("Rear_Kick_Brace", (0.13, 0.64, 0.11), (0.0, 0.16, 0.40), bare, 0.014,
    rotation=(deg(-31), 0.0, 0.0))
box("Rear_Brace_Foot", (0.28, 0.22, 0.065), (0.0, 0.30, 0.18), body_dark, 0.014)

# Side hopper and its clamp bands. It is deliberately offset to counter the control box.
box("Ammo_Hopper", (0.32, 0.34, 0.40), (0.275, 0.16, 0.53), body, 0.025)
box("Ammo_Hopper_Lid", (0.35, 0.37, 0.065), (0.275, 0.16, 0.755), body_dark, 0.014)
box("Ammo_Hopper_Chute", (0.17, 0.20, 0.15), (0.20, 0.03, 0.77), bare, 0.016,
    rotation=(deg(-12), 0.0, 0.0))
for z in (0.42, 0.66):
    box(f"Hopper_Clamp_{z}", (0.345, 0.365, 0.035), (0.275, 0.16, z), bare_edge, 0.007)
for x in (0.155, 0.395):
    cylinder(f"Hopper_Lid_Bolt_{x}", 0.022, 0.032, (x, -0.035, 0.755), bare_edge, 8,
             rotation=(deg(90), 0.0, 0.0))

# Segmented rubber feed hose climbs toward the rotating head.
cylinder("Feed_Hose_Lower", 0.047, 0.31, (0.34, 0.02, 0.90), rubber, 12)
cylinder("Feed_Hose_Upper", 0.047, 0.25, (0.22, 0.02, 1.045), rubber, 12,
         rotation=(0.0, deg(78), 0.0))
cylinder("Feed_Hose_Lower_Clamp", 0.061, 0.045, (0.34, 0.02, 0.79), bare_edge, 12)
cylinder("Feed_Hose_Upper_Clamp", 0.061, 0.045, (0.105, 0.02, 1.07), bare_edge, 12,
         rotation=(0.0, deg(78), 0.0))

# Scavenged control box, stop button, conduit, and dangling power cable.
box("Control_Box", (0.28, 0.22, 0.31), (-0.285, 0.15, 0.57), body_dark, 0.023)
box("Control_Face", (0.23, 0.025, 0.245), (-0.285, 0.027, 0.57), bare, 0.008)
cylinder("Stop_Button_Bezel", 0.052, 0.025, (-0.285, 0.008, 0.62), black, 12,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Stop_Button", 0.036, 0.036, (-0.285, -0.014, 0.62), mat("red"), 12,
         rotation=(deg(90), 0.0, 0.0))
for x in (-0.355, -0.215):
    for z in (0.49, 0.69):
        cylinder(f"Control_Face_Bolt_{x}_{z}", 0.013, 0.029, (x, 0.005, z), bare_edge, 8,
                 rotation=(deg(90), 0.0, 0.0))
cylinder("Power_Cable_Drop", 0.032, 0.33, (-0.40, 0.20, 0.30), rubber, 10)
cylinder("Power_Cable_Floor", 0.032, 0.35, (-0.24, 0.20, 0.15), rubber, 10,
         rotation=(0.0, deg(90), 0.0))
cylinder("Cable_Gland", 0.050, 0.055, (-0.40, 0.20, 0.455), bare, 12)

# Visible field repairs and weld-like gussets keep the base appropriately scavenged.
box("Mast_Repair_Plate", (0.035, 0.18, 0.23), (-0.102, -0.01, 0.75), bare_edge, 0.008)
for z in (0.68, 0.82):
    cylinder(f"Mast_Repair_Bolt_{z}", 0.017, 0.040, (-0.125, -0.01, z), bare_edge, 8,
             rotation=(0.0, deg(90), 0.0))
for x in (-0.13, 0.13):
    box(f"Mast_Gusset_{x}", (0.09, 0.28, 0.10), (x, 0.0, 0.27), body_dark, 0.012)

# Everything created from this point belongs to the separately rotating head.
head_start = set(bpy.context.scene.objects)
pivot = (0.0, 0.0, 1.075)

cylinder("Head_Turntable", 0.17, 0.11, (0.0, 0.0, 1.09), gun_metal, 14, bevel=0.010)
box("Gun_Receiver", (0.58, 0.40, 0.27), (0.0, -0.015, 1.235), gun_metal, 0.027)
box("Receiver_Top", (0.42, 0.30, 0.075), (-0.045, 0.0, 1.405), body_dark, 0.014)
box("Receiver_Nose_Block", (0.34, 0.14, 0.22), (0.0, -0.25, 1.22), bare, 0.018)

# Nail barrel faces -Y and ends just inside the collision footprint.
cylinder("Barrel_Shroud", 0.078, 0.30, (0.0, -0.310, 1.25), gun_metal, 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Muzzle_Collar", 0.105, 0.075, (0.0, -0.415, 1.25), bare_edge, 14,
         rotation=(deg(90), 0.0, 0.0), bevel=0.008)
cylinder("Muzzle_Bore", 0.047, 0.080, (0.0, -0.420, 1.25), black, 14,
         rotation=(deg(90), 0.0, 0.0))

# Rear pneumatic cylinder provides a clear industrial silhouette and balances the barrel.
cylinder("Pneumatic_Cylinder", 0.105, 0.34, (0.16, 0.21, 1.33), body, 14,
         rotation=(deg(90), 0.0, 0.0), bevel=0.010)
cylinder("Pneumatic_Front_Cap", 0.128, 0.055, (0.16, 0.055, 1.33), bare, 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Pneumatic_Rear_Cap", 0.128, 0.055, (0.16, 0.365, 1.33), bare, 14,
         rotation=(deg(90), 0.0, 0.0))
cylinder("Air_Hose", 0.032, 0.24, (-0.06, 0.29, 1.36), rubber, 10,
         rotation=(0.0, deg(90), 0.0))

# Long nail strip hangs beneath one side of the receiver.
box("Nail_Magazine", (0.15, 0.57, 0.11), (-0.225, 0.045, 1.075), body_dark, 0.015)
box("Magazine_Rail", (0.19, 0.54, 0.035), (-0.225, 0.045, 1.025), bare_edge, 0.006)
for i, y in enumerate((-0.17, -0.10, -0.03, 0.04, 0.11, 0.18, 0.25)):
    cylinder(f"Visible_Nail_{i}", 0.012, 0.12, (-0.307, y, 1.08), bare_edge, 8,
             rotation=(0.0, deg(90), 0.0))

# Hazard warning, a bolted repair patch, and sight-like top rails read from the front.
hazard_stripes("Head_Hazard", (0.13, -0.222, 1.34), 0.24, 0.085, 4, "-Y")
box("Head_Repair_Plate", (0.035, 0.19, 0.16), (0.307, -0.01, 1.22), bare_edge, 0.008)
for y in (-0.07, 0.05):
    for z in (1.18, 1.26):
        cylinder(f"Head_Repair_Bolt_{y}_{z}", 0.014, 0.040, (0.33, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))
for x in (-0.12, 0.03):
    box(f"Top_Rail_{x}", (0.055, 0.27, 0.045), (x, -0.02, 1.465), bare_edge, 0.007)

head_objects = [obj for obj in bpy.context.scene.objects if obj not in head_start and obj.type == "MESH"]
part("Head", head_objects, pivot)

finish("nail_turret", (1.0, 1.4, 1.0))
