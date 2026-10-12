"""Old household fridge scavenged for food storage. Written by Codex for kit.py.

    blender.exe -b --factory-startup --python tools/art/fridge.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, mat, material, reset  # noqa: E402

reset()
enamel = material("Enamel", (0.72, 0.69, 0.57), 0.05, 0.45)
grime = material("Grime", (0.18, 0.145, 0.11), 0.05, 0.88)
rubber, rust, bare_edge = mat("rubber"), mat("rust"), mat("bare_edge")

# Rounded 1980s cabinet, almost filling the collision volume.
box("Cabinet", (0.65, 0.57, 1.50), (0.0, 0.015, 0.80), enamel, 0.045)
box("Dark_Base_Recess", (0.57, 0.025, 0.16), (0.0, -0.281, 0.145), grime, 0.012)

# The upper freezer door sits square. Dark trim behind it makes the seal readable at range.
box("Freezer_Seal", (0.606, 0.030, 0.480), (0.0, -0.286, 1.302), rubber, 0.025)
box("Freezer_Door", (0.580, 0.052, 0.444), (0.0, -0.310, 1.305), enamel, 0.035)

# Lower door is hinged on the viewer's right and hangs a few degrees open.
HINGE_X = 0.294
LOWER_ANGLE = deg(3.0)


def lower_xy(local_x: float, base_y: float) -> tuple[float, float]:
    """Rotate a front-door detail about the lower door's right-hand hinge."""
    from math import cos, sin
    dx = local_x - HINGE_X
    return (HINGE_X + dx * cos(LOWER_ANGLE), base_y + dx * sin(LOWER_ANGLE))


def lower_box(name: str, size: tuple[float, float, float], local_x: float, base_y: float,
              z: float, material_, bevel: float = 0.0):
    x, y = lower_xy(local_x, base_y)
    return box(name, size, (x, y, z), material_, bevel, rotation=(0.0, 0.0, LOWER_ANGLE))


lower_box("Fridge_Seal", (0.606, 0.030, 0.860), 0.0, -0.286, 0.735, rubber, 0.025)
lower_box("Fridge_Door_Ajar", (0.580, 0.052, 0.824), 0.0, -0.310, 0.735, enamel, 0.035)

# Long, chunky vertical pull handles with metal end caps.
box("Freezer_Handle", (0.055, 0.070, 0.285), (-0.228, -0.356, 1.305), rubber, 0.016)
for z in (1.185, 1.425):
    box(f"Freezer_Handle_Cap_{z}", (0.075, 0.073, 0.050), (-0.228, -0.354, z), bare_edge, 0.010)

for z in (0.475, 0.995):
    lower_box(f"Fridge_Handle_Cap_{z}", (0.075, 0.060, 0.055), -0.228, -0.340, z,
              bare_edge, 0.010)
lower_box("Fridge_Handle", (0.055, 0.060, 0.565), -0.228, -0.342, 0.735, rubber, 0.016)

# Bottom compressor vent: six thick, shadowed slots in a scuffed grille plate.
box("Vent_Plate", (0.470, 0.025, 0.125), (0.045, -0.300, 0.142), bare_edge, 0.015)
for i, x in enumerate((-0.155, -0.085, -0.015, 0.055, 0.125, 0.195)):
    box(f"Vent_Slot_{i}", (0.038, 0.014, 0.077), (x, -0.316, 0.142), rubber, 0.006)

# A faded paper sticker and a small, oxidized magnet on the freezer door.
box("Faded_Sticker", (0.155, 0.010, 0.105), (0.105, -0.342, 1.348), bare_edge, 0.008,
    rotation=(0.0, deg(-4), deg(-3)))
cylinder("Old_Magnet", 0.033, 0.014, (0.190, -0.346, 1.220), rust, 10,
         rotation=(deg(90), 0.0, 0.0), bevel=0.004)

# Shallow dent shadows and short scuffed creases sell the abused sheet metal.
cylinder("Upper_Dent_Shadow", 0.065, 0.010, (0.115, -0.343, 1.455), grime, 10,
         rotation=(deg(90), 0.0, 0.0))
box("Upper_Dent_Crease", (0.105, 0.009, 0.012), (0.115, -0.350, 1.455), bare_edge, 0.004,
    rotation=(0.0, deg(-8), deg(18)))
lower_box("Lower_Dent_Crease_A", (0.155, 0.009, 0.013), 0.090, -0.344, 0.675,
          bare_edge, 0.004)
lower_box("Lower_Dent_Crease_B", (0.105, 0.010, 0.012), 0.120, -0.346, 0.645,
          grime, 0.003)

# Scavenged repair patch, held by four obvious fasteners.
box("Side_Repair_Plate", (0.012, 0.235, 0.245), (0.332, 0.075, 0.865), bare_edge, 0.010)
for yi, y in enumerate((-0.010, 0.160)):
    for zi, z in enumerate((0.780, 0.950)):
        cylinder(f"Repair_Bolt_{yi}_{zi}", 0.016, 0.018, (0.340, y, z), rust, 8,
                 rotation=(0.0, deg(90), 0.0))

# Deterministic grime and rust streaks, concentrated around the wet bottom edge.
for i, (x, h) in enumerate(((-0.255, 0.18), (-0.160, 0.105), (0.235, 0.145))):
    lower_box(f"Grime_Streak_{i}", (0.025, 0.009, h), x, -0.344, 0.255 + h / 2,
              grime, 0.004)
for i, (x, h) in enumerate(((-0.205, 0.115), (0.175, 0.080), (0.270, 0.125))):
    lower_box(f"Rust_Streak_{i}", (0.015, 0.010, h), x, -0.350, 0.255 + h / 2,
              rust, 0.003)
for i, x in enumerate((-0.275, -0.215, -0.070, 0.115, 0.260)):
    cylinder(f"Bottom_Rust_Bloom_{i}", 0.022, 0.010, (x, -0.343, 0.245), rust, 8,
             rotation=(deg(90), 0.0, 0.0))

finish("fridge", (0.7, 1.6, 0.7), max_triangles=2000)
