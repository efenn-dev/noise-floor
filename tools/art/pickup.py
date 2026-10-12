"""Battered 1980s full-size pickup truck for Noise Floor.

    blender.exe -b --factory-startup --python tools/art/pickup.py
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, part, reset  # noqa: E402

reset()

# Vehicle materials have fixed names because the game replaces/tints them at runtime.
paint = material("Car Paint", (0.5, 0.5, 0.5), 0.35, 0.62)
glass = material("Car Glass", (0.025, 0.045, 0.055), 0.05, 0.10)
tyre = material("Tyre", (0.012, 0.014, 0.013), 0.0, 0.92)
chrome = material("Chrome", (0.38, 0.40, 0.40), 0.90, 0.35)
interior = material("Interior", (0.075, 0.078, 0.074), 0.0, 0.90)
headlight = material("Headlight", (0.92, 0.88, 0.68), 0.05, 0.28)
tail_light = material("Tail Light", (0.55, 0.018, 0.012), 0.05, 0.38)
black, rust, bare_edge = mat("black"), mat("rust"), mat("bare_edge")


def torus(name, major_radius, minor_radius, location, material_, major_segments=16, minor_segments=8,
          rotation=(0.0, 0.0, 0.0)):
    """A deliberately faceted torus for tyres and the steering wheel."""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


def wheel(name, x, y):
    """Make a complete independent wheel, axle along X, with its pivot at axle centre."""
    centre = (x, y, 0.40)
    pieces = [
        torus(f"{name}_Tyre", 0.305, 0.095, centre, tyre, 16, 8, (0.0, deg(90), 0.0)),
        cylinder(f"{name}_Hub", 0.185, 0.205, centre, bare_edge, 16,
                 rotation=(0.0, deg(90), 0.0), bevel=0.012),
        cylinder(f"{name}_Hubcap", 0.105, 0.218, centre, chrome, 12,
                 rotation=(0.0, deg(90), 0.0), bevel=0.010),
    ]
    # A dark inner ring gives the hub some depth without increasing the silhouette.
    pieces.append(cylinder(f"{name}_Dust_Cap", 0.045, 0.224, centre, black, 10,
                           rotation=(0.0, deg(90), 0.0), bevel=0.006))
    part(name, pieces, centre)


# Separate wheels. Front is -Y and driver's left is +X in Blender.
for wheel_name, wx, wy in (
    ("Wheel_FL", 0.875, -1.48),
    ("Wheel_FR", -0.875, -1.48),
    ("Wheel_RL", 0.875, 1.72),
    ("Wheel_RR", -0.875, 1.72),
):
    wheel(wheel_name, wx, wy)

# Chassis, axles and high-clearance underbody.
box("Chassis_Left", (0.16, 4.38, 0.18), (0.57, 0.02, 0.47), black, 0.035)
box("Chassis_Right", (0.16, 4.38, 0.18), (-0.57, 0.02, 0.47), black, 0.035)
for y in (-1.48, 0.25, 1.72):
    box(f"Chassis_Crossmember_{y}", (1.32, 0.14, 0.15), (0.0, y, 0.49), black, 0.025)
for y in (-1.48, 1.72):
    cylinder(f"Axle_{y}", 0.075, 1.62, (0.0, y, 0.40), black, 12,
             rotation=(0.0, deg(90), 0.0))
# The exporter grounds the joined body, so this unobtrusive skid shares the tyres' Z=0 contact plane.
box("Grounding_Skid", (0.10, 0.24, 0.04), (0.0, 0.15, 0.02), black)

# Lower body and broad 1980s slab-sided silhouette.
box("Front_Valance", (1.86, 0.30, 0.25), (0.0, -2.32, 0.68), paint, 0.045)
box("Engine_Bay", (1.78, 1.30, 0.48), (0.0, -1.72, 0.91), paint, 0.075)
box("Hood", (1.72, 1.28, 0.10), (0.0, -1.73, 1.19), paint, 0.035,
    rotation=(deg(-1.5), 0.0, 0.0))
box("Cab_Lower", (1.78, 1.38, 0.68), (0.0, -0.50, 0.91), paint, 0.055)

# Rocker panels and mild low-body rust/dirt, kept narrow so the paint remains dominant.
for side, x in (("L", 0.912), ("R", -0.912)):
    box(f"Rocker_{side}", (0.075, 1.40, 0.18), (x, -0.47, 0.57), paint, 0.018)
    box(f"Rocker_Rust_{side}", (0.014, 0.70, 0.075),
        (x + (0.045 if x > 0 else -0.045), -0.34, 0.565), rust, 0.008,
        rotation=(0.0, deg(4 if x > 0 else -4), deg(1.5)))

# Cab roof and thin pillars. The windscreen opening stays clear above the low dashboard.
box("Cab_Roof", (1.76, 1.24, 0.13), (0.0, -0.35, 1.735), paint, 0.055)
for side, x in (("L", 0.845), ("R", -0.845)):
    box(f"A_Pillar_{side}", (0.065, 0.12, 0.58), (x, -0.91, 1.455), paint, 0.018,
        rotation=(deg(-18), 0.0, 0.0))
    box(f"B_Pillar_{side}", (0.065, 0.12, 0.60), (x, 0.18, 1.445), paint, 0.018)

# Intact windows are shallow slabs. Their tint is dark enough to read but remains see-through in-game.
box("Windscreen", (1.57, 0.035, 0.48), (0.0, -0.915, 1.48), glass, 0.010,
    rotation=(deg(-18), 0.0, 0.0))
box("Rear_Window", (1.43, 0.035, 0.42), (0.0, 0.275, 1.48), glass, 0.012)
for side, x in (("L", 0.865), ("R", -0.865)):
    box(f"Side_Window_{side}", (0.025, 0.91, 0.43), (x, -0.35, 1.48), glass, 0.010)

# Door skins, seams, handles and one bolted repair patch.
for side, x in (("L", 0.902), ("R", -0.902)):
    box(f"Door_{side}", (0.055, 0.92, 0.63), (x, -0.34, 0.96), paint, 0.018)
    box(f"Door_Handle_{side}", (0.035, 0.18, 0.045),
        (x + (0.038 if x > 0 else -0.038), -0.06, 1.23), chrome, 0.008)
box("Door_Repair_Plate", (0.018, 0.28, 0.20), (0.943, -0.50, 0.88), bare_edge, 0.012,
    rotation=(0.0, deg(2), deg(-3)))
for y in (-0.61, -0.39):
    for z in (0.82, 0.94):
        cylinder(f"Repair_Bolt_{y}_{z}", 0.018, 0.025, (0.958, y, z), bare_edge, 8,
                 rotation=(0.0, deg(90), 0.0))

# Interior: bench-like split seats, rear cargo shelf, low dash, pedals and steering wheel.
box("Cab_Floor", (1.55, 1.18, 0.09), (0.0, -0.33, 0.69), interior, 0.025)
for side, x in (("Driver", 0.42), ("Passenger", -0.42)):
    box(f"{side}_Seat_Cushion", (0.68, 0.48, 0.18), (x, -0.18, 0.87), interior, 0.065,
        rotation=(deg(-3), 0.0, 0.0))
    box(f"{side}_Seat_Back", (0.68, 0.17, 0.58), (x, 0.04, 1.17), interior, 0.060,
        rotation=(deg(-8), 0.0, 0.0))
box("Rear_Cargo_Shelf", (1.47, 0.22, 0.16), (0.0, 0.18, 0.83), interior, 0.025)
box("Dashboard", (1.56, 0.27, 0.22), (0.0, -0.69, 1.12), interior, 0.035,
    rotation=(deg(-5), 0.0, 0.0))
box("Instrument_Binnacle", (0.46, 0.12, 0.12), (0.40, -0.82, 1.235), black, 0.025)
box("Steering_Column", (0.09, 0.33, 0.09), (0.40, -0.61, 1.14), black, 0.014,
    rotation=(deg(-17), 0.0, 0.0))
torus("Steering_Wheel", 0.155, 0.025, (0.40, -0.74, 1.28), interior, 14, 6,
      (deg(72), 0.0, 0.0))

# Open cargo bed: floor, full sides, front wall, and closed tailgate.
box("Bed_Floor", (1.68, 2.06, 0.14), (0.0, 1.39, 0.72), paint, 0.035)
for side, x in (("L", 0.875), ("R", -0.875)):
    box(f"Bed_Side_{side}", (0.18, 2.08, 0.58), (x, 1.39, 0.96), paint, 0.045)
    box(f"Bed_Rail_{side}", (0.22, 2.09, 0.11), (x, 1.39, 1.275), paint, 0.035)
box("Bed_Front_Wall", (1.70, 0.13, 0.61), (0.0, 0.39, 0.98), paint, 0.035)
box("Tailgate", (1.70, 0.15, 0.61), (0.0, 2.39, 0.98), paint, 0.040)
box("Tailgate_Inner_Lip", (1.44, 0.035, 0.08), (0.0, 2.305, 1.21), bare_edge, 0.012)
box("Tailgate_Handle", (0.29, 0.035, 0.07), (0.0, 2.478, 1.14), chrome, 0.010)

# A couple of loose, skewed scavenged planks in the open bed.
box("Bed_Plank_One", (0.23, 1.42, 0.075), (-0.34, 1.39, 0.84), rust, 0.018,
    rotation=(0.0, deg(2), deg(7)))
box("Bed_Plank_Two", (0.21, 1.18, 0.07), (0.28, 1.50, 0.88), rust, 0.018,
    rotation=(0.0, deg(-2), deg(-9)))

# Bumpers, grille and simple road lights.
box("Front_Bumper", (1.94, 0.18, 0.18), (0.0, -2.50, 0.53), chrome, 0.035)
box("Rear_Bumper", (1.90, 0.18, 0.18), (0.0, 2.50, 0.52), chrome, 0.035)
box("Grille", (1.28, 0.035, 0.29), (0.0, -2.485, 0.86), black, 0.015)
for x in (-0.45, -0.15, 0.15, 0.45):
    box(f"Grille_Bar_{x}", (0.055, 0.025, 0.24), (x, -2.507, 0.86), bare_edge, 0.008)
for side, x in (("L", 0.70), ("R", -0.70)):
    box(f"Headlight_Bezel_{side}", (0.32, 0.05, 0.25), (x, -2.477, 0.89), chrome, 0.018)
    box(f"Headlight_{side}", (0.25, 0.025, 0.17), (x, -2.510, 0.90), headlight, 0.012)
    box(f"Tail_Light_{side}", (0.18, 0.025, 0.28), (x, 2.480, 1.00), tail_light, 0.012)

# Mirrors, wheel-arch eyebrows and a crooked rear plate reinforce the battered silhouette.
for side, x in (("L", 0.968), ("R", -0.968)):
    box(f"Mirror_Arm_{side}", (0.055, 0.20, 0.055), (x, -0.72, 1.39), black, 0.010)
    box(f"Mirror_{side}", (0.045, 0.22, 0.18), (x, -0.84, 1.43), chrome, 0.025,
        rotation=(0.0, deg(4 if x > 0 else -4), 0.0))
for y, label in ((-1.48, "Front"), (1.72, "Rear")):
    for side, x in (("L", 0.925), ("R", -0.925)):
        box(f"{label}_Arch_Brow_{side}", (0.045, 0.88, 0.075), (x, y, 0.77), bare_edge, 0.018)
box("Rear_License_Plate", (0.42, 0.025, 0.18), (0.16, 2.56, 0.58), bare_edge, 0.012,
    rotation=(deg(2), 0.0, deg(-3)))

finish("pickup", (2.0, 1.85, 5.2), max_triangles=6000)
