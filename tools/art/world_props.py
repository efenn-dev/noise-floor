"""Deterministic low-poly town and countryside props for Noise Floor.

Every export is built independently on :mod:`kit`, in metres, with the useful/front side
facing Blender -Y.  ``finish`` recentres the result, stands it on the collision-box floor,
checks the bounds and triangle budget, and exports ``assets/models/<id>.glb``.

Run one prop, all props, or the review contact sheet with Blender 5.1::

    blender.exe -b --factory-startup --python tools/art/world_props.py -- store_shelf
    blender.exe -b --factory-startup --python tools/art/world_props.py -- all
    blender.exe -b --factory-startup --python tools/art/world_props.py -- contact

The contact sheet imports the already-exported GLBs, gives every prop the same visual card
size, and renders a labelled 1500 px JPEG at ``tools/art/world_props_contact.jpg``.
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
CONTACT_PATH = Path(__file__).with_name("world_props_contact.jpg")

ALLOWED_MATERIALS = {
    "Prop Metal", "Prop Painted Metal", "Prop Rust", "Prop Wood", "Prop Concrete",
    "Prop Plastic", "Prop Rubber", "Prop Glass", "Prop Cardboard", "Prop Fabric",
    "Prop Hay", "Prop Leaves", "Prop Bark", "Prop Rock", "Prop Label", "Prop Screen",
}


def m(name: str, color: tuple[float, float, float], metallic: float = 0.0,
      roughness: float = 0.78, emission: float = 0.0):
    """Make one of the deliberately small, game-recognised prop material set."""
    assert name in ALLOWED_MATERIALS, f"Material is not in the approved prop palette: {name}"
    return material(name, color, metallic, roughness, emission)


def cone(name: str, radius1: float, radius2: float, depth: float,
         location: tuple[float, float, float], material_, vertices: int = 10,
         rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2,
                                    depth=depth, end_fill_type="NGON", location=location,
                                    rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


def torus(name: str, major_radius: float, minor_radius: float,
          location: tuple[float, float, float], material_, major_segments: int = 12,
          minor_segments: int = 4,
          rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=major_segments, minor_segments=minor_segments,
                                    major_radius=major_radius, minor_radius=minor_radius,
                                    location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


def ico(name: str, radius: float, location: tuple[float, float, float], material_,
        scale: tuple[float, float, float] = (1.0, 1.0, 1.0), subdivisions: int = 1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material_)
    return obj


def tube_between(name: str, a: tuple[float, float, float], b: tuple[float, float, float],
                 radius: float, material_, vertices: int = 8):
    """Straight low-poly tube between two arbitrary points."""
    av, bv = Vector(a), Vector(b)
    delta = bv - av
    obj = cylinder(name, radius, delta.length, tuple((av + bv) / 2), material_, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def cone_between(name: str, a: tuple[float, float, float], b: tuple[float, float, float],
                 radius1: float, radius2: float, material_, vertices: int = 6):
    """Tapered solid blade or branch between arbitrary points."""
    av, bv = Vector(a), Vector(b)
    delta = bv - av
    obj = cone(name, radius1, radius2, delta.length, tuple((av + bv) / 2), material_, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def poly_tube(name: str, points: list[tuple[float, float, float]], radius: float, material_,
              resolution: int = 1):
    """A solid polyline tube, converted to mesh so kit.finish can merge it."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    curve.resolution_v = max(0, resolution)
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material_)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return obj


