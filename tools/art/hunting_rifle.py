"""A detailed traditional bolt-action hunting rifle (M14), held close in first person.

    blender.exe -b --factory-startup --python tools/art/hunting_rifle.py

Not a build piece: the box passed to finish() is its placement envelope. The muzzle points to
the front (-Y in Blender, -Z in Godot). The asymmetrical bolt fixes the old lateral placement,
so the overall footprint and hand/muzzle anchors must stay stable.
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


def bevel(obj, width: float, segments: int = 2):
    mod = obj.modifiers.new("Soft edge bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def profile(name: str, stations, mat, bevel_width: float):
    """Make a bevelled stock section from (y, half-width, bottom-z, top-z) stations."""
    verts = []
    for y, half, bottom, top in stations:
        verts += [(-half, y, bottom), (half, y, bottom), (half, y, top), (-half, y, top)]
    faces = [(0, 1, 2, 3)]
    for i in range(len(stations) - 1):
        a, b = i * 4, (i + 1) * 4
        faces += [(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2),
                  (a + 2, b + 2, b + 3, a + 3), (a + 3, b + 3, b, a)]
    e = (len(stations) - 1) * 4
    faces.append((e + 3, e + 2, e + 1, e))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bevel(obj, bevel_width, 3)
    return obj


def rod(name: str, start, end, radius: float, mat, vertices: int = 12):
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
    bevel(obj, min(radius * 0.3, 0.001), 2)
    return obj


def sling_loop(name: str, y: float, z: float):
    cylinder(name + "_Stud", 0.0032, 0.014, (0.0, y, z + 0.007), gun_metal, vertices=12)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.009, minor_radius=0.0018,
                                     major_segments=16, minor_segments=6,
                                     location=(0.0, y, z - 0.004), rotation=(0.0, deg(90), 0.0))
    loop = bpy.context.object
    loop.name = name
    loop.scale.z = 0.62
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    loop.data.materials.append(gun_metal)


reset()

gun_metal = material("Gun Metal", (0.050, 0.060, 0.066), 0.88, 0.28)
gun_wood = material("Gun Wood", (0.22, 0.075, 0.024), 0.0, 0.38)
gun_rubber = material("Gun Rubber", (0.012, 0.014, 0.014), 0.0, 0.93)

# A continuous, shaped walnut stock: broad butt, narrow wrist, then a tapered fore-end.
profile("Stock_Butt", [
    (0.520, 0.021, -0.004, 0.086),
    (0.455, 0.023, -0.001, 0.105),
    (0.330, 0.022, 0.012, 0.119),
    (0.245, 0.019, 0.035, 0.113),
    (0.180, 0.016, 0.061, 0.108),
], gun_wood, 0.005)
profile("Wrist", [
    (0.180, 0.016, 0.061, 0.108),
    (0.125, 0.017, 0.051, 0.111),
    (0.080, 0.019, 0.055, 0.112),
], gun_wood, 0.004)
profile("Forend", [
    (0.080, 0.020, 0.055, 0.108),
    (-0.080, 0.020, 0.057, 0.105),
    (-0.245, 0.017, 0.066, 0.101),
    (-0.360, 0.013, 0.076, 0.098),
], gun_wood, 0.004)

# Raised cheek rest on the shooter's left side and a softly rounded recoil pad.
profile("Cheek_Rest", [
    (0.455, 0.0218, 0.067, 0.111),
    (0.350, 0.0250, 0.073, 0.128),
    (0.265, 0.0220, 0.078, 0.121),
], gun_wood, 0.003)
profile("Butt_Pad", [
    (0.530, 0.022, -0.006, 0.088),
    (0.516, 0.022, -0.004, 0.087),
], gun_rubber, 0.0035)

# Receiver, bottom metal and a recognizable bolt-action assembly.
box("Receiver", (0.034, 0.205, 0.043), (0.0, 0.034, 0.126), gun_metal, 0.0045)
cylinder("Receiver_Ring", 0.021, 0.044, (0.0, -0.055, 0.127), gun_metal, vertices=24,
         rotation=(deg(90), 0.0, 0.0), bevel=0.001)
box("Magazine_Plate", (0.030, 0.082, 0.008), (0.0, 0.034, 0.066), gun_metal, 0.0015)
box("Bolt_Body", (0.010, 0.082, 0.010), (-0.017, 0.090, 0.132), gun_metal, 0.002)
rod("Bolt_Handle", (-0.020, 0.103, 0.131), (-0.048, 0.103, 0.105), 0.0046, gun_metal, 14)
cylinder("Bolt_Knob", 0.0070, 0.012, (-0.053, 0.103, 0.101), gun_metal, vertices=16,
         rotation=(0.0, deg(55), 0.0), bevel=0.0012)

# Open trigger guard, separate curved trigger and rear safety tab.
rod("Trigger_Guard", (-0.013, 0.092, 0.069), (-0.013, 0.074, 0.038), 0.0024, gun_metal)
rod("Trigger_Guard_Bottom", (-0.013, 0.074, 0.038), (-0.013, 0.145, 0.040), 0.0024, gun_metal)
rod("Trigger_Guard_Rear", (-0.013, 0.145, 0.040), (-0.013, 0.151, 0.068), 0.0024, gun_metal)
rod("Trigger_Guard_Right", (0.013, 0.092, 0.069), (0.013, 0.074, 0.038), 0.0024, gun_metal)
rod("Trigger_Guard_Right_Bottom", (0.013, 0.074, 0.038), (0.013, 0.145, 0.040), 0.0024, gun_metal)
rod("Trigger_Guard_Right_Rear", (0.013, 0.145, 0.040), (0.013, 0.151, 0.068), 0.0024, gun_metal)
rod("Trigger", (0.0, 0.097, 0.067), (0.0, 0.109, 0.047), 0.0019, gun_metal, 12)
box("Safety", (0.009, 0.019, 0.004), (-0.011, 0.138, 0.151), gun_metal, 0.001)

# Tapered free-floating barrel, crown/bore and simple iron sights.
bpy.ops.mesh.primitive_cone_add(vertices=28, radius1=0.0115, radius2=0.0072, depth=0.600,
                                location=(0.0, -0.250, 0.127), rotation=(deg(90), 0.0, 0.0))
barrel = bpy.context.object
barrel.name = "Barrel"
barrel.data.materials.append(gun_metal)
bevel(barrel, 0.0008, 2)
cylinder("Muzzle_Crown", 0.0080, 0.012, (0.0, -0.544, 0.127), gun_metal, vertices=28,
         rotation=(deg(90), 0.0, 0.0), bevel=0.0007)
cylinder("Muzzle_Bore", 0.0045, 0.001, (0.0, -0.550, 0.127), gun_rubber, vertices=20,
         rotation=(deg(90), 0.0, 0.0))
box("Front_Sight", (0.005, 0.014, 0.014), (0.0, -0.506, 0.143), gun_metal, 0.0012)
box("Rear_Sight", (0.006, 0.022, 0.009), (-0.006, -0.096, 0.149), gun_metal, 0.001)
box("Rear_Sight_Right", (0.006, 0.022, 0.009), (0.006, -0.096, 0.149), gun_metal, 0.001)

# Two working-scale sling swivels under the fore-end and butt stock.
sling_loop("Sling_Swivel_Front", -0.275, 0.058)
sling_loop("Sling_Swivel_Rear", 0.405, 0.002)

finish("hunting_rifle", (0.09, 0.2, 1.1), max_triangles=14900)
