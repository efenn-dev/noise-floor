"""Abandoned 1990s sedan. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/car.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()

# The body paint is intentionally neutral: the game tints this one material per car.
paint = material("Car Paint", (0.5, 0.5, 0.5), 0.28, 0.72)
glass = material("Car Glass", (0.025, 0.045, 0.055), 0.0, 0.15)
tyre = material("Tyre", (0.012, 0.014, 0.014), 0.0, 0.92)
chrome = material("Chrome", (0.31, 0.33, 0.33), 0.9, 0.35)
rust, black = mat("rust"), mat("black")

# Lower unibody, doors, hood, trunk and chunky fenders.  The front is -Y.
box("Floor_Pan", (1.58, 3.56, 0.18), (0.0, 0.02, 0.34), black, 0.045)
box("Lower_Body", (1.66, 3.58, 0.44), (0.0, 0.00, 0.55), paint, 0.075)
box("Front_Valance", (1.60, 0.50, 0.35), (0.0, -1.72, 0.53), paint, 0.055)
box("Rear_Valance", (1.60, 0.49, 0.36), (0.0, 1.70, 0.55), paint, 0.055)

# Broad, low 1990s hood and slightly high trunk lid.
box("Hood", (1.52, 1.05, 0.18), (0.03, -1.35, 0.79), paint, 0.045, rotation=(deg(-2), 0.0, 0.0))
box("Hood_Crumple_Left", (0.53, 0.45, 0.17), (-0.49, -1.77, 0.75), paint, 0.035,
    rotation=(deg(-5), deg(-4), deg(-7)))
box("Hood_Crumple_Seam", (0.035, 0.42, 0.025), (-0.23, -1.67, 0.845), rust, 0.007,
    rotation=(0.0, deg(-5), deg(-7)))
box("Trunk_Deck", (1.51, 0.85, 0.18), (0.0, 1.38, 0.80), paint, 0.045,
    rotation=(deg(2), 0.0, 0.0))
box("Trunk_Lid_Seam", (1.24, 0.035, 0.025), (0.0, 1.02, 0.875), black, 0.006)

# Wheel-arch brows keep the profile chunky while the tyres remain clearly exposed.
for side, x in (("L", -0.72), ("R", 0.72)):
    for axle, y in (("Front", -1.28), ("Rear", 1.27)):
        box(f"{side}_{axle}_Arch_Brow", (0.20, 0.93, 0.24), (x, y, 0.69), paint, 0.055)

# Cabin: solid roof and pillars frame dark inset glazing. Sloped front/rear glass
# is especially legible from street-level first-person views.
box("Cabin_Roof", (1.43, 1.12, 0.15), (0.0, 0.10, 1.34), paint, 0.045)
for side, x in (("L", -0.69), ("R", 0.69)):
    box(f"{side}_A_Pillar", (0.105, 0.16, 0.61), (x, -0.67, 1.06), paint, 0.022,
        rotation=(deg(-27), 0.0, 0.0))
    box(f"{side}_B_Pillar", (0.105, 0.13, 0.57), (x, 0.12, 1.06), paint, 0.02)
    box(f"{side}_C_Pillar", (0.13, 0.18, 0.58), (x, 0.72, 1.05), paint, 0.022,
        rotation=(deg(25), 0.0, 0.0))

box("Windscreen", (1.30, 0.035, 0.54), (0.0, -0.66, 1.06), glass, 0.018,
    rotation=(deg(-28), 0.0, 0.0))
box("Rear_Window", (1.28, 0.035, 0.50), (0.0, 0.72, 1.06), glass, 0.018,
    rotation=(deg(27), 0.0, 0.0))

# Side glass and door skins. The right rear pane is broken out; the black interior
# and two surviving shards make the empty aperture read at medium distance.
for side, x, outward in (("L", -0.748, -1), ("R", 0.748, 1)):
    box(f"{side}_Front_Door", (0.035, 0.76, 0.39), (x, -0.27, 0.72), paint, 0.012)
    box(f"{side}_Rear_Door", (0.035, 0.69, 0.39), (x, 0.55, 0.72), paint, 0.012)
    box(f"{side}_Front_Window", (0.026, 0.62, 0.37), (x + outward * 0.006, -0.27, 1.08), glass, 0.009)
    if side == "L":
        box("L_Rear_Window", (0.026, 0.52, 0.37), (x - 0.006, 0.52, 1.08), glass, 0.009)
    else:
        box("Broken_Window_Dark_Interior", (0.022, 0.49, 0.32), (0.714, 0.52, 1.06), black, 0.006)
        box("Broken_Glass_Lower_Shard", (0.018, 0.20, 0.06), (0.762, 0.38, 0.91), glass, 0.004,
            rotation=(deg(9), 0.0, 0.0))
        box("Broken_Glass_Rear_Shard", (0.018, 0.07, 0.23), (0.762, 0.74, 1.02), glass, 0.004,
            rotation=(deg(-13), 0.0, 0.0))
    # Dull handles sit above the door crease.
    box(f"{side}_Front_Handle", (0.035, 0.18, 0.035), (x + outward * 0.025, -0.12, 0.91), chrome, 0.009)
    box(f"{side}_Rear_Handle", (0.035, 0.18, 0.035), (x + outward * 0.025, 0.69, 0.91), chrome, 0.009)

# Four 12-sided wheels along X. The right-rear tyre is deflated and rides low.
wheel_data = (
    ("LF", -0.77, -1.28, 0.43, False),
    ("RF", 0.77, -1.28, 0.43, False),
    ("LR", -0.77, 1.27, 0.43, False),
    ("RR_Flat", 0.77, 1.27, 0.35, True),
)
for name, x, y, z, flat in wheel_data:
    wheel = cylinder(f"{name}_Tyre", 0.35, 0.27, (x, y, z), tyre, 12,
                     rotation=(0.0, deg(90), 0.0), bevel=0.035)
    if flat:
        wheel.scale.x = 0.72  # local X maps to world Z after the 90-degree rotation
    cylinder(f"{name}_Hub", 0.165, 0.288, (x, y, z), chrome, 12,
             rotation=(0.0, deg(90), 0.0), bevel=0.018)
    cylinder(f"{name}_Hub_Cap", 0.060, 0.303, (x, y, z), black, 10,
             rotation=(0.0, deg(90), 0.0), bevel=0.01)

# Bumpers, with the left-front corner crushed and the right end hanging down.
box("Front_Bumper_Main", (1.20, 0.16, 0.17), (-0.08, -2.04, 0.43), chrome, 0.035)
box("Front_Bumper_Crushed_End", (0.34, 0.16, 0.16), (-0.67, -2.00, 0.39), chrome, 0.025,
    rotation=(deg(-5), deg(-10), deg(-8)))
box("Front_Bumper_Hanging_End", (0.34, 0.15, 0.16), (0.67, -2.00, 0.34), chrome, 0.025,
    rotation=(deg(7), deg(13), deg(4)))
box("Rear_Bumper", (1.57, 0.16, 0.17), (0.0, 2.03, 0.45), chrome, 0.035)

# Lamps are small flat boxes rather than functional machine lamps.
for x in (-0.49, 0.49):
    box(f"Headlight_{x}", (0.37, 0.035, 0.16), (x, -2.045, 0.67), chrome, 0.018)
    box(f"Tail_Light_{x}", (0.34, 0.035, 0.17), (x, 1.958, 0.69), mat("red"), 0.018)

# Dirt, sill rust and scavenged repair plates provide large readable wear marks.
for side, x, outward in (("L", -0.842, -1), ("R", 0.842, 1)):
    box(f"{side}_Dirty_Sill", (0.022, 1.62, 0.13), (x, 0.03, 0.41), black, 0.007)
    box(f"{side}_Rust_Sill_Front", (0.026, 0.52, 0.08), (x + outward * 0.003, -0.70, 0.47), rust, 0.006,
        rotation=(deg(2), 0.0, 0.0))
    box(f"{side}_Rust_Sill_Rear", (0.026, 0.42, 0.10), (x + outward * 0.003, 0.72, 0.46), rust, 0.006,
        rotation=(deg(-3), 0.0, 0.0))

box("Left_Quarter_Repair_Plate", (0.025, 0.42, 0.24), (-0.844, 1.51, 0.68), chrome, 0.014)
for y in (1.35, 1.67):
    for z in (0.59, 0.77):
        cylinder(f"Repair_Bolt_{y}_{z}", 0.022, 0.035, (-0.866, y, z), black, 8,
                 rotation=(0.0, deg(90), 0.0), bevel=0.004)
box("Trunk_Rust_Patch", (0.43, 0.025, 0.10), (-0.41, 1.817, 0.61), rust, 0.008,
    rotation=(0.0, 0.0, deg(-6)))

finish("car", (1.9, 1.5, 4.4))