def extrude_x(name: str, x0: float, x1: float, profile: list[tuple[float, float]], material_):
    """Extrude a closed (Y, Z) profile along X."""
    verts = [(x, y, z) for x in (x0, x1) for y, z in profile]
    n = len(profile)
    faces: list[tuple[int, ...]] = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def frustum_box(name: str, bottom: tuple[float, float], top: tuple[float, float], height: float,
                z0: float, material_):
    """Eight-vertex rectangular frustum; dimensions are (width X, depth Y)."""
    bw, bd = bottom
    tw, td = top
    verts = [(-bw / 2, -bd / 2, z0), (bw / 2, -bd / 2, z0),
             (bw / 2, bd / 2, z0), (-bw / 2, bd / 2, z0),
             (-tw / 2, -td / 2, z0 + height), (tw / 2, -td / 2, z0 + height),
             (tw / 2, td / 2, z0 + height), (-tw / 2, td / 2, z0 + height)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def bottle(name: str, x: float, y: float, z: float, body_h: float, color_mat, scale: float = 1.0):
    r = 0.035 * scale
    cylinder(f"{name}_Body", r, body_h, (x, y, z + body_h / 2), color_mat, 6)
    cylinder(f"{name}_Neck", r * 0.48, body_h * 0.24,
             (x, y, z + body_h + body_h * 0.12), color_mat, 6)
    cylinder(f"{name}_Cap", r * 0.58, 0.018 * scale,
             (x, y, z + body_h * 1.25), color_mat, 6)


def build_store_shelf() -> None:
    steel = m("Prop Painted Metal", (0.26, 0.31, 0.27), 0.5, 0.66)
    metal = m("Prop Metal", (0.36, 0.39, 0.38), 0.82, 0.48)
    cardboard = m("Prop Cardboard", (0.56, 0.34, 0.15), 0.0, 0.9)
    plastic = m("Prop Plastic", (0.62, 0.08, 0.055), 0.0, 0.62)
    glass = m("Prop Glass", (0.08, 0.30, 0.25), 0.05, 0.25)
    label = m("Prop Label", (0.92, 0.70, 0.16), 0.0, 0.58)

    box("Base", (1.94, 0.84, 0.12), (0.0, 0.0, 0.06), steel, 0.025)
    box("Centre_Back", (1.90, 0.055, 1.50), (0.0, 0.0, 0.83), steel, 0.012)
    for x in (-0.94, 0.94):
        box(f"End_Post_{x}", (0.055, 0.84, 1.62), (x, 0.0, 0.86), metal, 0.012)
    levels = (0.18, 0.55, 0.92, 1.29)
    for side in (-1, 1):
        y = side * 0.215
        for row, z in enumerate(levels):
            box(f"Shelf_{side}_{row}", (1.86, 0.37, 0.035), (0.0, y, z), metal, 0.008)
            box(f"Lip_{side}_{row}", (1.86, 0.025, 0.065),
                (0.0, side * 0.397, z + 0.035), steel, 0.005)
            stock_y = side * 0.26
            base_z = z + 0.025
            if row % 3 == 0:
                for i in range(7):
                    x = -0.72 + i * 0.24
                    cylinder(f"Can_{side}_{row}_{i}", 0.052, 0.16, (x, stock_y, base_z + 0.08),
                             label if i % 3 else plastic, 6)
            elif row % 3 == 1:
                for i in range(5):
                    x = -0.64 + i * 0.32
                    h = 0.22 + 0.03 * (i % 2)
                    box(f"Carton_{side}_{row}_{i}", (0.14, 0.16, h),
                        (x, stock_y, base_z + h / 2), cardboard,
                        rotation=(0.0, 0.0, deg((i % 3 - 1) * 2)))
                    box(f"Carton_Label_{side}_{row}_{i}", (0.095, 0.012, 0.08),
                        (x, stock_y - side * 0.087, base_z + h * 0.58), label)
            else:
                for i in range(6):
                    bottle(f"Bottle_{side}_{row}_{i}", -0.64 + i * 0.255, stock_y,
                           base_z, 0.18, glass if i % 2 else plastic, 0.9)
    box("Top_Cap", (1.98, 0.88, 0.07), (0.0, 0.0, 1.665), steel, 0.018)


def build_hardware_shelf() -> None:
    orange = m("Prop Painted Metal", (0.92, 0.29, 0.035), 0.42, 0.6)
    metal = m("Prop Metal", (0.30, 0.33, 0.34), 0.8, 0.52)
    cardboard = m("Prop Cardboard", (0.52, 0.31, 0.14), 0.0, 0.9)
    plastic = m("Prop Plastic", (0.10, 0.17, 0.19), 0.0, 0.66)
    label = m("Prop Label", (0.86, 0.82, 0.68), 0.0, 0.55)
    fabric = m("Prop Fabric", (0.53, 0.36, 0.15), 0.0, 0.92)

    for x in (-0.94, 0.94):
        for y in (-0.25, 0.25):
            box(f"Upright_{x}_{y}", (0.07, 0.07, 1.96), (x, y, 0.98), orange, 0.012)
        for z in (0.22, 0.75, 1.28, 1.92):
            box(f"Cross_{x}_{z}", (0.08, 0.56, 0.08), (x, 0.0, z), orange, 0.008)
    for row, z in enumerate((0.18, 0.70, 1.23, 1.76)):
        box(f"Shelf_{row}", (1.90, 0.52, 0.06), (0.0, 0.0, z), metal, 0.01)

    # Paint tins low, toolboxes and a rope coil at hand height, cartons up high.
    for i, x in enumerate((-0.68, -0.35, -0.02, 0.31, 0.64)):
        cylinder(f"Paint_Can_{i}", 0.12, 0.25, (x, -0.07, 0.335), metal, 12, bevel=0.008)
        box(f"Paint_Label_{i}", (0.16, 0.018, 0.10), (x, -0.185, 0.34), label, 0.004)
        torus(f"Paint_Handle_{i}", 0.105, 0.009, (x, -0.07, 0.46), metal, 10, 3,
              rotation=(deg(90), 0.0, 0.0))
    for i, x in enumerate((-0.55, 0.25)):
        box(f"Toolbox_{i}", (0.50, 0.34, 0.22), (x, -0.02, 0.84), plastic, 0.025)
        box(f"Toolbox_Latch_{i}", (0.10, 0.025, 0.06), (x, -0.202, 0.86), metal, 0.006)
        box(f"Toolbox_Handle_{i}", (0.22, 0.055, 0.05), (x, -0.02, 0.985), metal, 0.01)
    for j, r in enumerate((0.19, 0.14, 0.09)):
        torus(f"Rope_Coil_{j}", r, 0.025, (0.68, -0.17 - j * 0.003, 0.92), fabric,
              14, 4, rotation=(deg(90), 0.0, 0.0))
    for i, (x, w, h) in enumerate(((-0.58, 0.45, 0.34), (-0.10, 0.42, 0.42),
                                    (0.36, 0.43, 0.30), (0.70, 0.22, 0.38))):
        box(f"Hardware_Box_{i}", (w, 0.40, h), (x, 0.02, 1.26 + h / 2), cardboard, 0.012)
        box(f"Box_Label_{i}", (w * 0.55, 0.014, 0.11), (x, -0.188, 1.31 + h / 2), label, 0.003)


def build_checkout_counter() -> None:
    painted = m("Prop Painted Metal", (0.18, 0.32, 0.28), 0.38, 0.68)
    metal = m("Prop Metal", (0.38, 0.41, 0.40), 0.82, 0.45)
    rubber = m("Prop Rubber", (0.025, 0.03, 0.028), 0.0, 0.88)
    plastic = m("Prop Plastic", (0.12, 0.13, 0.13), 0.0, 0.64)
    screen = m("Prop Screen", (0.05, 0.42, 0.34), 0.05, 0.26, 0.16)
    label = m("Prop Label", (0.90, 0.20, 0.08), 0.0, 0.55)
    cardboard = m("Prop Cardboard", (0.68, 0.48, 0.18), 0.0, 0.88)

    box("Counter_Body", (1.74, 0.68, 0.76), (0.0, 0.02, 0.38), painted, 0.035)
    box("Counter_Toe", (1.60, 0.58, 0.10), (0.0, 0.06, 0.05), rubber, 0.015)
    box("Worktop", (1.78, 0.73, 0.055), (0.0, -0.01, 0.795), metal, 0.012)
    box("Conveyor", (0.95, 0.48, 0.035), (-0.36, -0.02, 0.832), rubber, 0.012)
    for x in (-0.80, 0.10):
        cylinder(f"Conveyor_Roller_{x}", 0.035, 0.48, (x, -0.02, 0.84), metal, 10,
                 rotation=(deg(90), 0.0, 0.0))
    # Register is kept under the 1.05 m collision height.
    box("Register", (0.40, 0.35, 0.16), (0.58, 0.08, 0.90), plastic, 0.025)
    box("Register_Screen", (0.24, 0.025, 0.13), (0.58, -0.108, 0.945), screen, 0.008,
        rotation=(deg(-8), 0.0, 0.0))
    box("Receipt", (0.13, 0.16, 0.012), (0.63, 0.06, 1.002), label, 0.002)
    box("Scanner", (0.22, 0.20, 0.025), (0.18, -0.04, 0.842), screen, 0.006)
    # Front candy rack, deliberately bold enough to read at first-person distance.
    box("Candy_Rack", (0.78, 0.12, 0.48), (0.25, -0.30, 0.45), metal, 0.012)
    for row in range(3):
        box(f"Candy_Shelf_{row}", (0.74, 0.11, 0.025),
            (0.25, -0.31, 0.28 + row * 0.16), metal, 0.004)
        for col in range(5):
            x = -0.03 + col * 0.14
            box(f"Candy_{row}_{col}", (0.095, 0.035, 0.11),
                (x, -0.35, 0.34 + row * 0.16), label if (row + col) % 2 else cardboard, 0.006,
                rotation=(deg(-5), 0.0, deg((col % 3 - 1) * 3)))


def build_pharmacy_counter() -> None:
    painted = m("Prop Painted Metal", (0.76, 0.80, 0.76), 0.12, 0.52)
    metal = m("Prop Metal", (0.32, 0.36, 0.37), 0.78, 0.48)
    plastic = m("Prop Plastic", (0.14, 0.18, 0.22), 0.0, 0.62)
    label = m("Prop Label", (0.18, 0.48, 0.72), 0.0, 0.52)
    screen = m("Prop Screen", (0.08, 0.42, 0.55), 0.05, 0.24, 0.12)

    box("Counter", (1.95, 0.64, 0.84), (0.0, 0.01, 0.42), painted, 0.03)
    box("Toe_Kick", (1.82, 0.52, 0.10), (0.0, 0.06, 0.05), metal, 0.012)
    box("Raised_Top", (1.98, 0.68, 0.08), (0.0, -0.01, 0.88), painted, 0.018)
    box("Customer_Ledge", (1.92, 0.16, 0.08), (0.0, -0.27, 1.01), painted, 0.018)
    box("Pharmacy_Cross_H", (0.30, 0.014, 0.085), (-0.58, -0.318, 0.47), label, 0.008)
    box("Pharmacy_Cross_V", (0.085, 0.014, 0.30), (-0.58, -0.318, 0.47), label, 0.008)
    box("Register", (0.38, 0.30, 0.13), (0.57, 0.07, 0.985), plastic, 0.022)
    box("Screen", (0.23, 0.025, 0.12), (0.57, -0.095, 1.02), screen, 0.006)
    for i, x in enumerate((-0.62, -0.45, -0.28, -0.11)):
        cylinder(f"Pill_Bottle_{i}", 0.045, 0.13 + 0.015 * (i % 2),
                 (x, -0.02, 0.985), plastic, 10, bevel=0.006)
        cylinder(f"Pill_Cap_{i}", 0.05, 0.025, (x, -0.02, 1.065 + 0.015 * (i % 2)),
                 label, 10)


def build_police_desk() -> None:
    wood = m("Prop Wood", (0.30, 0.20, 0.12), 0.0, 0.82)
    metal = m("Prop Metal", (0.24, 0.27, 0.28), 0.76, 0.52)
    plastic = m("Prop Plastic", (0.10, 0.12, 0.12), 0.0, 0.68)
    screen = m("Prop Screen", (0.05, 0.18, 0.20), 0.05, 0.22, 0.08)
    label = m("Prop Label", (0.82, 0.78, 0.62), 0.0, 0.66)
    fabric = m("Prop Fabric", (0.13, 0.20, 0.27), 0.0, 0.88)

    box("Desk_Top", (1.55, 0.74, 0.075), (0.0, 0.0, 0.73), wood, 0.018)
    for x in (-0.61, 0.61):
        box(f"Pedestal_{x}", (0.30, 0.62, 0.68), (x, 0.03, 0.34), metal, 0.022)
        for z in (0.18, 0.39, 0.60):
            box(f"Drawer_{x}_{z}", (0.28, 0.025, 0.16), (x, -0.294, z), metal, 0.006)
            box(f"Handle_{x}_{z}", (0.11, 0.018, 0.018), (x, -0.315, z), plastic, 0.004)
    # Chunky old CRT, facing the person at the front (-Y).
    box("Monitor", (0.48, 0.34, 0.38), (0.20, 0.13, 0.96), plastic, 0.045)
    box("Monitor_Screen", (0.34, 0.025, 0.25), (0.20, -0.052, 0.98), screen, 0.03)
    box("Monitor_Base", (0.30, 0.26, 0.05), (0.20, 0.08, 0.775), plastic, 0.012)
    box("Keyboard", (0.52, 0.19, 0.035), (0.12, -0.20, 0.79), plastic, 0.008,
        rotation=(0.0, 0.0, deg(-3)))
    for i in range(3):
        box(f"Paper_{i}", (0.32, 0.22, 0.008), (-0.46 + i * 0.025, -0.10 + i * 0.018,
                                                   0.78 + i * 0.009), label, 0.002,
            rotation=(0.0, 0.0, deg(-8 + i * 5)))
    # Bent-arm desk lamp.
    cylinder("Lamp_Base", 0.11, 0.035, (-0.50, 0.17, 0.785), metal, 12)
    tube_between("Lamp_Arm_A", (-0.50, 0.17, 0.80), (-0.45, 0.16, 1.08), 0.018, metal)
    tube_between("Lamp_Arm_B", (-0.45, 0.16, 1.08), (-0.34, 0.04, 1.15), 0.018, metal)
    cone("Lamp_Shade", 0.095, 0.045, 0.13, (-0.31, -0.005, 1.11), metal, 10,
         rotation=(deg(55), 0.0, deg(-35)))
    # Chair tucked beneath the front edge.
    box("Chair_Seat", (0.46, 0.34, 0.07), (0.0, -0.23, 0.47), fabric, 0.025)
    box("Chair_Back", (0.50, 0.08, 0.43), (0.0, -0.32, 0.70), fabric, 0.035,
        rotation=(deg(-6), 0.0, 0.0))
    cylinder("Chair_Column", 0.035, 0.38, (0.0, -0.20, 0.25), metal, 10)
    for i, angle in enumerate(range(0, 360, 72)):
        a = deg(angle)
        tube_between(f"Chair_Foot_{i}", (0.0, -0.20, 0.12),
                     (math.cos(a) * 0.24, -0.20 + math.sin(a) * 0.18, 0.08), 0.018, metal)


def build_gun_locker() -> None:
    steel = m("Prop Painted Metal", (0.28, 0.31, 0.30), 0.6, 0.66)
    metal = m("Prop Metal", (0.12, 0.14, 0.14), 0.82, 0.48)
    wood = m("Prop Wood", (0.30, 0.17, 0.08), 0.0, 0.82)
    rust = m("Prop Rust", (0.32, 0.09, 0.025), 0.25, 0.9)

    box("Locker_Case", (0.96, 0.34, 1.86), (0.0, 0.03, 0.93), steel, 0.018)
    box("Interior_Shadow", (0.43, 0.025, 1.72), (0.23, -0.155, 0.95), metal, 0.006)
    # Closed left door, right door yawed just enough to reveal the rifle without escaping 0.45 m.
    box("Left_Door", (0.45, 0.035, 1.76), (-0.245, -0.165, 0.95), steel, 0.012)
    box("Left_Handle", (0.035, 0.045, 0.18), (-0.06, -0.205, 0.98), metal, 0.006)
    box("Right_Door_Ajar", (0.43, 0.035, 1.76), (0.275, -0.17, 0.95), steel, 0.012,
        rotation=(0.0, 0.0, deg(-7)))
    for side, x in (("L", -0.245), ("R", 0.275)):
        for row in range(4):
            box(f"Vent_{side}_{row}", (0.20, 0.014, 0.025), (x, -0.19, 1.52 + row * 0.065), metal, 0.003)
    # Rifle silhouette: stock, receiver, long barrel and front sight.
    box("Rifle_Stock", (0.14, 0.07, 0.48), (0.20, -0.19, 0.43), wood, 0.025,
        rotation=(0.0, deg(-8), 0.0))
    box("Rifle_Action", (0.12, 0.075, 0.34), (0.16, -0.195, 0.82), metal, 0.015,
        rotation=(0.0, deg(-8), 0.0))
    tube_between("Rifle_Barrel", (0.13, -0.195, 0.96), (0.02, -0.195, 1.62), 0.018, metal, 8)
    box("Rifle_Sight", (0.025, 0.075, 0.055), (0.02, -0.195, 1.62), rust, 0.004)


def build_gas_pump() -> None:
    painted = m("Prop Painted Metal", (0.58, 0.12, 0.06), 0.52, 0.6)
    metal = m("Prop Metal", (0.30, 0.33, 0.34), 0.82, 0.46)
    rubber = m("Prop Rubber", (0.018, 0.022, 0.021), 0.0, 0.9)
    screen = m("Prop Screen", (0.10, 0.32, 0.36), 0.06, 0.2, 0.1)
    label = m("Prop Label", (0.88, 0.84, 0.68), 0.0, 0.55)
    plastic = m("Prop Plastic", (0.08, 0.09, 0.09), 0.0, 0.62)

    box("Plinth", (0.76, 0.48, 0.14), (0.0, 0.0, 0.07), metal, 0.025)
    box("Pump_Body", (0.70, 0.46, 1.52), (0.0, 0.0, 0.88), painted, 0.055)
    box("Top_Cap", (0.76, 0.50, 0.16), (0.0, 0.0, 1.70), metal, 0.035)
    box("Face_Recess", (0.56, 0.035, 0.58), (0.0, -0.247, 1.29), plastic, 0.018)
    box("Display", (0.42, 0.018, 0.19), (0.0, -0.272, 1.42), screen, 0.01)
    box("Price_Panel", (0.42, 0.018, 0.16), (0.0, -0.273, 1.18), label, 0.008)
    for i in range(3):
        box(f"Grade_Button_{i}", (0.10, 0.025, 0.055), (-0.14 + i * 0.14, -0.278, 1.02),
            label if i == 1 else metal, 0.01)
    # Hose hangs on the viewer's right side; nozzle rests high on that side.
    poly_tube("Fuel_Hose", [(0.34, -0.02, 1.52), (0.43, -0.02, 1.30),
                             (0.43, -0.10, 0.58), (0.31, -0.20, 0.35),
                             (0.26, -0.22, 0.70), (0.36, -0.22, 1.18)], 0.025, rubber)
    box("Nozzle_Grip", (0.10, 0.07, 0.27), (0.36, -0.22, 1.29), plastic, 0.018,
        rotation=(0.0, deg(-12), 0.0))
    tube_between("Nozzle_Spout", (0.34, -0.22, 1.40), (0.27, -0.22, 1.55), 0.016, metal, 8)
    box("Hose_Hook", (0.08, 0.08, 0.12), (0.37, 0.0, 1.49), metal, 0.012)


def build_dumpster() -> None:
    green = m("Prop Painted Metal", (0.08, 0.25, 0.13), 0.52, 0.76)
    metal = m("Prop Metal", (0.24, 0.27, 0.26), 0.8, 0.56)
    rust = m("Prop Rust", (0.34, 0.09, 0.025), 0.25, 0.9)
    rubber = m("Prop Rubber", (0.025, 0.028, 0.025), 0.0, 0.9)

    frustum_box("Dumpster_Body", (1.72, 0.88), (1.86, 1.00), 0.78, 0.14, green)
    box("Bottom_Skid", (1.65, 0.78, 0.14), (0.0, 0.0, 0.07), metal, 0.02)
    box("Top_Rim", (1.89, 1.04, 0.09), (0.0, 0.0, 0.965), metal, 0.015)
    for x in (-0.65, 0.0, 0.65):
        box(f"Front_Rib_{x}", (0.07, 0.045, 0.73), (x, -0.505, 0.62), metal, 0.01,
            rotation=(0.0, deg(x * 3), 0.0))
    for x in (-0.64, 0.64):
        box(f"Fork_Pocket_{x}", (0.34, 0.12, 0.16), (x, -0.40, 0.24), metal, 0.012)
        box(f"Pocket_Hole_{x}", (0.22, 0.13, 0.08), (x, -0.47, 0.24), rubber, 0.005)
    # Left lid closed; right lid rotated up around the rear edge.
    box("Lid_Closed", (0.91, 0.98, 0.06), (-0.46, 0.0, 1.035), green, 0.018)
    angle = deg(26)
    length = 0.92
    centre_y = 0.47 - math.cos(angle) * length / 2
    centre_z = 0.94 + math.sin(angle) * length / 2
    box("Lid_Half_Open", (0.91, length, 0.06), (0.46, centre_y, centre_z), green, 0.018,
        rotation=(angle, 0.0, 0.0))
    cylinder("Rear_Hinge", 0.035, 1.76, (0.0, 0.49, 0.96), metal, 10,
             rotation=(0.0, deg(90), 0.0))
    for i, x in enumerate((-0.72, 0.68)):
        box(f"Rust_Scar_{i}", (0.28, 0.015, 0.08), (x, -0.535, 0.48 + i * 0.18), rust, 0.004,
            rotation=(0.0, deg(12 - i * 22), deg(-5 + i * 8)))


def build_bench() -> None:
    wood = m("Prop Wood", (0.42, 0.23, 0.10), 0.0, 0.84)
    metal = m("Prop Metal", (0.10, 0.12, 0.12), 0.82, 0.55)
    rust = m("Prop Rust", (0.30, 0.075, 0.02), 0.24, 0.9)

    for i in range(4):
        y = -0.17 + i * 0.105
        box(f"Seat_Slat_{i}", (1.52, 0.09, 0.055), (0.0, y, 0.48), wood, 0.012)
    for i in range(4):
        z = 0.59 + i * 0.075
        box(f"Back_Slat_{i}", (1.52, 0.055, 0.055), (0.0, 0.25, z), wood, 0.012,
            rotation=(deg(-6), 0.0, 0.0))
    for x in (-0.58, 0.58):
        tube_between(f"Front_Leg_{x}", (x, -0.18, 0.04), (x, -0.13, 0.47), 0.035, metal, 10)
        tube_between(f"Rear_Leg_{x}", (x, 0.22, 0.04), (x, 0.18, 0.52), 0.035, metal, 10)
        tube_between(f"Back_Support_{x}", (x, 0.18, 0.46), (x, 0.28, 0.84), 0.03, metal, 10)
        poly_tube(f"Arm_{x}", [(x, -0.24, 0.58), (x, -0.24, 0.68),
                                (x, 0.16, 0.68)], 0.025, metal)
        cylinder(f"Foot_Bolt_{x}", 0.055, 0.025, (x, -0.18, 0.025), rust, 10)


def build_hay_bale_round() -> None:
    hay = m("Prop Hay", (0.72, 0.48, 0.12), 0.0, 0.94)
    fabric = m("Prop Fabric", (0.20, 0.12, 0.055), 0.0, 0.94)
    cylinder("Bale", 0.62, 1.30, (0.0, 0.0, 0.64), hay, 18,
             rotation=(0.0, deg(90), 0.0), bevel=0.025)
    for side in (-1, 1):
        x = side * 0.655
        for i, r in enumerate((0.13, 0.27, 0.42, 0.55)):
            torus(f"End_Strand_{side}_{i}", r, 0.012, (x, 0.0, 0.64), fabric,
                  16, 3, rotation=(0.0, deg(90), 0.0))
    for i, x in enumerate((-0.32, 0.0, 0.32)):
        torus(f"Bale_Band_{i}", 0.625, 0.012, (x, 0.0, 0.64), fabric,
              18, 3, rotation=(0.0, deg(90), 0.0))
    # A few raised straw lines break up the silhouette without alpha cards.
    for i in range(10):
        a = i * math.tau / 10
        tube_between(f"Strand_{i}", (-0.58, math.cos(a) * 0.61, 0.64 + math.sin(a) * 0.61),
                     (0.58, math.cos(a + 0.10) * 0.61, 0.64 + math.sin(a + 0.10) * 0.61),
                     0.008, hay, 6)


def build_hay_bale_square() -> None:
    hay = m("Prop Hay", (0.73, 0.49, 0.13), 0.0, 0.95)
    fabric = m("Prop Fabric", (0.20, 0.13, 0.06), 0.0, 0.95)
    box("Bale", (0.96, 0.47, 0.42), (0.0, 0.0, 0.22), hay, 0.055)
    for x in (-0.27, 0.27):
        box(f"Twine_Top_{x}", (0.025, 0.49, 0.018), (x, 0.0, 0.44), fabric, 0.004)
        box(f"Twine_Front_{x}", (0.025, 0.014, 0.43), (x, -0.235, 0.22), fabric, 0.004)
        box(f"Twine_Back_{x}", (0.025, 0.014, 0.43), (x, 0.235, 0.22), fabric, 0.004)
        box(f"Twine_Bottom_{x}", (0.025, 0.49, 0.018), (x, 0.0, 0.01), fabric, 0.004)
    for i in range(16):
        x = -0.43 + (i % 8) * 0.12
        z = 0.08 + (i // 8) * 0.22 + (i % 3) * 0.015
        box(f"Straw_End_{i}", (0.075, 0.010, 0.018), (x, -0.238, z), hay, 0.003,
            rotation=(0.0, deg((i % 3 - 1) * 8), deg((i % 5 - 2) * 4)))


def build_corn_row() -> None:
    leaves = m("Prop Leaves", (0.16, 0.34, 0.075), 0.0, 0.9)
    hay = m("Prop Hay", (0.70, 0.47, 0.08), 0.0, 0.9)
    fabric = m("Prop Fabric", (0.38, 0.20, 0.07), 0.0, 0.92)
    xs = (-0.58, -0.29, 0.0, 0.29, 0.58)
    for p, x in enumerate(xs):
        y = (-0.12, 0.12, -0.06, 0.10, -0.10)[p]
        h = (1.86, 1.98, 2.04, 1.92, 1.82)[p]
        cone(f"Stalk_{p}", 0.035, 0.018, h, (x, y, h / 2), leaves, 7)
        # Thick, tapered solid leaves; paired angles make the row readable from either side.
        for j, z in enumerate((0.48, 0.78, 1.08, 1.38, 1.62)):
            side = -1 if (p + j) % 2 else 1
            length = 0.25 + 0.025 * (j % 2)
            end = (x + side * length, y - 0.10 + 0.05 * (j % 3), z - 0.16)
            cone_between(f"Leaf_{p}_{j}", (x, y, z), end, 0.060, 0.006, leaves, 5)
        if p in (1, 2, 4):
            cob_z = 1.12 + 0.08 * (p % 2)
            cone(f"Cob_{p}", 0.075, 0.045, 0.28, (x + 0.06, y - 0.055, cob_z), hay, 9,
                 rotation=(deg(12), deg(18), 0.0))
            cone(f"Husk_{p}", 0.09, 0.02, 0.34, (x + 0.055, y - 0.045, cob_z - 0.03), leaves, 7,
                 rotation=(deg(12), deg(18), 0.0))
        for k in range(3):
            tube_between(f"Tassel_{p}_{k}", (x, y, h - 0.07),
                         (x + (k - 1) * 0.08, y + 0.025 * (k % 2), h + 0.01),
                         0.008, fabric, 5)


def build_farm_fence() -> None:
    wood = m("Prop Wood", (0.42, 0.27, 0.13), 0.0, 0.92)
    metal = m("Prop Metal", (0.22, 0.24, 0.23), 0.75, 0.62)
    for x in (-0.93, 0.93):
        box(f"Post_{x}", (0.13, 0.12, 1.18), (x, 0.0, 0.59), wood, 0.018)
        cone(f"Post_Cap_{x}", 0.078, 0.02, 0.12, (x, 0.0, 1.14), wood, 4,
             rotation=(0.0, 0.0, deg(45)))
    for i, z in enumerate((0.32, 0.65, 0.98)):
        box(f"Rail_{i}", (1.82, 0.075, 0.13), (0.0, -0.015, z), wood, 0.014,
            rotation=(0.0, deg((i - 1) * 1.5), 0.0))
        for x in (-0.89, 0.89):
            cylinder(f"Nail_{i}_{x}", 0.018, 0.010, (x, -0.052, z), metal, 10,
                     rotation=(deg(90), 0.0, 0.0))


def build_tractor_wreck() -> None:
    rust = m("Prop Rust", (0.34, 0.085, 0.025), 0.35, 0.88)
    painted = m("Prop Painted Metal", (0.25, 0.31, 0.10), 0.5, 0.78)
    metal = m("Prop Metal", (0.20, 0.22, 0.21), 0.82, 0.52)
    rubber = m("Prop Rubber", (0.025, 0.026, 0.022), 0.0, 0.94)
    fabric = m("Prop Fabric", (0.17, 0.13, 0.08), 0.0, 0.92)

    # Long side-on silhouette: nose at -X, large driven wheels at +X.
    box("Chassis", (2.75, 0.82, 0.26), (-0.05, 0.0, 0.92), metal, 0.045)
    box("Engine_Hood", (1.55, 0.88, 0.72), (-0.67, 0.0, 1.30), painted, 0.10,
        rotation=(0.0, deg(-2), 0.0))
    box("Nose_Grille", (0.10, 0.76, 0.55), (-1.47, 0.0, 1.30), metal, 0.035)
    for z in (1.14, 1.28, 1.42):
        box(f"Grille_Slot_{z}", (0.025, 0.58, 0.045), (-1.53, 0.0, z), rust, 0.008)
    box("Gearbox", (0.72, 0.92, 0.75), (0.55, 0.0, 1.20), rust, 0.085)
    box("Rear_Fender", (1.32, 1.70, 0.16), (0.88, 0.0, 1.72), painted, 0.08)
    box("Seat_Base", (0.42, 0.45, 0.14), (0.45, 0.0, 1.82), metal, 0.025)
    box("Seat", (0.48, 0.44, 0.12), (0.43, -0.02, 1.96), fabric, 0.045,
        rotation=(0.0, deg(-5), 0.0))
    box("Seat_Back", (0.12, 0.48, 0.52), (0.68, 0.02, 2.12), fabric, 0.045,
        rotation=(0.0, deg(-8), 0.0))
    tube_between("Steering_Column", (0.05, 0.0, 1.62), (0.25, 0.0, 2.05), 0.025, metal, 10)
    torus("Steering_Wheel", 0.18, 0.025, (0.25, 0.0, 2.08), metal, 14, 4,
          rotation=(0.0, deg(65), 0.0))

    # Wheels are deliberately part of the static merged prop, not vehicle wheel nodes.
    wheel_specs = ((0.92, 0.78, 0.34), (-1.08, 0.46, 0.26))
    for axle, radius, tread in wheel_specs:
        for side in (-1, 1):
            y = side * (0.70 if axle > 0 else 0.58)
            cylinder(f"Tyre_{axle}_{side}", radius, tread, (axle, y, radius), rubber, 18,
                     rotation=(deg(90), 0.0, 0.0), bevel=0.035)
            cylinder(f"Rim_{axle}_{side}", radius * 0.48, tread + 0.02,
                     (axle, y - side * 0.01, radius), rust, 14,
                     rotation=(deg(90), 0.0, 0.0), bevel=0.018)
            cylinder(f"Hub_{axle}_{side}", radius * 0.18, tread + 0.045,
                     (axle, y - side * 0.025, radius), metal, 12,
                     rotation=(deg(90), 0.0, 0.0))
            for lug in range(8):
                a = lug * math.tau / 8
                tx = axle + math.cos(a) * radius * 0.76
                tz = radius + math.sin(a) * radius * 0.76
                box(f"Tread_{axle}_{side}_{lug}", (0.16, tread + 0.05, 0.10),
                    (tx, y, tz), rubber, 0.015, rotation=(0.0, deg(-math.degrees(a)), 0.0))
    # Bent exhaust with a soot cap, plus a single headlamp.
    cylinder("Exhaust", 0.055, 1.26, (-0.52, 0.24, 2.00), rust, 10)
    cylinder("Exhaust_Cap", 0.075, 0.06, (-0.52, 0.24, 2.64), metal, 10)
    cylinder("Headlamp", 0.12, 0.10, (-1.49, -0.32, 1.54), metal, 12,
             rotation=(0.0, deg(90), 0.0), bevel=0.018)


def build_water_trough() -> None:
    metal = m("Prop Metal", (0.48, 0.53, 0.54), 0.82, 0.54)
    painted = m("Prop Painted Metal", (0.28, 0.32, 0.31), 0.52, 0.72)
    rubber = m("Prop Rubber", (0.045, 0.07, 0.07), 0.0, 0.78)

    box("Trough_Bottom", (1.78, 0.48, 0.07), (0.0, 0.0, 0.27), metal, 0.025)
    for side in (-1, 1):
        box(f"Long_Wall_{side}", (1.90, 0.07, 0.40), (0.0, side * 0.26, 0.45), metal, 0.035,
            rotation=(deg(side * 5), 0.0, 0.0))
    for x in (-0.92, 0.92):
        box(f"End_Wall_{x}", (0.07, 0.54, 0.40), (x, 0.0, 0.45), metal, 0.035)
    box("Water", (1.73, 0.44, 0.025), (0.0, 0.0, 0.55), rubber, 0.008)
    for x in (-0.65, 0.65):
        for y in (-0.20, 0.20):
            box(f"Leg_{x}_{y}", (0.09, 0.09, 0.26), (x, y, 0.13), painted, 0.012)
        box(f"Foot_{x}", (0.38, 0.52, 0.06), (x, 0.0, 0.03), painted, 0.012)
    cylinder("Drain", 0.055, 0.04, (0.70, -0.295, 0.35), painted, 10,
             rotation=(deg(90), 0.0, 0.0))


def build_pine(height: float, radius: float, layers: int) -> None:
    leaves = m("Prop Leaves", (0.055, 0.19, 0.085), 0.0, 0.92)
    bark = m("Prop Bark", (0.18, 0.095, 0.045), 0.0, 0.95)
    trunk_h = height * 0.72
    cone("Trunk", radius * 0.105, radius * 0.045, trunk_h,
         (0.0, 0.0, trunk_h / 2), bark, 9)
    cylinder("Root_Flare", radius * 0.15, height * 0.035,
             (0.0, 0.0, height * 0.0175), bark, 9)
    base_z = height * 0.23
    usable = height * 0.73
    for i in range(layers):
        t = i / max(1, layers - 1)
        z = base_z + t * usable * 0.86
        r = radius * (0.94 - 0.70 * t)
        depth = usable * (0.34 - 0.08 * t)
        cone(f"Needle_Layer_{i}", r, r * 0.08, depth,
             ((i % 2) * 0.05 - 0.025, ((i + 1) % 2) * 0.05 - 0.025, z + depth * 0.34),
             leaves, 10, rotation=(0.0, 0.0, deg(i * 17)))
    cone("Tree_Tip", radius * 0.28, 0.0, height * 0.24,
         (0.0, 0.0, height * 0.88), leaves, 9)


def build_pine_tree() -> None:
    build_pine(8.70, 1.92, 8)


def build_pine_tree_small() -> None:
    build_pine(5.30, 1.24, 7)


def build_bush() -> None:
    leaves = m("Prop Leaves", (0.10, 0.30, 0.075), 0.0, 0.93)
    bark = m("Prop Bark", (0.16, 0.085, 0.04), 0.0, 0.95)
    for i, x in enumerate((-0.26, -0.10, 0.08, 0.26)):
        tube_between(f"Twig_{i}", (x * 0.35, 0.0, 0.03),
                     (x, (-1 if i % 2 else 1) * 0.20, 0.64 + 0.05 * (i % 3)),
                     0.025, bark, 7)
    clumps = [((-0.34, -0.16, 0.44), 0.50, (0.78, 0.86, 0.68)),
              ((0.30, -0.12, 0.47), 0.48, (0.78, 0.88, 0.68)),
              ((-0.20, 0.25, 0.51), 0.46, (0.78, 0.88, 0.70)),
              ((0.30, 0.24, 0.50), 0.45, (0.78, 0.90, 0.69)),
              ((0.0, 0.0, 0.62), 0.52, (0.78, 0.86, 0.68))]
    for i, (loc, r, scale) in enumerate(clumps):
        ico(f"Leaf_Clump_{i}", r, loc, leaves, scale, 2)


def build_rock() -> None:
    rock = m("Prop Rock", (0.31, 0.30, 0.27), 0.05, 0.96)
    obj = ico("Boulder", 1.0, (0.0, 0.0, 0.48), rock, (0.70, 0.56, 0.47), 3)
    # Deterministic vertex displacement keeps it faceted and avoids a smooth-sphere silhouette.
    for i, vert in enumerate(obj.data.vertices):
        co = vert.co
        factor = 1.0 + 0.10 * math.sin(i * 2.37) + 0.045 * math.cos(i * 0.91)
        co.x *= factor
        co.y *= 1.0 + 0.07 * math.sin(i * 1.33)
        co.z *= 1.0 + 0.06 * math.cos(i * 1.71)
        if co.z < -0.31:
            co.z = -0.31
    obj.data.update()
    # Three coarse chips make asymmetry obvious from the contact-sheet angle.
    for i, (loc, scale) in enumerate((((-0.45, -0.20, 0.62), (0.24, 0.17, 0.20)),
                                      ((0.38, -0.10, 0.31), (0.28, 0.19, 0.16)),
                                      ((0.12, 0.34, 0.55), (0.20, 0.18, 0.24)))):
        ico(f"Rock_Lobe_{i}", 1.0, loc, rock, scale, 1)


def build_guardrail() -> None:
    metal = m("Prop Metal", (0.52, 0.55, 0.54), 0.86, 0.5)
    rust = m("Prop Rust", (0.31, 0.075, 0.02), 0.28, 0.9)
    # Corrugated W profile in depth/height, seen from the road at -Y.
    profile = [(-0.045, 0.34), (-0.09, 0.39), (-0.045, 0.46), (-0.09, 0.53),
               (-0.045, 0.60), (0.025, 0.60), (-0.025, 0.53), (0.025, 0.46),
               (-0.025, 0.39), (0.025, 0.34)]
    extrude_x("W_Beam", -1.98, 1.98, profile, metal)
    for x in (-1.05, 1.05):
        box(f"Post_{x}", (0.11, 0.11, 0.76), (x, 0.05, 0.38), metal, 0.012)
        box(f"Post_Foot_{x}", (0.24, 0.24, 0.05), (x, 0.06, 0.025), rust, 0.01)
        for z in (0.43, 0.54):
            cylinder(f"Bolt_{x}_{z}", 0.035, 0.035, (x, -0.105, z), rust, 10,
                     rotation=(deg(90), 0.0, 0.0), bevel=0.004)
    for x in (-1.85, 1.85):
        cylinder(f"End_Bolt_{x}", 0.03, 0.032, (x, -0.105, 0.47), rust, 10,
                 rotation=(deg(90), 0.0, 0.0))


def build_concrete_barrier() -> None:
    concrete = m("Prop Concrete", (0.52, 0.51, 0.46), 0.0, 0.96)
    label = m("Prop Label", (0.83, 0.62, 0.10), 0.0, 0.66)
    metal = m("Prop Metal", (0.16, 0.17, 0.16), 0.74, 0.66)
    profile = [(-0.295, 0.0), (0.295, 0.0), (0.275, 0.18), (0.13, 0.52),
               (0.12, 0.83), (-0.12, 0.83), (-0.13, 0.52), (-0.275, 0.18)]
    extrude_x("Jersey_Barrier", -0.98, 0.98, profile, concrete)
    for x in (-0.72, 0.0, 0.72):
        box(f"Reflector_{x}", (0.12, 0.014, 0.075), (x, -0.285, 0.22), label, 0.008)
    for i, (x, z, angle) in enumerate(((-0.55, 0.48, -12), (0.38, 0.64, 8), (0.72, 0.31, -5))):
        box(f"Casting_Scar_{i}", (0.20, 0.012, 0.022), (x, -0.145, z), concrete, 0.003,
            rotation=(0.0, deg(angle), deg(angle)))
    for x in (-0.42, 0.42):
        cylinder(f"Form_Tie_{x}", 0.025, 0.012, (x, -0.287, 0.55), metal, 8,
                 rotation=(deg(90), 0.0, 0.0))


def build_road_sign() -> None:
    metal = m("Prop Metal", (0.22, 0.24, 0.24), 0.84, 0.5)
    painted = m("Prop Painted Metal", (0.83, 0.84, 0.79), 0.24, 0.5)
    label = m("Prop Label", (0.07, 0.09, 0.09), 0.0, 0.62)
    cylinder("Pole", 0.045, 2.62, (0.0, 0.0, 1.31), metal, 12)
    box("Pole_Foot", (0.22, 0.08, 0.06), (0.0, 0.0, 0.03), metal, 0.012)
    box("Sign_Back", (0.74, 0.055, 0.90), (0.0, 0.0, 2.15), metal, 0.022)
    box("Sign_Panel", (0.68, 0.025, 0.84), (0.0, -0.041, 2.15), painted, 0.016)
    # Four dark bars form a plain border, deliberately no written message.
    box("Border_Top", (0.66, 0.014, 0.035), (0.0, -0.058, 2.545), label, 0.005)
    box("Border_Bottom", (0.66, 0.014, 0.035), (0.0, -0.058, 1.755), label, 0.005)
    for x in (-0.315, 0.315):
        box(f"Border_Side_{x}", (0.035, 0.014, 0.82), (x, -0.058, 2.15), label, 0.005)
    for z in (1.88, 2.42):
        cylinder(f"Sign_Bolt_{z}", 0.022, 0.018, (0.0, -0.065, z), metal, 10,
                 rotation=(deg(90), 0.0, 0.0))


Builder = Callable[[], None]
SPECS: dict[str, tuple[tuple[float, float, float], int, Builder]] = {
    "store_shelf": ((2.0, 1.7, 0.9), 3000, build_store_shelf),
    "hardware_shelf": ((2.0, 2.0, 0.6), 3000, build_hardware_shelf),
    "checkout_counter": ((1.8, 1.05, 0.75), 3000, build_checkout_counter),
    "pharmacy_counter": ((2.0, 1.1, 0.7), 3000, build_pharmacy_counter),
    "police_desk": ((1.6, 1.2, 0.8), 3000, build_police_desk),
    "gun_locker": ((1.0, 1.9, 0.45), 3000, build_gun_locker),
    "gas_pump": ((0.9, 1.9, 0.55), 3000, build_gas_pump),
    "dumpster": ((1.9, 1.4, 1.1), 3000, build_dumpster),
    "bench": ((1.6, 0.85, 0.6), 3000, build_bench),
    "hay_bale_round": ((1.4, 1.3, 1.4), 3000, build_hay_bale_round),
    "hay_bale_square": ((1.0, 0.45, 0.5), 3000, build_hay_bale_square),
    "corn_row": ((2.0, 2.1, 0.7), 3000, build_corn_row),
    "farm_fence": ((2.0, 1.2, 0.12), 3000, build_farm_fence),
    "tractor_wreck": ((3.6, 2.7, 1.9), 6000, build_tractor_wreck),
    "water_trough": ((2.0, 0.65, 0.65), 3000, build_water_trough),
    "pine_tree": ((4.0, 9.0, 4.0), 6000, build_pine_tree),
    "pine_tree_small": ((2.6, 5.5, 2.6), 6000, build_pine_tree_small),
    "bush": ((1.4, 1.0, 1.4), 3000, build_bush),
    "rock": ((1.6, 0.9, 1.3), 3000, build_rock),
    "guardrail": ((4.0, 0.8, 0.35), 3000, build_guardrail),
    "concrete_barrier": ((2.0, 0.85, 0.6), 3000, build_concrete_barrier),
    "road_sign": ((0.75, 2.7, 0.12), 3000, build_road_sign),
}


def export_one(prop_id: str) -> Path:
    size, max_triangles, builder = SPECS[prop_id]
    reset()
    builder()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, f"{prop_id}: builder made no mesh geometry"
    used = sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material})
    unexpected = set(used) - ALLOWED_MATERIALS
    assert not unexpected, f"{prop_id}: unapproved material names: {sorted(unexpected)}"
    print(f"WORLD_PROP {prop_id}: materials={','.join(used)}")
    return finish(prop_id, size, max_triangles=max_triangles)


