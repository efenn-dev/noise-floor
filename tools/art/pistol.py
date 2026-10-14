"""A detailed compact semi-automatic pistol (M14), held close in first person.

    blender.exe -b --factory-startup --python tools/art/pistol.py

Not a build piece: the box passed to finish() is its placement envelope. The muzzle points to
the front (-Y in Blender, -Z in Godot). Keep the grip and muzzle anchors stable: Shooter places
the exported model directly under the camera.
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


def bevel(obj, width: float, segments: int = 2):
    """Apply a soft bevel now, so the exported GLB does not depend on Blender modifiers."""
    mod = obj.modifiers.new("Soft edge bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def rod(name: str, start, end, radius: float, mat, vertices: int = 10):
    """A cylinder between two points, useful for the curved-looking trigger guard."""
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=delta.length,
                                        location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(delta.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(obj, min(radius * 0.35, 0.0008), 2)
    return obj


reset()

gun_metal = material("Gun Metal", (0.055, 0.065, 0.075), 0.88, 0.26)
gun_polymer = material("Gun Polymer", (0.022, 0.026, 0.029), 0.05, 0.63)
gun_rubber = material("Gun Rubber", (0.010, 0.012, 0.013), 0.0, 0.92)

# Slide and barrel group. The slide is deliberately broad and softly radiused, with a slightly
# narrower nose so it reads as machined steel rather than a rectangular toy block.
box("Slide", (0.032, 0.174, 0.035), (0.0, -0.007, 0.112), gun_metal, 0.0032)
box("Slide_Nose", (0.030, 0.030, 0.032), (0.0, -0.106, 0.111), gun_metal, 0.003)

# A real recess on the right side of the slide, with the chamber/barrel hood down inside it.
port = box("Ejection_Port_Cutter", (0.012, 0.038, 0.015), (-0.0135, -0.016, 0.120), gun_metal, 0.001)
slide = bpy.data.objects["Slide"]
boolean = slide.modifiers.new("Ejection port", "BOOLEAN")
boolean.operation = "DIFFERENCE"
boolean.solver = "EXACT"
boolean.object = port
bpy.context.view_layer.objects.active = slide
bpy.ops.object.modifier_apply(modifier=boolean.name)
bpy.data.objects.remove(port, do_unlink=True)
box("Barrel_Hood", (0.010, 0.031, 0.009), (-0.0118, -0.016, 0.116), gun_metal, 0.0015)

# Six separate rear serrations per side catch highlights at first-person distance.
for side in (-1, 1):
    for i in range(6):
        y = 0.052 + i * 0.006
        box("Slide_Serrations" if side == -1 and i == 0 else f"Slide_Serration_{side}_{i}",
            (0.0011, 0.0030, 0.025), (side * 0.0160, y, 0.111), gun_metal, 0.00035,
            rotation=(deg(-8), 0.0, 0.0))

# Separate front blade and two rear ears leave a visible sight notch.
box("Front_Sight", (0.0050, 0.010, 0.008), (0.0, -0.089, 0.133), gun_metal, 0.001)
box("Rear_Sight", (0.0070, 0.010, 0.009), (-0.0075, 0.071, 0.1335), gun_metal, 0.001)
box("Rear_Sight_Right", (0.0070, 0.010, 0.009), (0.0075, 0.071, 0.1335), gun_metal, 0.001)

# The barrel ring is proud of the slide and the smaller dark bore sits just behind its front face.
cylinder("Muzzle", 0.0072, 0.010, (0.0, -0.1125, 0.112), gun_metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.0007)
cylinder("Bore", 0.0042, 0.0010, (0.0, -0.1180, 0.112), gun_rubber, vertices=20,
         rotation=(deg(90), 0.0, 0.0))

# Polymer lower frame, dust cover and small steel controls.
box("Frame", (0.0275, 0.142, 0.025), (0.0, 0.002, 0.083), gun_polymer, 0.003)
box("Dust_Cover", (0.0270, 0.052, 0.018), (0.0, -0.054, 0.073), gun_polymer, 0.0025)
box("Slide_Stop", (0.0014, 0.024, 0.006), (-0.0144, 0.029, 0.093), gun_metal, 0.0006)
cylinder("Takedown_Pin", 0.0032, 0.0015, (-0.0143, -0.011, 0.084), gun_metal,
         vertices=16, rotation=(0.0, deg(90), 0.0), bevel=0.0004)

# Slanted grip with a separate backstrap and magazine base. Its centre is the placement anchor.
box("Grip", (0.0290, 0.045, 0.105), (0.0, 0.058, 0.035), gun_polymer, 0.004,
    rotation=(deg(-14), 0.0, 0.0))
box("Grip_Backstrap", (0.026, 0.009, 0.078), (0.0, 0.078, 0.035), gun_rubber, 0.0025,
    rotation=(deg(-14), 0.0, 0.0))
box("Magazine_Base_Plate", (0.031, 0.047, 0.007), (0.0, 0.0710, -0.0130), gun_rubber, 0.0025,
    rotation=(deg(-14), 0.0, 0.0))

# Fine stipple pads on both sides: shallow enough not to alter the old width, large enough to read.
for side in (-1, 1):
    for row in range(7):
        for col in range(3):
            y = 0.047 + col * 0.010 + (row % 2) * 0.0015
            z = 0.002 + row * 0.0105
            box(f"Grip_Stipple_{side}_{row}_{col}", (0.00065, 0.0050, 0.0040),
                (side * 0.0147, y, z), gun_rubber, 0.0005)

# Rounded trapezoid-like guard and a slim, rearward-curving trigger.
rod("Trigger_Guard", (-0.0115, -0.022, 0.066), (-0.0115, -0.011, 0.045), 0.0025, gun_polymer)
rod("Trigger_Guard_Front", (-0.0115, -0.011, 0.045), (-0.0115, 0.023, 0.043), 0.0025, gun_polymer)
rod("Trigger_Guard_Rear", (-0.0115, 0.023, 0.043), (-0.0115, 0.031, 0.065), 0.0025, gun_polymer)
rod("Trigger_Guard_Right", (0.0115, -0.022, 0.066), (0.0115, -0.011, 0.045), 0.0025, gun_polymer)
rod("Trigger_Guard_Right_Bottom", (0.0115, -0.011, 0.045), (0.0115, 0.023, 0.043), 0.0025, gun_polymer)
rod("Trigger_Guard_Right_Rear", (0.0115, 0.023, 0.043), (0.0115, 0.031, 0.065), 0.0025, gun_polymer)
rod("Trigger", (0.0, -0.001, 0.067), (0.0, 0.010, 0.052), 0.0019, gun_metal, 12)

finish("pistol", (0.04, 0.16, 0.24), max_triangles=14900)
