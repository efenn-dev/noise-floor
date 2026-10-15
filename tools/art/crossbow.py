"""V30 hunting crossbow with one loaded bolt, muzzle toward Blender -Y / Godot -Z."""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


def rod(name, start, end, radius, mat, vertices=12):
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length,
                                        location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    return obj


reset()
metal = material("Gun Metal", (0.050, 0.058, 0.060), 0.82, 0.38)
wood = material("Gun Wood", (0.20, 0.065, 0.020), 0.0, 0.46)
rubber = material("Gun Rubber", (0.012, 0.014, 0.014), 0.0, 0.92)

box("Stock", (0.070, 0.400, 0.105), (0.0, 0.300, 0.075), wood, 0.012,
    rotation=(deg(-4), 0.0, 0.0))
box("Butt_Pad", (0.072, 0.020, 0.108), (0.0, 0.505, 0.061), rubber, 0.007)
box("Wrist", (0.052, 0.160, 0.080), (0.0, 0.105, 0.086), wood, 0.010,
    rotation=(deg(-16), 0.0, 0.0))
box("Rail", (0.042, 0.720, 0.040), (0.0, -0.205, 0.145), metal, 0.006)
box("Forend", (0.075, 0.310, 0.070), (0.0, -0.245, 0.105), wood, 0.010)
box("Trigger_Housing", (0.060, 0.175, 0.080), (0.0, 0.020, 0.115), metal, 0.008)
rod("Trigger", (0.0, 0.045, 0.105), (0.0, 0.060, 0.078), 0.0022, metal)

# Recurve limbs and taut string, wide enough to read in first person.
for side in (-1.0, 1.0):
    rod(f"Limb_Inner_{int(side)}", (side * 0.02, -0.535, 0.145),
        (side * 0.255, -0.505, 0.155), 0.014, metal, 16)
    rod(f"Limb_Outer_{int(side)}", (side * 0.255, -0.505, 0.155),
        (side * 0.365, -0.455, 0.175), 0.011, metal, 16)
    rod(f"String_{int(side)}", (side * 0.365, -0.455, 0.175),
        (0.0, 0.015, 0.165), 0.0014, rubber, 8)
box("Limb_Block", (0.105, 0.060, 0.075), (0.0, -0.520, 0.145), metal, 0.008)

# Loaded bolt: shaft, steel point, fletching. This same scale is mirrored by ProjectileView.
rod("Loaded_Bolt", (0.0, 0.030, 0.176), (0.0, -0.615, 0.176), 0.0030, wood, 12)
bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.007, radius2=0.0, depth=0.040,
                                location=(0.0, -0.635, 0.176), rotation=(deg(90), 0.0, 0.0))
bpy.context.object.name = "Bolt_Point"
bpy.context.object.data.materials.append(metal)
for side in (-1, 1):
    box(f"Fletching_{side}", (0.002, 0.055, 0.020), (side * 0.004, -0.005, 0.186),
        rubber, 0.001)

box("Rear_Sight", (0.030, 0.020, 0.018), (0.0, 0.075, 0.185), metal, 0.002)
box("Front_Sight", (0.008, 0.018, 0.018), (0.0, -0.490, 0.185), metal, 0.002)

finish("crossbow", (0.78, 0.22, 1.18), max_triangles=14900)
