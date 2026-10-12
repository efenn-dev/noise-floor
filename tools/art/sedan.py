"""Worn 1990s family sedan for Noise Floor. Written by Codex, built on kit.py.

    blender.exe -b --factory-startup --python tools/art/sedan.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, part, reset  # noqa: E402

reset()

# Vehicle materials are named contracts with the game.  Shared palette metals provide the wear.
paint = material("Car Paint", (0.5, 0.5, 0.5), 0.32, 0.64)
glass = material("Car Glass", (0.025, 0.045, 0.055), 0.05, 0.10)
tyre = material("Tyre", (0.012, 0.014, 0.014), 0.0, 0.92)
chrome = material("Chrome", (0.38, 0.40, 0.40), 0.90, 0.35)
interior = material("Interior", (0.075, 0.078, 0.075), 0.0, 0.88)
headlight = material("Headlight", (0.88, 0.82, 0.58), 0.05, 0.28)
tail_light = material("Tail Light", (0.55, 0.018, 0.012), 0.08, 0.38)
black, rust, bare_edge = mat("black"), mat("rust"), mat("bare_edge")


def wheel(name: str, x: float, y: float) -> None:
    """A separate 16-sided wheel, axle along X and pivot exactly at its centre."""
    z = 0.33
    pieces = [
        cylinder(f"{name}_Tyre", 0.33, 0.235, (x, y, z), tyre, 16,
                 rotation=(0.0, deg(90), 0.0), bevel=0.035),
        cylinder(f"{name}_HubOuter", 0.175, 0.249, (x, y, z), bare_edge, 16,
                 rotation=(0.0, deg(90), 0.0)),
        cylinder(f"{name}_HubCap", 0.084, 0.263, (x, y, z), chrome, 12,
                 rotation=(0.0, deg(90), 0.0)),
    ]
    # Broad tread pads keep the tyre readable at medium distance without making it high-poly.
    for i in range(12):
        angle = i * 30.0
        a = deg(angle)
        pieces.append(box(
            f"{name}_Tread_{i}", (0.245, 0.080, 0.045),
            (x, y + 0.306 * __import__("math").sin(a), z + 0.306 * __import__("math").cos(a)),
            tyre, rotation=(a, 0.0, 0.0)))
    part(name, pieces, (x, y, z))


# Wheels establish the stance: front is -Y and driver's left is +X.
for wheel_name, wx, wy in (
    ("Wheel_FL", 0.775, -1.325),
    ("Wheel_FR", -0.775, -1.325),
    ("Wheel_RL", 0.775, 1.325),
    ("Wheel_RR", -0.775, 1.325),
):
    wheel(wheel_name, wx, wy)

# Lower shell, sills, bumpers, and the long conservative three-box sedan profile.
box("Floorpan", (1.62, 3.52, 0.18), (0.0, 0.02, 0.27), black, 0.045)
box("Lower_Body", (1.72, 3.63, 0.43), (0.0, 0.00, 0.49), paint, 0.09)
box("Front_Valance", (1.66, 0.36, 0.30), (0.0, -1.91, 0.47), paint, 0.065)
box("Front_Bumper", (1.77, 0.18, 0.17), (0.0, -2.105, 0.43), black, 0.045)
box("Front_Bumper_Trim", (1.55, 0.035, 0.040), (0.0, -2.175, 0.45), chrome, 0.006)
box("Rear_Valance", (1.68, 0.38, 0.32), (0.0, 1.91, 0.49), paint, 0.065)
box("Rear_Bumper", (1.77, 0.18, 0.17), (0.0, 2.105, 0.43), black, 0.045)
box("Rear_Bumper_Trim", (1.55, 0.035, 0.040), (0.0, 2.175, 0.45), chrome, 0.006)

# Hood and boot are deliberately broad and square, with stepped edges typical of a 1990s sedan.
box("Hood", (1.59, 1.18, 0.16), (0.0, -1.34, 0.78), paint, 0.055,
    rotation=(deg(-2.0), 0.0, 0.0))
box("Hood_Centre_Ridge", (0.82, 0.88, 0.035), (0.0, -1.34, 0.875), paint, 0.012)
box("Boot_Lid", (1.57, 0.86, 0.17), (0.0, 1.56, 0.77), paint, 0.05,
    rotation=(deg(1.5), 0.0, 0.0))
box("Boot_Lip", (1.52, 0.085, 0.075), (0.0, 1.97, 0.82), paint, 0.018)

# Cabin frame. Thin pillars leave an uninterrupted driving view above the low dashboard.
box("Roof", (1.50, 1.78, 0.115), (0.0, 0.34, 1.405), paint, 0.045)
for x in (-0.715, 0.715):
    box(f"A_Pillar_{x}", (0.065, 0.105, 0.59), (x, -0.535, 1.105), paint, 0.018,
        rotation=(deg(-31), 0.0, 0.0))
    box(f"B_Pillar_{x}", (0.065, 0.095, 0.61), (x, 0.37, 1.105), paint, 0.016)
    box(f"C_Pillar_{x}", (0.065, 0.13, 0.57), (x, 1.13, 1.085), paint, 0.018,
        rotation=(deg(30), 0.0, 0.0))
    box(f"Roof_Rail_{x}", (0.075, 1.83, 0.075), (x, 0.34, 1.355), paint, 0.018)

# Intact windscreens and side glazing, each a thin slab in the required Car Glass material.
box("Windscreen", (1.35, 0.026, 0.55), (0.0, -0.535, 1.105), glass, 0.012,
    rotation=(deg(-31), 0.0, 0.0))
box("Rear_Window", (1.34, 0.026, 0.49), (0.0, 1.105, 1.105), glass, 0.012,
    rotation=(deg(30), 0.0, 0.0))
for x in (-0.746, 0.746):
    side = "L" if x > 0 else "R"
    box(f"Front_Side_Window_{side}", (0.025, 0.69, 0.43), (x, -0.075, 1.105), glass, 0.010)
    box(f"Rear_Side_Window_{side}", (0.025, 0.60, 0.43), (x, 0.785, 1.105), glass, 0.010)

# Four doors with dark seam strips, handles, and restrained protective side moulding.
for x in (-0.866, 0.866):
    side = "L" if x > 0 else "R"
    for label, y, length in (("Front", -0.12, 0.78), ("Rear", 0.78, 0.75)):
        box(f"{label}_Door_{side}", (0.055, length, 0.51), (x, y, 0.735), paint, 0.015)
        box(f"{label}_Door_Moulding_{side}", (0.068, length * 0.82, 0.055),
            (x + (0.007 if x > 0 else -0.007), y, 0.58), black, 0.009)
        box(f"{label}_Handle_{side}", (0.075, 0.145, 0.038),
            (x + (0.035 if x > 0 else -0.035), y - 0.20, 0.91), chrome, 0.009)
    for seam_y in (-0.56, 0.34, 1.20):
        box(f"Door_Seam_{side}_{seam_y}", (0.067, 0.018, 0.50), (x, seam_y, 0.75), black, 0.003)

# Mirrors remain compact and within the 1.9 m collision width.
for x in (-0.875, 0.875):
    side = "L" if x > 0 else "R"
    box(f"Mirror_Stem_{side}", (0.085, 0.07, 0.055), (x, -0.49, 1.03), black, 0.012)
    box(f"Mirror_{side}", (0.095, 0.18, 0.12), (x, -0.55, 1.07), paint, 0.025)

# Simple visible interior. Dashboard top is 0.92 m, safely below eye Z 1.15 - 0.2.
box("Dashboard", (1.39, 0.34, 0.18), (0.0, -0.61, 0.82), interior, 0.045)
box("Dashboard_Top", (1.42, 0.31, 0.055), (0.0, -0.60, 0.91), black, 0.018)
box("Centre_Console", (0.25, 0.72, 0.22), (0.0, -0.06, 0.47), interior, 0.035)
for label, x in (("Driver", 0.38), ("Passenger", -0.38)):
    box(f"{label}_Seat_Cushion", (0.48, 0.55, 0.18), (x, 0.16, 0.54), interior, 0.065)
    box(f"{label}_Seat_Back", (0.48, 0.18, 0.58), (x, 0.40, 0.82), interior, 0.065,
        rotation=(deg(-7), 0.0, 0.0))
    cylinder(f"{label}_Headrest", 0.13, 0.32, (x, 0.45, 1.16), interior, 12,
             rotation=(0.0, deg(90), 0.0), bevel=0.015)
box("Rear_Seat_Cushion", (1.25, 0.50, 0.18), (0.0, 0.92, 0.54), interior, 0.065)
box("Rear_Seat_Back", (1.25, 0.18, 0.52), (0.0, 1.15, 0.79), interior, 0.065,
    rotation=(deg(-8), 0.0, 0.0))

# Right-hand driver controls (driver's left is +X in Blender per the vehicle convention).
cylinder("Steering_Column", 0.035, 0.34, (0.38, -0.43, 0.84), black, 12,
         rotation=(deg(68), 0.0, 0.0))
cylinder("Steering_Wheel", 0.17, 0.045, (0.38, -0.53, 0.94), black, 16,
         rotation=(deg(68), 0.0, 0.0), bevel=0.012)
for angle in (0, 120, 240):
    a = deg(angle)
    box(f"Steering_Spoke_{angle}", (0.035, 0.045, 0.15),
        (0.38, -0.53, 0.94), bare_edge, 0.006, rotation=(deg(68), a, 0.0))

# Lighting and trim read clearly at 5-10 m.
for x in (-0.55, 0.55):
    box(f"Headlight_{x}", (0.47, 0.035, 0.18), (x, -2.105, 0.69), headlight, 0.022)
    box(f"Tail_Light_{x}", (0.48, 0.035, 0.19), (x, 2.105, 0.69), tail_light, 0.022)
box("Front_Grille", (0.50, 0.035, 0.20), (0.0, -2.11, 0.66), black, 0.018)
for x in (-0.18, -0.09, 0.0, 0.09, 0.18):
    box(f"Grille_Slat_{x}", (0.025, 0.018, 0.16), (x, -2.133, 0.66), chrome, 0.004)
box("Rear_Number_Plate_Recess", (0.52, 0.03, 0.18), (0.0, 2.11, 0.65), black, 0.015)

# Scavenged-town wear: sill rust, low dirt, and one bolted repair patch, never missing panels.
for x in (-0.882, 0.882):
    side = "L" if x > 0 else "R"
    box(f"Rusty_Sill_{side}", (0.035, 2.25, 0.085), (x, 0.18, 0.35), rust, 0.014)
    for y in (-1.72, -0.92, 0.62, 1.52):
        box(f"Dirt_Scab_{side}_{y}", (0.043, 0.34, 0.055), (x, y, 0.405), black, 0.010,
            rotation=(deg(0), deg(0), deg(5 if y > 0 else -4)))
box("Repair_Plate", (0.035, 0.48, 0.26), (0.889, 0.72, 0.72), bare_edge, 0.018)
for y in (0.54, 0.90):
    for z in (0.63, 0.81):
        cylinder(f"Repair_Bolt_{y}_{z}", 0.024, 0.035, (0.914, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0), bevel=0.004)

finish("sedan", (1.9, 1.5, 4.4), max_triangles=6000)
