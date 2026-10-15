"""Deterministic F1 resource-node and extractor models for Noise Floor.

The models use :mod:`kit` conventions: metres, FRONT = Blender -Y, and every
export is independently reset, built, fitted to its collision box, and written
to ``assets/models/<id>.glb``.  Extractors have no input marking: they take their
resource from the node below/behind them.  Their orange part is always the item
output at the front.

Run one model, every model (one ID at a time is recommended on Emmitt's PC), or
the labelled review render::

    blender.exe -b --factory-startup --python tools/art/f1_models.py -- scrap_heap
    blender.exe -b --factory-startup --python tools/art/f1_models.py -- all
    blender.exe -b --factory-startup --python tools/art/f1_models.py -- contact

The contact sheet imports the eight exported GLBs and renders a 1500 px JPEG at
``tools/art/f1_models_contact.jpg``.  No randomness is used.
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, hazard_stripes, lamp, mat, material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
CONTACT_PATH = Path(__file__).with_name("f1_models_contact.jpg")

PROP_MATERIALS = {
    "Prop Metal", "Prop Painted Metal", "Prop Rust", "Prop Wood", "Prop Bark",
    "Prop Concrete", "Prop Rock", "Prop Rubber", "Prop Glass", "Prop Plastic",
    "Prop Fabric", "Prop Label",
}


def prop_mat(name: str, color: tuple[float, float, float], metallic: float = 0.0,
             roughness: float = 0.78, emission: float = 0.0):
    assert name in PROP_MATERIALS, f"Unapproved resource-node material: {name}"
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
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius,
                                         location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material_)
    return obj


def tube_between(name: str, a: tuple[float, float, float], b: tuple[float, float, float],
                 radius: float, material_, vertices: int = 8):
    av, bv = Vector(a), Vector(b)
    delta = bv - av
    obj = cylinder(name, radius, delta.length, tuple((av + bv) / 2), material_, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def scale_scene_z(factor: float) -> None:
    """Compress all current geometry vertically in world space, preserving rotations."""
    transform = Matrix.Diagonal((1.0, 1.0, factor, 1.0))
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.matrix_world = transform @ obj.matrix_world


def scale_scene_y(factor: float) -> None:
    """Compress all current geometry in depth in world space."""
    transform = Matrix.Diagonal((1.0, factor, 1.0, 1.0))
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.matrix_world = transform @ obj.matrix_world


def scale_scene_x(factor: float) -> None:
    """Compress all current geometry in width in world space."""
    transform = Matrix.Diagonal((factor, 1.0, 1.0, 1.0))
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.matrix_world = transform @ obj.matrix_world


def frustum(name: str, bottom: tuple[float, float], top: tuple[float, float], height: float,
            z0: float, location: tuple[float, float], material_):
    """Rectangular open-looking hopper body; dimensions are width X and depth Y."""
    bw, bd = bottom
    tw, td = top
    x, y = location
    verts = [(x - bw / 2, y - bd / 2, z0), (x + bw / 2, y - bd / 2, z0),
             (x + bw / 2, y + bd / 2, z0), (x - bw / 2, y + bd / 2, z0),
             (x - tw / 2, y - td / 2, z0 + height), (x + tw / 2, y - td / 2, z0 + height),
             (x + tw / 2, y + td / 2, z0 + height), (x - tw / 2, y + td / 2, z0 + height)]
    faces = [(0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5),
             (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def handwheel(name: str, location: tuple[float, float, float], material_, radius: float = 0.16,
              facing_front: bool = True):
    """Low-poly valve wheel, normally in the X/Z plane and visible from -Y."""
    rot = (deg(90), 0.0, 0.0) if facing_front else (0.0, deg(90), 0.0)
    torus(f"{name}_Rim", radius, radius * 0.10, location, material_, 12, 4, rot)
    x, y, z = location
    if facing_front:
        cylinder(f"{name}_Hub", radius * 0.22, 0.07, location, material_, 10, rot)
        box(f"{name}_Spoke_H", (radius * 1.7, 0.035, 0.025), location, material_)
        box(f"{name}_Spoke_V", (0.025, 0.035, radius * 1.7), location, material_)
    else:
        cylinder(f"{name}_Hub", radius * 0.22, 0.07, location, material_, 10, rot)
        box(f"{name}_Spoke_Y", (0.035, radius * 1.7, 0.025), location, material_)
        box(f"{name}_Spoke_Z", (0.035, 0.025, radius * 1.7), location, material_)


def build_scrap_heap() -> None:
    metal = prop_mat("Prop Metal", (0.25, 0.27, 0.26), 0.82, 0.56)
    painted = prop_mat("Prop Painted Metal", (0.19, 0.31, 0.29), 0.48, 0.74)
    rust = prop_mat("Prop Rust", (0.37, 0.095, 0.025), 0.28, 0.91)
    rubber = prop_mat("Prop Rubber", (0.025, 0.027, 0.024), 0.02, 0.93)
    plastic = prop_mat("Prop Plastic", (0.76, 0.70, 0.52), 0.0, 0.77)
    label = prop_mat("Prop Label", (0.78, 0.22, 0.055), 0.0, 0.63)

    # Broad, dark under-mound makes the prop read as one pile rather than scattered litter.
    ico("Compacted_Junk_Core", 1.0, (0.0, 0.10, 0.46), rust, (1.60, 1.28, 0.52), 2)
    for i, (loc, size, rot, mat_) in enumerate((
        ((-0.90, -0.35, 0.80), (1.35, 0.10, 0.58), (deg(10), deg(-17), deg(12)), painted),
        ((0.78, 0.15, 0.89), (1.50, 0.08, 0.52), (deg(-12), deg(20), deg(-18)), rust),
        ((0.00, 0.50, 1.12), (1.55, 0.09, 0.50), (deg(15), deg(-8), deg(6)), metal),
        ((-0.25, -0.12, 1.39), (1.25, 0.075, 0.42), (deg(-9), deg(12), deg(-10)), painted),
        ((1.17, -0.18, 0.49), (0.85, 0.075, 0.50), (deg(7), deg(-25), deg(22)), metal),
    )):
        box(f"Bent_Car_Panel_{i}", size, loc, mat_, 0.035, rot)
        # Raised crease gives each panel a crumpled sheet-metal read.
        box(f"Panel_Crease_{i}", (size[0] * 0.68, 0.035, 0.045),
            (loc[0], loc[1] - 0.06, loc[2]), rust if mat_ is not rust else metal, 0.008,
            rotation=(rot[0], rot[1], rot[2] + deg(7)))

    # A full wheel and detached hub are strong junkyard cues from long range.
    torus("Loose_Wheel_Tyre", 0.43, 0.12, (-1.23, -0.98, 0.55), rubber, 16, 5,
          rotation=(deg(90), 0.0, deg(-10)))
    cylinder("Loose_Wheel_Rim", 0.24, 0.09, (-1.23, -1.01, 0.55), metal, 12,
             rotation=(deg(90), 0.0, deg(-10)))
    cylinder("Loose_Wheel_Hub", 0.07, 0.12, (-1.23, -1.07, 0.55), rust, 10,
             rotation=(deg(90), 0.0, deg(-10)))

    # Fridge door is intentionally pale and rectangular against the rusty mound.
    box("Fridge_Door", (0.76, 0.10, 1.05), (0.62, -1.12, 0.72), plastic, 0.07,
        rotation=(deg(-4), deg(8), deg(-7)))
    box("Fridge_Door_Seal", (0.65, 0.025, 0.92), (0.62, -1.19, 0.72), rubber, 0.035,
        rotation=(deg(-4), deg(8), deg(-7)))
    box("Fridge_Handle", (0.08, 0.06, 0.44), (0.88, -1.25, 0.75), metal, 0.02,
        rotation=(deg(-4), deg(8), deg(-7)))
    box("Old_Sticker", (0.25, 0.018, 0.13), (0.48, -1.255, 0.98), label, 0.01,
        rotation=(deg(-4), deg(8), deg(-7)))

    # Pipes and crossed rebar break the top silhouette.
    for i, (a, b, radius, mat_) in enumerate((
        ((-1.25, 0.42, 0.55), (1.35, -0.12, 1.28), 0.075, rust),
        ((-0.55, 0.92, 0.55), (1.45, 0.46, 1.40), 0.065, metal),
        ((-1.40, 0.28, 0.42), (0.85, 1.18, 1.06), 0.035, rust),
        ((-0.75, -0.45, 0.48), (1.25, 0.70, 1.52), 0.032, rust),
        ((-1.30, 0.80, 0.40), (0.35, -0.30, 1.57), 0.030, metal),
    )):
        tube_between(f"Pipe_Rebar_{i}", a, b, radius, mat_, 8)
    for i, x in enumerate((-0.48, 0.15, 0.72)):
        box(f"Crumpled_Sheet_{i}", (0.72, 0.60, 0.055), (x, 0.87, 0.70 + i * 0.15),
            painted if i == 1 else rust, 0.025,
            rotation=(deg(18 - i * 9), deg(-14 + i * 11), deg(16 - i * 13)))
    scale_scene_z(0.95)


def build_well() -> None:
    concrete = prop_mat("Prop Concrete", (0.48, 0.47, 0.42), 0.0, 0.96)
    rock = prop_mat("Prop Rock", (0.30, 0.30, 0.28), 0.04, 0.98)
    wood = prop_mat("Prop Wood", (0.42, 0.25, 0.105), 0.0, 0.90)
    bark = prop_mat("Prop Bark", (0.20, 0.105, 0.045), 0.0, 0.96)
    metal = prop_mat("Prop Metal", (0.22, 0.24, 0.23), 0.76, 0.59)
    rust = prop_mat("Prop Rust", (0.31, 0.075, 0.022), 0.28, 0.91)
    rubber = prop_mat("Prop Rubber", (0.035, 0.028, 0.022), 0.0, 0.94)

    # Two offset courses leave a dark/open centre and clearly describe a circular well ring.
    for row, z in enumerate((0.16, 0.43, 0.70)):
        count = 12
        for i in range(count):
            a = (i + 0.5 * (row % 2)) * math.tau / count
            r = 0.61
            block = box(f"Ring_Block_{row}_{i}", (0.34, 0.23, 0.24),
                        (math.cos(a) * r, math.sin(a) * r, z),
                        concrete if (i + row) % 3 else rock, 0.035,
                        rotation=(0.0, 0.0, a + deg(90)))
            block.scale.x *= 1.0 + 0.04 * math.sin(i * 2.1 + row)
    cylinder("Dark_Well_Mouth", 0.49, 0.035, (0.0, 0.0, 0.83), rubber, 18)
    cylinder("Concrete_Lip", 0.75, 0.12, (0.0, 0.0, 0.80), concrete, 18, bevel=0.025)
    cylinder("Open_Mouth", 0.53, 0.14, (0.0, 0.0, 0.85), rubber, 18)

    # Lid planks are half slid and slightly cocked, exposing the black water opening.
    for i, y in enumerate((-0.16, 0.02, 0.20)):
        box(f"Lid_Plank_{i}", (0.92, 0.17, 0.075), (0.32, y - 0.22, 0.92 + 0.02 * i),
            wood, 0.018, rotation=(deg(-4), deg(8), deg(-11)))
    for x in (0.06, 0.57):
        box(f"Lid_Cleat_{x}", (0.09, 0.62, 0.065), (x, -0.20, 0.955), bark, 0.012,
            rotation=(deg(-4), deg(8), deg(-11)))

    # Traditional farm-well crank frame, pitched above the ring but inside 1.5 m.
    for x in (-0.66, 0.66):
        box(f"Frame_Post_{x}", (0.13, 0.15, 0.78), (x, 0.10, 1.08), wood, 0.018,
            rotation=(0.0, deg(-2 if x < 0 else 2), 0.0))
        box(f"Post_Foot_{x}", (0.24, 0.28, 0.08), (x, 0.10, 0.76), concrete, 0.016)
    cylinder("Crank_Axle", 0.055, 1.50, (0.0, 0.10, 1.39), metal, 12,
             rotation=(0.0, deg(90), 0.0))
    cylinder("Rope_Drum", 0.14, 0.34, (0.0, 0.10, 1.39), wood, 12,
             rotation=(0.0, deg(90), 0.0))
    cylinder("Rope", 0.018, 0.48, (0.0, 0.10, 1.12), rubber, 8)
    tube_between("Crank_Arm", (0.76, 0.10, 1.39), (0.76, -0.02, 1.18), 0.028, rust, 8)
    cylinder("Crank_Handle", 0.035, 0.19, (0.76, -0.11, 1.18), wood, 8,
             rotation=(deg(90), 0.0, 0.0))


def build_fuel_tanker() -> None:
    metal = prop_mat("Prop Metal", (0.23, 0.25, 0.24), 0.82, 0.56)
    painted = prop_mat("Prop Painted Metal", (0.43, 0.12, 0.065), 0.45, 0.79)
    rust = prop_mat("Prop Rust", (0.35, 0.075, 0.020), 0.30, 0.92)
    rubber = prop_mat("Prop Rubber", (0.020, 0.022, 0.020), 0.02, 0.94)
    glass = prop_mat("Prop Glass", (0.075, 0.17, 0.18), 0.10, 0.27)
    plastic = prop_mat("Prop Plastic", (0.72, 0.67, 0.48), 0.0, 0.80)
    label = prop_mat("Prop Label", (0.88, 0.62, 0.055), 0.0, 0.60)

    # Truck length is X so the whole rolled wreck fills the unusually wide node footprint.
    box("Bent_Chassis", (7.70, 0.34, 0.30), (0.0, 0.18, 0.38), rust, 0.065,
        rotation=(deg(4), deg(-2), deg(1)))
    # Tank axis X.  Its lowered, offset circular body makes the truck visibly lie on its side.
    cylinder("Fuel_Tank", 1.03, 5.18, (1.20, 0.08, 1.32), painted, 24,
             rotation=(0.0, deg(90), 0.0), bevel=0.035)
    for x in (-1.05, 0.45, 1.95, 3.38):
        torus(f"Tank_Hoop_{x}", 1.035, 0.055, (x, 0.08, 1.32), metal, 18, 4,
              rotation=(0.0, deg(90), 0.0))
    cylinder("Tank_Rear_Cap", 1.06, 0.10, (3.80, 0.08, 1.32), rust, 22,
             rotation=(0.0, deg(90), 0.0), bevel=0.025)

    # Cab at the left/front of the wreck, rolled clockwise toward -Y (the truck's right side).
    box("Cab_Main", (2.00, 1.62, 1.65), (-2.72, -0.18, 1.16), painted, 0.12,
        rotation=(deg(8), deg(-4), deg(-3)))
    box("Cab_Hood", (1.20, 1.50, 0.75), (-3.58, -0.12, 0.92), rust, 0.10,
        rotation=(deg(8), deg(-5), deg(-3)))
    box("Cab_Roof_Crush", (1.55, 1.50, 0.18), (-2.55, -0.55, 2.02), rust, 0.055,
        rotation=(deg(20), deg(-6), deg(-8)))
    box("Windshield", (0.94, 0.035, 0.74), (-2.68, -1.02, 1.52), glass, 0.045,
        rotation=(deg(8), deg(-4), deg(-3)))
    box("Broken_Windshield", (0.25, 0.018, 0.36), (-2.42, -1.055, 1.48), plastic, 0.025,
        rotation=(deg(8), deg(-4), deg(8)))
    # The driver's-side window faces upward: the clearest cue that the cab is on its right side.
    box("Upturned_Door_Window", (0.82, 0.62, 0.045), (-2.60, -0.10, 2.065), glass, 0.045,
        rotation=(deg(2), deg(-5), deg(-3)))
    box("Upturned_Window_Frame", (1.02, 0.82, 0.055), (-2.60, -0.10, 2.035), rust, 0.045,
        rotation=(deg(2), deg(-5), deg(-3)))
    box("Upturned_Window_Glass", (0.80, 0.60, 0.065), (-2.60, -0.10, 2.075), glass, 0.035,
        rotation=(deg(2), deg(-5), deg(-3)))
    box("Front_Grille", (0.12, 1.13, 0.55), (-4.02, -0.08, 0.89), metal, 0.035,
        rotation=(deg(8), deg(-5), deg(-3)))
    for z in (0.75, 0.90, 1.05):
        box(f"Grille_Slat_{z}", (0.04, 0.92, 0.045), (-4.09, -0.12, z), rust, 0.006)

    # The surviving left-side wheels face upward after the truck rolled onto its right side.
    for i, x in enumerate((-2.86, 0.25, 2.65)):
        cylinder(f"Raised_Axle_{i}", 0.07, 0.52, (x, -0.50, 1.93), metal, 10,
                 rotation=(deg(90), 0.0, 0.0))
        cylinder(f"Attached_Tyre_{i}", 0.46, 0.30, (x, -0.67, 2.12), rubber, 18,
                 bevel=0.035)
        cylinder(f"Attached_Rim_{i}", 0.23, 0.33, (x, -0.67, 2.13), rust, 14)
    torus("Detached_Wheel", 0.43, 0.13, (-1.35, -1.02, 0.48), rubber, 18, 5,
          rotation=(deg(84), deg(10), deg(-14)))
    cylinder("Detached_Rim", 0.22, 0.11, (-1.35, -1.07, 0.48), metal, 14,
             rotation=(deg(84), deg(10), deg(-14)))

    # The former top hatch now faces -Y, halfway along the tank, with a bold hazard placard.
    cylinder("Sideways_Hatch_Neck", 0.24, 0.16, (1.15, -1.00, 1.37), metal, 14,
             rotation=(deg(90), 0.0, 0.0))
    cylinder("Sideways_Hatch", 0.34, 0.11, (1.15, -1.12, 1.37), rust, 16,
             rotation=(deg(90), 0.0, 0.0), bevel=0.016)
    handwheel("Tank_Valve", (1.15, -1.23, 1.37), metal, 0.23, True)
    box("Hazard_Plaque", (0.58, 0.035, 0.58), (2.05, -0.96, 1.36), label, 0.035,
        rotation=(deg(8), 0.0, deg(45)))
    box("Hazard_Diamond", (0.40, 0.018, 0.40), (2.05, -0.985, 1.36), plastic, 0.025,
        rotation=(deg(8), 0.0, deg(45)))
    box("Hazard_Bar_H", (0.34, 0.012, 0.055), (2.05, -1.008, 1.36), rust, 0.008,
        rotation=(deg(8), 0.0, 0.0))
    box("Hazard_Bar_V", (0.055, 0.012, 0.34), (2.05, -1.008, 1.36), rust, 0.008,
        rotation=(deg(8), 0.0, 0.0))
    # Scrape rails on the ground-facing side sell the crash and stop the tank feeling pristine.
    for i, x in enumerate((-0.30, 1.15, 2.60)):
        box(f"Tank_Scrape_{i}", (0.70, 0.055, 0.10), (x, -0.91, 0.73 + 0.03 * i), rust, 0.02,
            rotation=(deg(8), deg(-2), deg(3 - i * 3)))


def build_timber_stand() -> None:
    bark = prop_mat("Prop Bark", (0.19, 0.085, 0.032), 0.0, 0.97)
    wood = prop_mat("Prop Wood", (0.68, 0.45, 0.20), 0.0, 0.88)
    rock = prop_mat("Prop Rock", (0.28, 0.27, 0.24), 0.0, 0.98)

    # Seven felled pine logs, all axis X, in a stable 3-3-1 stack.
    logs = [(-0.56, 0.29, 0.28), (0.0, 0.30, 0.30), (0.56, 0.28, 0.27),
            (-0.30, 0.78, 0.27), (0.30, 0.80, 0.29), (-0.02, 1.25, 0.25),
            (0.48, 1.21, 0.23)]
    for i, (y, z, radius) in enumerate(logs):
        length = 2.86 + 0.08 * (i % 3)
        x = 0.05 * ((i % 3) - 1)
        cylinder(f"Log_Bark_{i}", radius, length, (x, y, z), bark, 12,
                 rotation=(0.0, deg(90), 0.0))
        for side in (-1, 1):
            cylinder(f"Log_Cut_{i}_{side}", radius * 0.88, 0.035,
                     (x + side * (length / 2 + 0.012), y, z), wood, 12,
                     rotation=(0.0, deg(90), 0.0))
            for ring in (0.34, 0.62):
                torus(f"Growth_Ring_{i}_{side}_{ring}", radius * ring, 0.008,
                      (x + side * (length / 2 + 0.032), y, z), bark, 10, 3,
                      rotation=(0.0, deg(90), 0.0))
    # Two cut stumps stand beside the front of the stack and keep the silhouette asymmetrical.
    for i, (x, y, r, h) in enumerate(((-0.85, -0.62, 0.34, 0.50),
                                      (0.92, -0.64, 0.29, 0.36))):
        cylinder(f"Stump_Bark_{i}", r, h, (x, y, h / 2), bark, 11)
        cylinder(f"Stump_Cut_{i}", r * 0.90, 0.035, (x, y, h + 0.012), wood, 11)
        for root in range(4):
            a = root * math.tau / 4 + i * 0.35
            tube_between(f"Stump_Root_{i}_{root}",
                         (x + math.cos(a) * r * 0.35, y + math.sin(a) * r * 0.35, 0.10),
                         (x + math.cos(a) * r * 1.35, y + math.sin(a) * r * 1.35, 0.03),
                         0.08, bark, 7)
    for x in (-1.48, 1.48):
        box(f"Stack_Stop_{x}", (0.12, 1.35, 0.12), (x, 0.45, 0.09), rock, 0.02)
    scale_scene_y(0.98)
    scale_scene_z(0.83)


def machine_materials():
    return mat("body"), mat("body_dark"), mat("bare"), mat("bare_edge")


def build_salvager() -> None:
    body, body_dark, bare, bare_edge = machine_materials()
    # Broad skid and squat shredder body.
    box("Base_Skid", (1.68, 1.56, 0.13), (0.0, 0.02, 0.075), body_dark, 0.035)
    for x in (-0.70, 0.70):
        box(f"Skid_Rail_{x}", (0.13, 1.70, 0.11), (x, 0.02, 0.14), bare, 0.022)
    box("Grinder_Case", (1.40, 0.96, 0.63), (0.0, -0.02, 0.63), body, 0.065)
    for x in (-0.38, 0.38):
        cylinder(f"Grinder_End_{x}", 0.28, 0.11, (x, -0.52, 0.67), bare, 14,
                 rotation=(deg(90), 0.0, 0.0), bevel=0.012)
        cylinder(f"Grinder_Hub_{x}", 0.10, 0.14, (x, -0.59, 0.67), bare_edge, 12,
                 rotation=(deg(90), 0.0, 0.0))
    for x in (-0.52, 0.0, 0.52):
        box(f"Case_Rib_{x}", (0.075, 1.00, 0.68), (x, -0.02, 0.63), body_dark, 0.012)

    # Deep top hopper; its black throat reads open without any blue input paint.
    frustum("Top_Hopper", (0.76, 0.58), (1.38, 1.05), 0.55, 0.89, (0.0, 0.05), bare)
    box("Hopper_Throat", (0.68, 0.48, 0.055), (0.0, 0.05, 0.91), mat("black"), 0.012)
    for x in (-0.66, 0.66):
        box(f"Hopper_Rim_X_{x}", (0.075, 1.10, 0.07), (x, 0.05, 1.45), bare_edge, 0.012)
    for y in (-0.48, 0.58):
        box(f"Hopper_Rim_Y_{y}", (1.38, 0.075, 0.07), (0.0, y, 1.45), bare_edge, 0.012)

    # Articulated grabbing arm leans behind the machine toward the node.
    tube_between("Claw_Boom_L", (-0.58, 0.42, 0.32), (-0.55, 0.68, 1.45), 0.075, bare, 10)
    tube_between("Claw_Boom_R", (0.58, 0.42, 0.32), (0.55, 0.68, 1.45), 0.075, bare, 10)
    tube_between("Claw_Crosshead", (-0.55, 0.68, 1.45), (0.55, 0.68, 1.45), 0.075, bare, 10)
    tube_between("Claw_Arm", (0.15, 0.68, 1.44), (0.08, 0.82, 1.72), 0.065, body_dark, 10)
    cylinder("Claw_Pivot", 0.12, 0.22, (0.08, 0.76, 1.70), bare_edge, 12,
             rotation=(0.0, deg(90), 0.0))
    box("Claw_Palm", (0.78, 0.16, 0.12), (0.0, 0.73, 1.69), bare_edge, 0.025,
        rotation=(deg(-7), 0.0, 0.0))
    for i, x in enumerate((-0.24, 0.0, 0.24)):
        tube_between(f"Claw_Tine_{i}", (x, 0.78, 1.67), (x * 1.35, 0.45, 1.42),
                     0.050, bare_edge, 8)
    for side, x in (("L", -0.34), ("R", 0.34)):
        tube_between(f"Claw_Hook_{side}", (x, 0.49, 1.44),
                     (x * 1.10, 0.38, 1.54), 0.050, bare_edge, 8)

    # High-contrast orange scrap chute at FRONT (-Y), with a generous catching tray.
    box("Output_Throat", (0.64, 0.24, 0.26), (0.0, -0.57, 0.48), mat("output_orange"), 0.025)
    box("Output_Chute", (0.92, 0.50, 0.075), (0.0, -0.68, 0.31), mat("output_orange"), 0.016,
        rotation=(deg(13), 0.0, 0.0))
    for x in (-0.48, 0.48):
        box(f"Chute_Rail_{x}", (0.06, 0.50, 0.16), (x, -0.68, 0.36), body_dark, 0.012,
            rotation=(deg(13), 0.0, 0.0))
    box("Chute_Stop", (1.02, 0.07, 0.15), (0.0, -0.89, 0.26), body_dark, 0.012)
    hazard_stripes("Front_Warning", (0.0, -0.507, 0.82), 0.70, 0.12, 5, "-Y")
    lamp((-0.52, -0.10, 1.50))
    scale_scene_y(0.98)


def build_water_pump() -> None:
    body, body_dark, bare, bare_edge = machine_materials()
    gauge = material("Gauge White", (0.78, 0.76, 0.66), 0.05, 0.72)
    box("Skid", (1.10, 1.40, 0.13), (0.0, 0.0, 0.075), body_dark, 0.03)
    for x in (-0.45, 0.45):
        box(f"Skid_Rail_{x}", (0.13, 1.50, 0.10), (x, 0.0, 0.14), bare, 0.018)
    # Motor and snail-like pump chamber are deliberately exposed and mechanical.
    cylinder("Motor", 0.25, 0.55, (-0.25, -0.02, 0.48), body, 16,
             rotation=(0.0, deg(90), 0.0), bevel=0.018)
    cylinder("Motor_End", 0.22, 0.075, (-0.56, -0.02, 0.48), body_dark, 14,
             rotation=(0.0, deg(90), 0.0))
    for x in (-0.43, -0.27, -0.11):
        cylinder(f"Cooling_Fin_{x}", 0.275, 0.035, (x, -0.02, 0.48), bare_edge, 14,
                 rotation=(0.0, deg(90), 0.0))
    cylinder("Pump_Housing", 0.34, 0.32, (0.31, -0.02, 0.48), body_dark, 16,
             rotation=(0.0, deg(90), 0.0), bevel=0.018)
    cylinder("Pump_Face", 0.28, 0.055, (0.49, -0.02, 0.48), bare, 16,
             rotation=(0.0, deg(90), 0.0))

    # Intake pipe is at BACK (+Y), unpainted, and visibly plunges into the ground.
    cylinder("Ground_Intake", 0.085, 0.82, (0.31, 0.54, 0.41), bare, 12)
    cylinder("Back_Elbow", 0.15, 0.16, (0.31, 0.54, 0.77), bare_edge, 12)
    cylinder("Back_Run", 0.085, 0.57, (0.31, 0.27, 0.77), bare, 12,
             rotation=(deg(90), 0.0, 0.0))
    for z in (0.09, 0.68):
        cylinder(f"Intake_Collar_{z}", 0.12, 0.055, (0.31, 0.54, z), bare_edge, 12)

    # Front outlet bends down over a shallow orange drain/can tray.
    cylinder("Outlet_Riser", 0.075, 0.40, (0.30, -0.20, 0.82), bare, 12)
    cylinder("Outlet_Neck", 0.075, 0.42, (0.30, -0.40, 1.02), bare, 12,
             rotation=(deg(90), 0.0, 0.0))
    cylinder("Output_Spout", 0.11, 0.14, (0.30, -0.64, 1.02), mat("output_orange"), 14,
             rotation=(deg(90), 0.0, 0.0))
    box("Output_Tray", (0.70, 0.42, 0.065), (0.25, -0.58, 0.24), mat("output_orange"), 0.015)
    for x in (-0.12, 0.62):
        box(f"Tray_Rail_{x}", (0.055, 0.42, 0.13), (x, -0.58, 0.29), body_dark, 0.01)
    cylinder("Gauge_Bezel", 0.13, 0.06, (-0.10, -0.24, 0.89), mat("black"), 14,
             rotation=(deg(90), 0.0, 0.0))
    cylinder("Gauge_Face", 0.105, 0.015, (-0.10, -0.277, 0.89), gauge, 14,
             rotation=(deg(90), 0.0, 0.0))
    box("Gauge_Needle", (0.018, 0.012, 0.075), (-0.08, -0.288, 0.91), mat("black"), 0.002,
        rotation=(0.0, deg(-30), 0.0))
    lamp((-0.34, 0.12, 0.78))
    scale_scene_x(0.95)
    scale_scene_y(0.77)


def build_fuel_pump() -> None:
    body, body_dark, bare, bare_edge = machine_materials()
    fuel_red = material("Fuel Tank Red", (0.46, 0.055, 0.035), 0.25, 0.76)
    box("Skid", (1.20, 1.24, 0.12), (0.0, 0.0, 0.07), body_dark, 0.03)
    for x in (-0.48, 0.48):
        box(f"Skid_Rail_{x}", (0.13, 1.34, 0.10), (x, 0.0, 0.13), bare, 0.018)
    # Small petrol motor plus transfer pump on an open portable frame.
    box("Engine_Block", (0.48, 0.48, 0.38), (-0.25, 0.08, 0.43), body, 0.055)
    box("Fuel_Tank", (0.50, 0.43, 0.20), (-0.25, 0.07, 0.74), fuel_red, 0.045)
    cylinder("Fuel_Cap", 0.065, 0.04, (-0.35, -0.02, 0.86), bare_edge, 12)
    cylinder("Pump_Drum", 0.23, 0.36, (0.31, 0.05, 0.44), body_dark, 14,
             rotation=(0.0, deg(90), 0.0), bevel=0.016)
    cylinder("Pump_Face", 0.18, 0.055, (0.51, 0.05, 0.44), bare, 14,
             rotation=(0.0, deg(90), 0.0))
    for x in (-0.55, 0.55):
        for y in (-0.48, 0.48):
            cylinder(f"Frame_Upright_{x}_{y}", 0.032, 0.74, (x, y, 0.52), bare, 8)
    for y in (-0.48, 0.48):
        cylinder(f"Frame_Top_{y}", 0.032, 1.10, (0.0, y, 0.89), bare, 8,
                 rotation=(0.0, deg(90), 0.0))

    # Three stacked hose loops at the back make the coiled hose readable from 3/4 view.
    for i, z in enumerate((0.38, 0.55, 0.72)):
        torus(f"Back_Hose_Coil_{i}", 0.31, 0.035, (0.0, 0.55, z), mat("rubber"), 14, 4,
              rotation=(deg(90), 0.0, 0.0))
    tube_between("Hose_Tail", (0.28, 0.55, 0.50), (0.48, -0.37, 0.78), 0.035, mat("rubber"), 8)

    # Filling nozzle is hung over a bright front tray, clearly the sole output side.
    box("Nozzle_Body", (0.12, 0.32, 0.12), (0.45, -0.43, 0.78), bare_edge, 0.025,
        rotation=(deg(-18), 0.0, 0.0))
    box("Nozzle_Handle", (0.08, 0.20, 0.20), (0.45, -0.28, 0.70), mat("black"), 0.018,
        rotation=(deg(-18), 0.0, 0.0))
    tube_between("Nozzle_Spout", (0.45, -0.56, 0.82), (0.45, -0.67, 0.64), 0.035, bare_edge, 10)
    box("Output_Tray", (0.82, 0.43, 0.065), (0.19, -0.51, 0.24), mat("output_orange"), 0.015)
    for x in (-0.24, 0.62):
        box(f"Tray_Rail_{x}", (0.055, 0.43, 0.14), (x, -0.51, 0.29), body_dark, 0.01)
    box("Tray_Stop", (0.88, 0.06, 0.14), (0.19, -0.72, 0.28), mat("output_orange"), 0.01)
    hazard_stripes("Pump_Warning", (-0.25, -0.171, 0.47), 0.35, 0.08, 4, "-Y")
    lamp((-0.47, -0.20, 0.90))
    scale_scene_y(0.77)


def build_sawmill() -> None:
    body, body_dark, bare, bare_edge = machine_materials()
    wood = prop_mat("Prop Wood", (0.64, 0.41, 0.17), 0.0, 0.88)
    bark = prop_mat("Prop Bark", (0.18, 0.078, 0.030), 0.0, 0.97)

    # Portable mill bed: twin lengthwise rails, sleepers and adjustable log bunks.
    for x in (-0.64, 0.64):
        box(f"Bed_Rail_{x}", (0.14, 1.74, 0.16), (x, 0.0, 0.17), body_dark, 0.022)
    for i, y in enumerate((-0.70, -0.22, 0.26, 0.70)):
        box(f"Bed_Sleeper_{i}", (1.55, 0.13, 0.12), (0.0, y, 0.19), bare, 0.018)
        for x in (-0.74, 0.74):
            box(f"Foot_{i}_{x}", (0.16, 0.20, 0.08), (x, y, 0.04), bare_edge, 0.012)
    # Short clamped pine log, axis Y, centred under the band.
    cylinder("Log_Bark", 0.27, 1.42, (0.0, 0.12, 0.54), bark, 12,
             rotation=(deg(90), 0.0, 0.0))
    for y in (-0.60, 0.84):
        cylinder(f"Log_Cut_{y}", 0.245, 0.035, (0.0, y, 0.54), wood, 12,
                 rotation=(deg(90), 0.0, 0.0))
    for x in (-0.39, 0.39):
        box(f"Log_Clamp_Post_{x}", (0.09, 0.15, 0.58), (x, 0.48, 0.42), bare_edge, 0.012)
        box(f"Log_Clamp_Arm_{x}", (0.31, 0.13, 0.08), (x * 0.52, 0.48, 0.69), bare_edge, 0.012)

    # Saw head straddles the log.  Two big front-visible wheel covers plus the thin band
    # between them are the unmistakable portable BANDSAW silhouette.
    for x in (-0.57, 0.57):
        box(f"Head_Upright_{x}", (0.13, 0.32, 1.02), (x, -0.02, 0.91), body, 0.025)
        cylinder(f"Band_Wheel_Cover_{x}", 0.36, 0.15, (x, -0.22, 1.03), body, 18,
                 rotation=(deg(90), 0.0, 0.0), bevel=0.018)
        cylinder(f"Band_Wheel_Rim_{x}", 0.31, 0.025, (x, -0.31, 1.03), body_dark, 18,
                 rotation=(deg(90), 0.0, 0.0))
        cylinder(f"Band_Wheel_Hub_{x}", 0.075, 0.18, (x, -0.25, 1.03), bare_edge, 12,
                 rotation=(deg(90), 0.0, 0.0))
    box("Saw_Head_Top", (1.38, 0.31, 0.14), (0.0, -0.02, 1.37), body_dark, 0.022)
    box("Thin_Band_Blade", (1.22, 0.018, 0.035), (0.0, -0.315, 0.77), bare_edge, 0.003)
    box("Blade_Guard", (0.60, 0.055, 0.10), (0.0, -0.30, 0.82), mat("yellow"), 0.008)
    for x in (-0.42, 0.42):
        box(f"Blade_Guide_{x}", (0.07, 0.12, 0.18), (x, -0.26, 0.77), bare, 0.009)

    # Compact pull-start engine on the saw head, not a table-mounted circular-saw motor.
    box("Head_Engine", (0.48, 0.42, 0.24), (0.23, 0.02, 1.30), body_dark, 0.045)
    cylinder("Engine_Recoil", 0.13, 0.07, (0.23, -0.225, 1.30), bare, 14,
             rotation=(deg(90), 0.0, 0.0))
    box("Engine_Fuel_Tank", (0.32, 0.30, 0.13), (0.23, 0.02, 1.46), body, 0.03)
    cylinder("Engine_Cap", 0.045, 0.025, (0.15, -0.01, 1.54), bare_edge, 10)

    # Fresh-cut planks on the orange FRONT outfeed tray.
    box("Output_Tray", (1.55, 0.40, 0.065), (0.0, -0.72, 0.31), mat("output_orange"), 0.015)
    for x in (-0.79, 0.79):
        box(f"Tray_Rail_{x}", (0.055, 0.40, 0.13), (x, -0.72, 0.36), body_dark, 0.01)
    for i, (x, z) in enumerate(((-0.05, 0.39), (0.05, 0.46), (-0.02, 0.53))):
        box(f"Fresh_Plank_{i}", (1.30, 0.34, 0.06), (x, -0.70, z), wood, 0.012,
            rotation=(0.0, deg((i - 1) * 1.5), deg((i - 1) * 1.2)))
    box("Front_Stop", (1.62, 0.06, 0.16), (0.0, -0.91, 0.36), mat("output_orange"), 0.012)
    lamp((-0.72, 0.04, 1.34))
    scale_scene_z(0.96)


Builder = Callable[[], None]
SPECS: dict[str, tuple[tuple[float, float, float], int, str, Builder]] = {
    "scrap_heap": ((3.6, 1.7, 3.2), 6000, "prop", build_scrap_heap),
    "well": ((1.7, 1.5, 1.7), 6000, "prop", build_well),
    "fuel_tanker": ((8.4, 3.2, 2.8), 6000, "prop", build_fuel_tanker),
    "timber_stand": ((3.4, 1.3, 2.2), 6000, "prop", build_timber_stand),
    "salvager": ((1.8, 1.9, 1.8), 5000, "machine", build_salvager),
    "water_pump": ((1.2, 1.6, 1.2), 5000, "machine", build_water_pump),
    "fuel_pump": ((1.3, 1.4, 1.1), 5000, "machine", build_fuel_pump),
    "sawmill": ((1.9, 1.5, 1.9), 5000, "machine", build_sawmill),
}


def export_one(model_id: str) -> Path:
    size, max_triangles, kind, builder = SPECS[model_id]
    reset()
    builder()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, f"{model_id}: builder made no mesh geometry"
    used = sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material})
    if kind == "prop":
        unexpected = set(used) - PROP_MATERIALS
        assert not unexpected, f"{model_id}: unapproved prop material names: {sorted(unexpected)}"
    else:
        assert "OUTPUT_ORANGE" in used, f"{model_id}: extractor has no orange output"
        assert "INPUT_BLUE" not in used, f"{model_id}: extractor must have no input side"
        assert any(obj.name == "Lamp" for obj in meshes), f"{model_id}: missing separate Lamp"
    print(f"F1_MODEL {model_id}: materials={','.join(used)}")
    return finish(model_id, size, max_triangles=max_triangles)


def look_at(obj, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_contact() -> None:
    missing = [model_id for model_id in SPECS if not (MODEL_DIR / f"{model_id}.glb").exists()]
    if missing:
        raise FileNotFoundError(f"Export all F1 models before contact render: {', '.join(missing)}")
    reset()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 820
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.quality = 93
    scene.render.filepath = str(CONTACT_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.022, 0.028, 0.032)
    scene.view_settings.look = "AgX - Medium High Contrast"

    card_mat = material("Contact Card", (0.078, 0.09, 0.095), 0.0, 0.84)
    floor_mat = material("Contact Floor", (0.12, 0.13, 0.12), 0.0, 0.90)
    text_mat = material("Contact Text", (0.82, 0.86, 0.84), 0.0, 0.52, 0.15)
    cols, rows = 4, 2
    cell_w, cell_h = 4.1, 4.0
    for index, model_id in enumerate(SPECS):
        col, row = index % cols, index // cols
        tx = (col - (cols - 1) / 2) * cell_w
        tz = ((rows - 1) / 2 - row) * cell_h
        before = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / f"{model_id}.glb"))
        imported = [obj for obj in scene.objects if obj not in before and obj.type == "MESH"]
        points = [obj.matrix_world @ Vector(corner) for obj in imported for corner in obj.bound_box]
        lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
        hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
        centre = (lo + hi) / 2
        extent = hi - lo
        scale = min(3.30 / max(extent.x, extent.y, 0.01), 2.65 / max(extent.z, 0.01))
        # Same 3/4 front-left view for every card.  FRONT is -Z after kit.finish/export.
        transform = (Matrix.Translation((tx, 0.0, tz + 0.18)) @
                     Matrix.Rotation(deg(10), 4, "X") @ Matrix.Rotation(deg(156), 4, "Z") @
                     Matrix.Scale(scale, 4) @ Matrix.Translation(-centre))
        for obj in imported:
            obj.matrix_world = transform @ obj.matrix_world
        box(f"Card_{model_id}", (3.84, 0.035, 3.64), (tx, 1.28, tz), card_mat, 0.055)
        box(f"Floor_{model_id}", (3.60, 2.05, 0.035), (tx, 0.20, tz - 1.18), floor_mat, 0.025)
        bpy.ops.object.text_add(location=(tx, -1.28, tz - 1.48), rotation=(deg(90), 0.0, 0.0))
        text_obj = bpy.context.object
        text_obj.name = f"Label_{model_id}"
        text_obj.data.body = model_id.replace("_", " ")
        text_obj.data.align_x = "CENTER"
        text_obj.data.align_y = "CENTER"
        text_obj.data.size = 0.31
        text_obj.data.extrude = 0.006
        text_obj.data.materials.append(text_mat)

    bpy.ops.object.camera_add(location=(0.0, -25.0, 0.0))
    camera = bpy.context.object
    look_at(camera, Vector((0.0, 0.0, 0.0)))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 17.6
    scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-6.0, -10.0, 10.0))
    key = bpy.context.object
    key.data.energy = 1500
    key.data.shape = "DISK"
    key.data.size = 8.0
    look_at(key, Vector((0.0, 0.0, 0.0)))
    bpy.ops.object.light_add(type="AREA", location=(8.0, -7.0, 2.0))
    fill = bpy.context.object
    fill.data.energy = 950
    fill.data.size = 7.0
    look_at(fill, Vector((0.0, 0.0, 0.0)))
    bpy.ops.object.light_add(type="AREA", location=(0.0, 5.0, 9.0))
    rim = bpy.context.object
    rim.data.energy = 1250
    rim.data.size = 6.0
    look_at(rim, Vector((0.0, 0.0, 0.0)))
    bpy.ops.render.render(write_still=True)
    print(f"F1_MODEL contact: {CONTACT_PATH.relative_to(ROOT)}")


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    command = args[0] if args else "all"
    if command == "all":
        for model_id in SPECS:
            export_one(model_id)
    elif command == "contact":
        render_contact()
    elif command in SPECS:
        export_one(command)
    else:
        valid = ", ".join(["all", "contact", *SPECS])
        raise SystemExit(f"Unknown F1 model '{command}'. Valid choices: {valid}")


if __name__ == "__main__":
    main()
