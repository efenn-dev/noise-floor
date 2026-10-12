"""Rain collector (rain -> stored water). Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/rain_collector.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, quad, reset  # noqa: E402

reset()
body, body_dark, bare, bare_edge = mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")
tote = material("Tote Plastic", (0.64, 0.66, 0.59), 0.02, 0.50)
tarp = material("Olive Tarp", (0.23, 0.27, 0.12), 0.05, 0.86)
water = material("Water", (0.055, 0.10, 0.075), 0.05, 0.10)

# Salvaged cinder-block skids and a heavy lower cage keep the tote off the mud.
for x in (-0.46, 0.46):
    box(f"Block_Skid_{x}", (0.30, 1.02, 0.14), (x, 0.0, 0.07), body_dark, 0.025)
    box(f"Block_Hollow_{x}", (0.13, 0.70, 0.07), (x, 0.0, 0.145), mat("black"), 0.015)
box("Cage_Base", (1.24, 1.00, 0.10), (0.0, 0.0, 0.20), bare, 0.022)

# Squared-off translucent-plastic IBC tank, deliberately chunky at gameplay scale.
box("IBC_Tote", (1.10, 0.84, 0.66), (0.0, 0.0, 0.57), tote, 0.075)
box("Tote_Top_Pad", (0.52, 0.42, 0.055), (0.0, 0.0, 0.922), tote, 0.018)
cylinder("Tote_Fill_Neck", 0.15, 0.065, (0.0, 0.0, 0.972), mat("rubber"), 14, bevel=0.008)

# Steel IBC cage: corner posts, top/bottom rails, and a readable square grid.
for xi, x in enumerate((-0.59, 0.59)):
    for yi, y in enumerate((-0.47, 0.47)):
        box(f"Cage_Post_{xi}_{yi}", (0.055, 0.055, 0.78), (x, y, 0.58), bare_edge, 0.009)

for z in (0.26, 0.50, 0.74, 0.94):
    box(f"Front_Rail_{z}", (1.22, 0.045, 0.045), (0.0, -0.47, z), bare, 0.007)
    box(f"Back_Rail_{z}", (1.22, 0.045, 0.045), (0.0, 0.47, z), bare, 0.007)
for x in (-0.30, 0.30):
    box(f"Front_Stave_{x}", (0.042, 0.048, 0.72), (x, -0.47, 0.59), bare, 0.007)
    box(f"Back_Stave_{x}", (0.042, 0.048, 0.72), (x, 0.47, 0.59), bare, 0.007)

for z in (0.26, 0.50, 0.74, 0.94):
    box(f"Left_Rail_{z}", (0.045, 0.94, 0.045), (-0.59, 0.0, z), bare, 0.007)
    box(f"Right_Rail_{z}", (0.045, 0.94, 0.045), (0.59, 0.0, z), bare, 0.007)
for y in (-0.235, 0.235):
    box(f"Left_Stave_{y}", (0.048, 0.042, 0.72), (-0.59, y, 0.59), bare, 0.007)
    box(f"Right_Stave_{y}", (0.048, 0.042, 0.72), (0.59, y, 0.59), bare, 0.007)

# Low tarp catch-basin: four sloping quads converge on the tank neck.
rim_x, rim_y, throat_x, throat_y = 0.72, 0.66, 0.17, 0.14
rim_z, throat_z = 1.18, 0.99
quad("Tarp_Front", [(-rim_x, -rim_y, rim_z), (rim_x, -rim_y, rim_z),
                    (throat_x, -throat_y, throat_z), (-throat_x, -throat_y, throat_z)], tarp)
quad("Tarp_Right", [(rim_x, -rim_y, rim_z), (rim_x, rim_y, rim_z),
                    (throat_x, throat_y, throat_z), (throat_x, -throat_y, throat_z)], tarp)
quad("Tarp_Back", [(rim_x, rim_y, rim_z), (-rim_x, rim_y, rim_z),
                   (-throat_x, throat_y, throat_z), (throat_x, throat_y, throat_z)], tarp)
quad("Tarp_Left", [(-rim_x, rim_y, rim_z), (-rim_x, -rim_y, rim_z),
                   (-throat_x, -throat_y, throat_z), (-throat_x, throat_y, throat_z)], tarp)

# Folded tarp edges give the thin basin a sturdy silhouette.
box("Tarp_Front_Hem", (1.49, 0.045, 0.045), (0.0, -0.675, 1.155), body_dark, 0.008)
box("Tarp_Back_Hem", (1.49, 0.045, 0.045), (0.0, 0.675, 1.155), body_dark, 0.008)
box("Tarp_Left_Hem", (0.045, 1.31, 0.045), (-0.745, 0.0, 1.155), body_dark, 0.008)
box("Tarp_Right_Hem", (0.045, 1.31, 0.045), (0.745, 0.0, 1.155), body_dark, 0.008)

# A shallow, dark water sheet remains visible inside the olive funnel.
box("Caught_Water", (0.78, 0.64, 0.018), (0.0, 0.0, 1.115), water, 0.025)

# Downpipe is offset toward the rear so the tote cap and funnel throat still read.
cylinder("Downpipe", 0.055, 0.31, (0.37, 0.30, 0.965), body_dark, 12, bevel=0.008)
cylinder("Downpipe_Collar", 0.078, 0.055, (0.37, 0.30, 0.825), bare_edge, 12, bevel=0.006)
box("Downpipe_Brace", (0.30, 0.045, 0.055), (0.47, 0.42, 0.88), bare_edge, 0.008,
    rotation=(0.0, deg(-18), 0.0))

# OUTPUT (front, -Y): orange valve housing, short spout, and a small catch tray.
cylinder("Output_Housing", 0.14, 0.12, (0.0, -0.515, 0.42), mat("output_orange"), 14,
         rotation=(deg(90), 0.0, 0.0), bevel=0.012)
cylinder("Tap_Neck", 0.060, 0.19, (0.0, -0.655, 0.42), bare_edge, 12,
         rotation=(deg(90), 0.0, 0.0), bevel=0.008)
cylinder("Tap_Downturn", 0.052, 0.16, (0.0, -0.745, 0.35), bare, 12, bevel=0.007)
cylinder("Tap_Handle_Stem", 0.035, 0.19, (0.0, -0.60, 0.55), bare, 10)
box("Tap_Handle", (0.30, 0.07, 0.055), (0.0, -0.60, 0.65), mat("output_orange"), 0.012)
box("Drip_Tray", (0.48, 0.24, 0.055), (0.0, -0.64, 0.22), body_dark, 0.012)
box("Tray_Back", (0.48, 0.045, 0.14), (0.0, -0.53, 0.285), body_dark, 0.01)
for x in (-0.205, 0.205):
    box(f"Tray_Rail_{x}", (0.055, 0.24, 0.09), (x, -0.64, 0.255), bare, 0.009)

# A compact warning patch and mismatched repair plate sell the scavenged build.
hazard_stripes("Drain_Hazard", (0.0, -0.498, 0.76), 0.42, 0.12, 4, "-Y")
box("Repair_Plate", (0.24, 0.025, 0.20), (0.38, -0.505, 0.61), body, 0.009,
    rotation=(0.0, 0.0, deg(-5)))
for x in (0.29, 0.47):
    for z in (0.54, 0.68):
        cylinder(f"Repair_Bolt_{x}_{z}", 0.018, 0.03, (x, -0.523, z), bare_edge, 8,
                 rotation=(deg(90), 0.0, 0.0))

# Back-corner beacon rises on its own bracket, clear of the broad funnel.
box("Lamp_Post", (0.055, 0.055, 0.21), (0.68, 0.59, 1.035), bare, 0.009)
box("Lamp_Bracket", (0.17, 0.12, 0.045), (0.65, 0.59, 1.13), bare_edge, 0.008)
lamp((0.65, 0.59, 1.155), radius=0.065)

finish("rain_collector", (1.6, 1.2, 1.6))
