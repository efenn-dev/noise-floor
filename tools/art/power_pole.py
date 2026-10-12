"""Wooden utility pole for carrying wires between machines.

    blender.exe -b --factory-startup --python tools/art/power_pole.py
"""

import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, mat, material, reset  # noqa: E402

reset()
wood = material("Weathered Wood", (0.24, 0.19, 0.14), 0.0, 0.92)
glass = material("Insulator Glass", (0.46, 0.60, 0.53), 0.05, 0.15)
sign_white = material("Sign White", (0.64, 0.61, 0.50), 0.05, 0.88)
bare, bare_edge, rust = mat("bare"), mat("bare_edge"), mat("rust")

# A faceted, gently tapered timber pole. Its top sits just inside the 3.0 m
# envelope; the crossarm centre is exactly 0.2 m beneath the pole top.
bpy.ops.mesh.primitive_cone_add(
    vertices=12,
    radius1=0.105,
    radius2=0.075,
    depth=2.835,
    end_fill_type="NGON",
    location=(0.0, 0.0, 1.5775),
)
pole = bpy.context.object
pole.name = "Tapered_Wood_Pole"
pole.data.materials.append(wood)

# Low cinder footing, with a battered steel retaining strap.
box("Cinder_Footing", (0.24, 0.22, 0.18), (0.0, 0.0, 0.09), sign_white, 0.018)
box("Footing_Rust_Band", (0.245, 0.225, 0.045), (0.0, 0.0, 0.155), rust, 0.008)

# Main wire crossarm: 1.05 m overall width and exactly 0.2 m below the pole top.
box("Wood_Crossarm", (1.05, 0.10, 0.08), (0.0, 0.0, 2.795), wood, 0.015)
box("Crossarm_Centre_Saddle", (0.18, 0.115, 0.115), (0.0, 0.0, 2.785), rust, 0.012)

# Diagonal scavenged-steel braces tying the long arm back into the pole.
box("Left_Crossarm_Brace", (0.415, 0.035, 0.035), (-0.232, 0.0, 2.610), bare, 0.007,
    rotation=(0.0, deg(41), 0.0))
box("Right_Crossarm_Brace", (0.415, 0.035, 0.035), (0.232, 0.0, 2.610), bare, 0.007,
    rotation=(0.0, deg(-41), 0.0))
for x in (-0.39, -0.075, 0.075, 0.39):
    cylinder(f"Brace_Bolt_{x}", 0.018, 0.052, (x, -0.008, 2.745 if abs(x) > 0.2 else 2.475),
             bare_edge, 8, rotation=(deg(90), 0.0, 0.0))

# Three pale glass/ceramic spool insulators and their metal pins.
for i, x in enumerate((-0.37, 0.0, 0.37)):
    cylinder(f"Insulator_Pin_{i}", 0.012, 0.125, (x, 0.0, 2.885), bare_edge, 10)
    cylinder(f"Insulator_Lower_{i}", 0.042, 0.045, (x, 0.0, 2.870), glass, 12)
    cylinder(f"Insulator_Waist_{i}", 0.028, 0.055, (x, 0.0, 2.915), glass, 12)
    cylinder(f"Insulator_Cap_{i}", 0.050, 0.045, (x, 0.0, 2.960), glass, 12)
    cylinder(f"Wire_Groove_{i}", 0.035, 0.010, (x, 0.0, 2.984), bare, 12)

# A patched crossarm face with deliberately mismatched fasteners.
box("Crossarm_Repair_Plate", (0.17, 0.014, 0.060), (0.22, -0.057, 2.790), bare_edge, 0.004)
for i, x in enumerate((0.16, 0.28)):
    cylinder(f"Crossarm_Repair_Bolt_{i}", 0.010, 0.018, (x, -0.067, 2.790), rust, 8,
             rotation=(deg(90), 0.0, 0.0))

# Steel climbing staples up the front face, clear of the warning placard.
for i, z in enumerate((0.42, 0.72, 1.02, 1.55, 1.85, 2.15, 2.43)):
    for side, x in (("L", -0.062), ("R", 0.062)):
        cylinder(f"Step_Stem_{i}_{side}", 0.008, 0.070, (x, -0.112, z), rust, 6,
                 rotation=(deg(90), 0.0, 0.0))
    cylinder(f"Step_Rung_{i}", 0.009, 0.142, (0.0, -0.145, z), bare_edge, 6,
             rotation=(0.0, deg(90), 0.0))

# Dirty warning sign on the approach face, including a tiny faded hazard field.
box("Warning_Sign", (0.18, 0.012, 0.24), (0.0, -0.106, 1.285), sign_white, 0.008)
hazard_stripes("Warning_Hazard", (0.0, -0.117, 1.315), 0.14, 0.065, 3, "-Y")
box("Warning_Text_Bar_1", (0.11, 0.006, 0.012), (0.0, -0.126, 1.245), mat("black"), 0.002)
box("Warning_Text_Bar_2", (0.075, 0.006, 0.010), (0.0, -0.126, 1.220), mat("black"), 0.002)
for i, x in enumerate((-0.065, 0.065)):
    for j, z in enumerate((1.195, 1.375)):
        cylinder(f"Sign_Screw_{i}_{j}", 0.007, 0.010, (x, -0.117, z), rust, 8,
                 rotation=(deg(90), 0.0, 0.0))

# A rough clamp around a split-looking section makes the pole feel repaired.
cylinder("Pole_Repair_Band", 0.101, 0.075, (0.0, 0.0, 1.68), bare, 12)
box("Pole_Repair_Tab", (0.055, 0.018, 0.12), (0.070, -0.094, 1.68), rust, 0.004)
cylinder("Pole_Repair_Bolt", 0.012, 0.022, (0.070, -0.108, 1.68), bare_edge, 8,
         rotation=(deg(90), 0.0, 0.0))

finish("power_pole", (0.25, 3.0, 0.25), overhang=(0.4, 0.05))
