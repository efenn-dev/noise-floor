"""Boxy 1990s delivery van for Noise Floor.

    blender.exe -b --factory-startup --python tools/art/van.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, part, reset  # noqa: E402

reset()

# Vehicle materials have exact names consumed by the game.  The painted body uses
# one material throughout; the remaining metal wear comes from the shared palette.
paint = material("Car Paint", (0.5, 0.5, 0.5), 0.34, 0.66)
glass = material("Car Glass", (0.018, 0.030, 0.040), 0.05, 0.10)
tyre = material("Tyre", (0.012, 0.014, 0.014), 0.0, 0.92)
chrome = material("Chrome", (0.42, 0.44, 0.43), 0.9, 0.35)
interior = material("Interior", (0.070, 0.075, 0.072), 0.0, 0.92)
headlight = material("Headlight", (0.88, 0.84, 0.64), 0.05, 0.28)
tail_light = material("Tail Light", (0.55, 0.018, 0.012), 0.05, 0.35)
black, rust, bare_edge = mat("black"), mat("rust"), mat("bare_edge")


def wheel(name: str, x: float, y: float) -> None:
    """Make a 16-sided wheel with its axle along X and pivot at its centre."""
    centre = (x, y, 0.36)
    pieces = [
        cylinder(f"{name}_Tyre", 0.36, 0.20, centre, tyre, 16,
                 rotation=(0.0, deg(90), 0.0), bevel=0.018),
        cylinder(f"{name}_Hub", 0.185, 0.214, centre, bare_edge, 16,
                 rotation=(0.0, deg(90), 0.0), bevel=0.012),
        cylinder(f"{name}_Cap", 0.080, 0.222, centre, chrome, 12,
                 rotation=(0.0, deg(90), 0.0), bevel=0.008),
    ]
    part(name, pieces, centre)


# Wheels: driver left is +X in Blender, front points -Y.
wheel("Wheel_FL", 0.84, -1.42)
wheel("Wheel_FR", -0.84, -1.42)
wheel("Wheel_RL", 0.84, 1.58)
wheel("Wheel_RR", -0.84, 1.58)

# Chassis and lower body.  The tiny central skid reaches Z=0 so finish() keeps
# wheel contact exactly on the collision-box floor.
box("Chassis", (1.60, 4.18, 0.18), (0.0, 0.05, 0.33), black, 0.035)
box("Floor_Skid", (0.70, 1.10, 0.06), (0.0, 0.40, 0.03), black, 0.012)
box("Front_Bumper", (1.90, 0.16, 0.19), (0.0, -2.35, 0.43), chrome, 0.035)
box("Rear_Bumper", (1.90, 0.16, 0.20), (0.0, 2.35, 0.45), chrome, 0.035)

# Chunky rocker panels leave the tyres readable rather than burying them in a
# single lower-body slab.  Short raised blocks suggest squared wheel arches.
box("Left_Sill", (0.12, 2.20, 0.20), (0.88, 0.08, 0.50), paint, 0.025)
box("Right_Sill", (0.12, 2.20, 0.20), (-0.88, 0.08, 0.50), paint, 0.025)
for side, x in (("L", 0.88), ("R", -0.88)):
    for axle, y in (("Front", -1.42), ("Rear", 1.58)):
        box(f"{side}_{axle}_Arch_Top", (0.13, 0.90, 0.12), (x, y, 0.78), paint, 0.025)
        box(f"{side}_{axle}_Arch_Front", (0.13, 0.16, 0.43),
            (x, y - 0.49, 0.585), paint, 0.025)
        box(f"{side}_{axle}_Arch_Rear", (0.13, 0.16, 0.43),
            (x, y + 0.49, 0.585), paint, 0.025)

# Tall, windowless cargo box.  It begins behind the cab and carries most of the
# silhouette; roof and corner rails keep the broad panels from looking toy-flat.
box("Cargo_Core", (1.72, 2.68, 1.34), (0.0, 0.93, 1.34), paint, 0.055)
box("Cargo_Roof", (1.82, 2.78, 0.13), (0.0, 0.91, 1.985), paint, 0.040)
for x in (-0.895, 0.895):
    box(f"Cargo_Roof_Rail_{x}", (0.075, 2.60, 0.085), (x, 0.94, 2.015), paint, 0.018)

# Cab lower shell, short hood and roof.  The cab is deliberately assembled
# around the glazing, so no opaque mass sits behind the windscreen.
box("Cab_Lower", (1.76, 1.43, 0.63), (0.0, -1.20, 0.98), paint, 0.045)
box("Hood", (1.68, 0.68, 0.34), (0.0, -1.98, 0.88), paint, 0.045,
    rotation=(deg(-3), 0.0, 0.0))
box("Hood_Centre_Ridge", (0.54, 0.61, 0.045), (0.0, -2.00, 1.065), paint, 0.014,
    rotation=(deg(-3), 0.0, 0.0))
box("Cab_Roof", (1.82, 1.48, 0.13), (0.0, -1.01, 1.965), paint, 0.040)

# Cab glazing.  The dashboard top is at 1.29 m, safely below the 1.55 m eye
# point; the four A-pillar pieces are exactly 0.06 m wide.
box("Windscreen", (1.58, 0.025, 0.55), (0.0, -1.655, 1.58), glass, 0.008,
    rotation=(deg(-7), 0.0, 0.0))
for x in (-0.82, 0.82):
    box(f"A_Pillar_{x}", (0.06, 0.075, 0.68), (x, -1.625, 1.59), paint, 0.014,
        rotation=(deg(-7), 0.0, 0.0))
    box(f"B_Pillar_{x}", (0.065, 0.11, 0.72), (x, -0.50, 1.58), paint, 0.014)
    box(f"Cab_Side_Window_{x}", (0.025, 0.91, 0.52), (x, -1.03, 1.59), glass, 0.008)

# Interior visible through the glass: low dashboard, two seats, steering wheel,
# centre tunnel, and a ribbed cargo floor continuing aft.
box("Dashboard", (1.54, 0.29, 0.22), (0.0, -1.50, 1.17), interior, 0.035)
box("Dash_Top", (1.48, 0.32, 0.055), (0.0, -1.46, 1.285), black, 0.015)
for side, x in (("Driver", 0.42), ("Passenger", -0.42)):
    box(f"{side}_Seat_Base", (0.43, 0.48, 0.18), (x, -0.83, 0.88), interior, 0.055)
    box(f"{side}_Seat_Back", (0.43, 0.16, 0.61), (x, -0.55, 1.17), interior, 0.055,
        rotation=(deg(-7), 0.0, 0.0))
    box(f"{side}_Headrest", (0.30, 0.14, 0.21), (x, -0.51, 1.52), interior, 0.045)
box("Centre_Tunnel", (0.23, 0.78, 0.18), (0.0, -0.91, 0.77), interior, 0.035)
cylinder("Steering_Wheel", 0.18, 0.045, (0.42, -1.30, 1.34), black, 16,
         rotation=(deg(72), 0.0, 0.0), bevel=0.012)
cylinder("Steering_Hub", 0.050, 0.070, (0.42, -1.28, 1.33), chrome, 12,
         rotation=(deg(72), 0.0, 0.0))
box("Cargo_Floor", (1.48, 2.62, 0.08), (0.0, 0.89, 0.72), interior, 0.018)
for x in (-0.56, -0.28, 0.0, 0.28, 0.56):
    box(f"Cargo_Floor_Rib_{x}", (0.035, 2.35, 0.025), (x, 0.95, 0.775), bare_edge, 0.006)

# Front face details: square 1990s grille, lamps, number plate and tow eyes.
box("Grille", (0.92, 0.035, 0.28), (0.0, -2.332, 0.72), black, 0.010)
for x in (-0.70, 0.70):
    box(f"Headlight_{x}", (0.34, 0.045, 0.20), (x, -2.35, 0.78), headlight, 0.025)
    box(f"Front_Indicator_Trim_{x}", (0.065, 0.035, 0.20),
        (x + (0.205 if x > 0 else -0.205), -2.344, 0.78), bare_edge, 0.008)
box("Front_Number_Plate", (0.48, 0.035, 0.12), (0.0, -2.402, 0.40), bare_edge, 0.010)
for x in (-0.56, 0.56):
    cylinder(f"Tow_Eye_{x}", 0.055, 0.035, (x, -2.435, 0.35), rust, 12,
             rotation=(deg(90), 0.0, 0.0), bevel=0.008)

# Sliding cargo door on -X, with its guide rail and recessed pull handle.
box("Sliding_Door", (0.035, 1.54, 1.18), (-0.882, 0.61, 1.32), paint, 0.025)
box("Sliding_Door_Rail", (0.045, 1.75, 0.055), (-0.920, 0.66, 1.82), bare_edge, 0.010)
box("Sliding_Door_Track_Low", (0.045, 1.55, 0.045), (-0.920, 0.61, 0.77), black, 0.008)
box("Sliding_Door_Handle", (0.045, 0.25, 0.085), (-0.928, -0.02, 1.47), black, 0.018)
for y in (-0.12, 1.34):
    for z in (0.83, 1.76):
        cylinder(f"Sliding_Door_Bolt_{y}_{z}", 0.023, 0.030, (-0.936, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))

# Twin rear doors and their small legal windows.  Seams, hinges and lights stay
# proud enough to read from gameplay distance.
box("Rear_Left_Door", (0.82, 0.035, 1.36), (0.43, 2.288, 1.32), paint, 0.025)
box("Rear_Right_Door", (0.82, 0.035, 1.36), (-0.43, 2.288, 1.32), paint, 0.025)
box("Rear_Centre_Seam", (0.035, 0.046, 1.34), (0.0, 2.314, 1.32), black, 0.006)
for x in (-0.43, 0.43):
    box(f"Rear_Window_{x}", (0.58, 0.025, 0.39), (x, 2.316, 1.62), glass, 0.012)
    box(f"Rear_Handle_{x}", (0.17, 0.035, 0.065),
        (x + (-0.14 if x < 0 else 0.14), 2.339, 1.20), black, 0.012)
    box(f"Tail_Light_{x}", (0.20, 0.045, 0.36), (x * 1.78, 2.357, 0.72), tail_light, 0.025)
for x in (-0.80, 0.80):
    for z in (0.92, 1.67):
        box(f"Rear_Hinge_{x}_{z}", (0.12, 0.055, 0.08), (x, 2.335, z), chrome, 0.012)

# Mirrors, repair plates and restrained low-body rust sell the scavenged state.
for x in (-0.96, 0.96):
    box(f"Mirror_Arm_{x}", (0.055, 0.25, 0.055), (x, -1.45, 1.55), black, 0.012,
        rotation=(deg(8), 0.0, 0.0))
    box(f"Mirror_{x}", (0.055, 0.18, 0.27), (x, -1.55, 1.60), chrome, 0.025)
box("Right_Repair_Plate", (0.035, 0.48, 0.30), (0.882, 0.40, 1.15), bare_edge, 0.018)
for y in (0.20, 0.60):
    for z in (1.04, 1.26):
        cylinder(f"Repair_Bolt_{y}_{z}", 0.022, 0.03, (0.908, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))
for side, x in (("L", 0.942), ("R", -0.942)):
    box(f"Rusty_Sill_{side}", (0.025, 1.67, 0.07), (x, 0.20, 0.435), rust, 0.010)
    box(f"Road_Dirt_{side}", (0.020, 0.72, 0.15), (x, 1.58, 0.66), black, 0.015)

finish("van", (2.0, 2.1, 4.9), max_triangles=6000)
