"""Procedurally build and export the Noise Floor industrial press.

Run with Blender 5.1:
  blender.exe -b --factory-startup --python tools/art/press.py
"""

from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "models" / "press.glb"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def apply_modifier(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def add_box(name, size, location, mat, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Applied edge bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.affect = "EDGES"
        apply_modifier(obj, mod)
    return obj


def add_cylinder(
    name, radius, depth, location, mat, vertices=12, rotation=(0.0, 0.0, 0.0), bevel=0.0
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, end_fill_type="NGON",
        location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Applied rim bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.affect = "EDGES"
        apply_modifier(obj, mod)
    return obj


def add_hazard_stripe(name, x0, y, z0, width, height, slant, mat):
    verts = [
        (x0 - width / 2, y, z0 - height / 2),
        (x0 + width / 2, y, z0 - height / 2),
        (x0 + width / 2 + slant, y, z0 + height / 2),
        (x0 - width / 2 + slant, y, z0 + height / 2),
    ]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def world_bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def triangle_count(objects):
    total = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    return total


clear_scene()

# Flat, texture-free palette. Slight value variations help the silhouette read at distance.
body = material("Painted Green-Grey Steel", (0.16, 0.22, 0.20), 0.55, 0.72)
body_dark = material("Worn Dark Green Steel", (0.095, 0.135, 0.125), 0.60, 0.78)
bare = material("Bare Dark Steel", (0.14, 0.16, 0.17), 0.82, 0.45)
bare_edge = material("Scuffed Steel", (0.25, 0.27, 0.27), 0.78, 0.50)
yellow = material("Hazard Yellow", (0.88, 0.60, 0.035), 0.15, 0.62)
black = material("Hazard Black", (0.025, 0.030, 0.028), 0.20, 0.76)
red = material("Emergency Button Red", (0.72, 0.035, 0.025), 0.10, 0.55)
rubber = material("Chute Lip Rubber", (0.018, 0.022, 0.021), 0.05, 0.85)

# Heavy base and lower frame. All source geometry is built in Z=0..1.4 first.
add_box("Base_Plate", (1.50, 1.10, 0.14), (0.0, 0.0, 0.07), body_dark, 0.035)
add_box("Base_Raised_Pad", (1.20, 0.82, 0.12), (0.0, 0.03, 0.18), body, 0.025)
for x in (-0.63, 0.63):
    for y in (-0.43, 0.43):
        add_cylinder(f"Anchor_Bolt_{x}_{y}", 0.035, 0.035, (x, y, 0.155), bare_edge, 10)

# Four unmistakable guide columns, with chunky collars top and bottom.
for xi, x in enumerate((-0.51, 0.51)):
    for yi, y in enumerate((-0.27, 0.27)):
        add_cylinder(f"Guide_Column_{xi}_{yi}", 0.062, 0.93, (x, y, 0.70), bare, 12)
        add_cylinder(f"Lower_Collar_{xi}_{yi}", 0.092, 0.075, (x, y, 0.285), bare_edge, 12, bevel=0.008)
        add_cylinder(f"Upper_Collar_{xi}_{yi}", 0.092, 0.075, (x, y, 1.115), bare_edge, 12, bevel=0.008)

# Die bed and stepped tool block.
add_box("Die_Bed", (1.12, 0.67, 0.15), (0.0, 0.0, 0.34), bare, 0.025)
add_box("Lower_Die", (0.70, 0.40, 0.095), (0.0, -0.01, 0.455), bare_edge, 0.016)
add_box("Die_Insert", (0.42, 0.24, 0.045), (0.0, -0.01, 0.525), black, 0.008)

# Ram/platen, hydraulic rod, and barrel. The barrel hangs below the crown so the
# crown's top centre remains a clean landing area for the game's status lamp.
add_box("Ram_Platen", (1.02, 0.61, 0.17), (0.0, 0.0, 0.70), bare, 0.025)
add_box("Ram_Wear_Plate", (0.79, 0.44, 0.075), (0.0, -0.005, 0.585), bare_edge, 0.012)
add_cylinder("Hydraulic_Rod", 0.072, 0.25, (0.0, 0.0, 0.88), bare_edge, 14, bevel=0.008)
add_cylinder("Hydraulic_Cylinder", 0.175, 0.37, (0.0, 0.0, 1.075), body_dark, 14, bevel=0.012)
add_cylinder("Cylinder_Lower_Flange", 0.215, 0.065, (0.0, 0.0, 0.91), bare, 14, bevel=0.009)
add_cylinder("Cylinder_Upper_Flange", 0.215, 0.065, (0.0, 0.0, 1.24), bare, 14, bevel=0.009)

# Overhead frame: a low central crown plus taller side shoulders. The shoulders
# set the 1.4 m height while leaving open air directly above the crown centre.
add_box("Crown_Beam", (1.34, 0.72, 0.16), (0.0, 0.0, 1.25), body, 0.03)
for x in (-0.63, 0.63):
    add_box(f"Crown_Shoulder_{x}", (0.19, 0.72, 0.22), (x, 0.0, 1.29), body_dark, 0.025)
    add_box(f"Side_Gusset_{x}", (0.20, 0.48, 0.28), (x, 0.0, 1.06), body, 0.025)

# Front hazard panel (-Y output side). Yellow pieces are separate faces laid over
# a black backing, not a texture.
add_box("Ram_Hazard_Panel", (0.76, 0.018, 0.13), (0.0, -0.314, 0.70), black, 0.008)
for i, x in enumerate((-0.29, -0.145, 0.0, 0.145, 0.29)):
    add_hazard_stripe(f"Hazard_Yellow_Stripe_{i}", x, -0.324, 0.70, 0.075, 0.105, 0.055, yellow)

# Side-mounted scavenged control box. Button points out along +X.
add_box("Control_Box", (0.22, 0.31, 0.29), (0.64, -0.02, 0.81), body_dark, 0.025)
add_box("Control_Box_Face", (0.025, 0.245, 0.225), (0.762, -0.02, 0.81), bare, 0.007)
add_cylinder(
    "Red_Stop_Button", 0.056, 0.042, (0.795, -0.02, 0.85), red, 14,
    rotation=(0.0, math.radians(90.0), 0.0), bevel=0.007
)
add_cylinder(
    "Button_Bezel", 0.076, 0.022, (0.778, -0.02, 0.85), black, 14,
    rotation=(0.0, math.radians(90.0), 0.0), bevel=0.005
)

# Short sloped front output chute and rubber catch lip.
add_box(
    "Output_Chute", (0.68, 0.37, 0.055), (0.0, -0.47, 0.285), bare_edge, 0.012,
    rotation=(math.radians(18.0), 0.0, 0.0)
)
add_box("Chute_Left_Rail", (0.055, 0.37, 0.105), (-0.34, -0.47, 0.32), body_dark, 0.01,
        rotation=(math.radians(18.0), 0.0, 0.0))
add_box("Chute_Right_Rail", (0.055, 0.37, 0.105), (0.34, -0.47, 0.32), body_dark, 0.01,
        rotation=(math.radians(18.0), 0.0, 0.0))
add_box("Chute_Rubber_Lip", (0.76, 0.065, 0.075), (0.0, -0.645, 0.225), rubber, 0.012)

# A few intentional repair plates sell the worn, scavenged construction without
# relying on texture detail.
add_box("Left_Repair_Plate", (0.17, 0.025, 0.25), (-0.675, 0.20, 0.72), bare_edge, 0.01)
add_box("Back_Service_Plate", (0.36, 0.025, 0.25), (0.22, 0.372, 0.82), body_dark, 0.012)
for i, z in enumerate((0.74, 0.90)):
    add_cylinder(
        f"Service_Bolt_{i}", 0.022, 0.03, (0.22, 0.393, z), bare_edge, 8,
        rotation=(math.radians(90.0), 0.0, 0.0)
    )

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]

# Centre the complete model at the origin as expected by the game.
bmin, bmax = world_bounds(meshes)
centre = (bmin + bmax) * 0.5
for obj in meshes:
    obj.location -= centre
bpy.context.view_layer.update()

bmin, bmax = world_bounds(meshes)
triangles = triangle_count(meshes)

eps = 1.0e-5
assert bmin.x >= -0.85 - eps and bmax.x <= 0.85 + eps
assert bmin.y >= -0.85 - eps and bmax.y <= 0.85 + eps
assert bmin.z >= -0.70 - eps and bmax.z <= 0.70 + eps
assert 600 <= triangles <= 3000, f"Triangle count {triangles} outside required range"

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_animations=False,
    export_yup=True,
)

print(f"PRESS_TRIANGLES={triangles}")
print(
    "PRESS_BOUNDS="
    f"X[{bmin.x:.4f},{bmax.x:.4f}] "
    f"Y[{bmin.y:.4f},{bmax.y:.4f}] "
    f"Z[{bmin.z:.4f},{bmax.z:.4f}]"
)
print(f"PRESS_GLB={OUTPUT}")