def look_at(obj, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_contact() -> None:
    missing = [prop_id for prop_id in SPECS if not (MODEL_DIR / f"{prop_id}.glb").exists()]
    if missing:
        raise FileNotFoundError(f"Export all props before rendering contact sheet: {', '.join(missing)}")
    reset()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 1040
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.quality = 92
    scene.render.filepath = str(CONTACT_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.032, 0.038)
    scene.view_settings.look = "AgX - Medium High Contrast"

    card_mat = material("Contact Card", (0.085, 0.10, 0.11), 0.0, 0.82)
    text_mat = material("Contact Text", (0.78, 0.84, 0.84), 0.0, 0.55, 0.25)
    cols, rows = 6, 4
    cell_w, cell_h = 3.25, 3.15
    ids = list(SPECS)
    for index, prop_id in enumerate(ids):
        col, row = index % cols, index // cols
        tx = (col - (cols - 1) / 2) * cell_w
        tz = ((rows - 1) / 2 - row) * cell_h
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / f"{prop_id}.glb"))
        imported = [obj for obj in bpy.context.scene.objects if obj not in before and obj.type == "MESH"]
        points = [obj.matrix_world @ Vector(corner) for obj in imported for corner in obj.bound_box]
        lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
        hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
        centre = (lo + hi) / 2
        extent = hi - lo
        scale = min(2.55 / max(extent.x, extent.y, 0.01), 2.15 / max(extent.z, 0.01))
        transform = (Matrix.Translation((tx, 0.0, tz + 0.18)) @
                     Matrix.Rotation(deg(10), 4, "X") @ Matrix.Rotation(deg(156), 4, "Z") @
                     Matrix.Scale(scale, 4) @ Matrix.Translation(-centre))
        for obj in imported:
            obj.matrix_world = transform @ obj.matrix_world
        box(f"Card_{prop_id}", (3.05, 0.035, 2.90), (tx, 1.18, tz), card_mat, 0.055)
        bpy.ops.object.text_add(location=(tx, -1.25, tz - 1.24), rotation=(deg(90), 0.0, 0.0))
        text_obj = bpy.context.object
        text_obj.name = f"Label_{prop_id}"
        text_obj.data.body = prop_id.replace("_", " ")
        text_obj.data.align_x = "CENTER"
        text_obj.data.align_y = "CENTER"
        text_obj.data.size = 0.25
        text_obj.data.extrude = 0.006
        text_obj.data.materials.append(text_mat)

    target = Vector((0.0, 0.0, 0.0))
    bpy.ops.object.camera_add(location=(0.0, -31.0, 0.0))
    camera = bpy.context.object
    look_at(camera, target)
    camera.data.type = "ORTHO"
    # Blender's orthographic scale is the horizontal span; 20.5 m keeps all six cards in frame.
    camera.data.ortho_scale = 20.5
    scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-6.0, -10.0, 10.0))
    key = bpy.context.object
    key.data.energy = 1450
    key.data.shape = "DISK"
    key.data.size = 8.0
    look_at(key, Vector((0.0, 0.0, 0.0)))
    bpy.ops.object.light_add(type="AREA", location=(8.0, -6.0, 2.0))
    fill = bpy.context.object
    fill.data.energy = 900
    fill.data.size = 7.0
    look_at(fill, Vector((0.0, 0.0, 0.0)))
    bpy.ops.object.light_add(type="AREA", location=(0.0, 4.0, 8.0))
    rim = bpy.context.object
    rim.data.energy = 1200
    rim.data.size = 6.0
    look_at(rim, Vector((0.0, 0.0, 0.0)))
    bpy.ops.render.render(write_still=True)
    print(f"WORLD_PROP contact: {CONTACT_PATH.relative_to(ROOT)}")


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    command = args[0] if args else "all"
    if command == "all":
        for prop_id in SPECS:
            export_one(prop_id)
    elif command == "contact":
        render_contact()
    elif command in SPECS:
        export_one(command)
    else:
        valid = ", ".join(["all", "contact", *SPECS])
        raise SystemExit(f"Unknown world prop '{command}'. Valid choices: {valid}")


if __name__ == "__main__":
    main()
