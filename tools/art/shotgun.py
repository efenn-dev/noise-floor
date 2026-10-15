"""V30 pump shotgun, muzzle toward Blender -Y / Godot -Z."""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


def rod(name, start, end, radius, mat, vertices=14):
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
metal = material("Gun Metal", (0.055, 0.062, 0.065), 0.86, 0.32)
wood = material("Gun Wood", (0.24, 0.085, 0.027), 0.0, 0.42)
rubber = material("Gun Rubber", (0.014, 0.016, 0.016), 0.0, 0.92)

# Butt, wrist and receiver. The pistol grip centre is deliberately stable for Hands.GUNS.
box("Buttstock", (0.070, 0.315, 0.105), (0.0, 0.360, 0.070), wood, 0.012,
    rotation=(deg(-5), 0.0, 0.0))
box("Recoil_Pad", (0.072, 0.020, 0.108), (0.0, 0.520, 0.056), rubber, 0.008,
    rotation=(deg(-5), 0.0, 0.0))
box("Wrist", (0.052, 0.150, 0.075), (0.0, 0.185, 0.086), wood, 0.012,
    rotation=(deg(-18), 0.0, 0.0))
box("Receiver", (0.064, 0.245, 0.085), (0.0, 0.025, 0.135), metal, 0.009)
box("Loading_Gate", (0.040, 0.090, 0.008), (0.0, 0.070, 0.088), rubber, 0.002)

# Barrel and six-round tube. Their front faces become the measured choke/muzzle anchor.
cylinder("Barrel", 0.0125, 0.690, (0.0, -0.360, 0.165), metal, vertices=28,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Magazine_Tube", 0.0135, 0.550, (0.0, -0.285, 0.116), metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
cylinder("Bore", 0.0082, 0.002, (0.0, -0.706, 0.165), rubber, vertices=24,
         rotation=(deg(90), 0.0, 0.0))
box("Barrel_Lug", (0.035, 0.026, 0.055), (0.0, -0.565, 0.139), metal, 0.004)

# Ribbed sliding fore-end; the world moves the complete gun for the pump gesture.
box("Pump", (0.072, 0.235, 0.075), (0.0, -0.255, 0.105), wood, 0.012)
for i in range(9):
    box(f"Pump_Rib_{i}", (0.074, 0.008, 0.078), (0.0, -0.350 + i * 0.024, 0.105),
        rubber, 0.002)

# Trigger guard, trigger and bead sights.
rod("Guard_Left", (-0.025, 0.105, 0.104), (-0.025, 0.120, 0.066), 0.003, metal)
rod("Guard_Bottom", (-0.025, 0.120, 0.066), (-0.025, 0.180, 0.070), 0.003, metal)
rod("Guard_Right", (0.025, 0.105, 0.104), (0.025, 0.120, 0.066), 0.003, metal)
rod("Guard_Right_Bottom", (0.025, 0.120, 0.066), (0.025, 0.180, 0.070), 0.003, metal)
rod("Trigger", (0.0, 0.125, 0.105), (0.0, 0.140, 0.079), 0.0022, metal)
cylinder("Front_Bead", 0.0035, 0.008, (0.0, -0.650, 0.181), metal, vertices=16)
box("Rear_Notch", (0.020, 0.018, 0.010), (0.0, 0.095, 0.182), metal, 0.002)

finish("shotgun", (0.10, 0.20, 1.25), max_triangles=14900)
