"""Deterministic F2 HUB and radio-mast models for Noise Floor.

The models follow :mod:`kit` conventions: metres, FRONT = Blender -Y, and
``finish(id, box)`` stands each export on its collision-box floor, verifies the
fit, and writes ``assets/models/<id>.glb``.  Both models use ``lamp()`` so the
game gets a separate mesh named ``Lamp`` to recolour at runtime.

Run one model, both models, or the labelled 3/4-view review render::

    blender.exe -b --factory-startup --python tools/art/f2_models.py -- hub
    blender.exe -b --factory-startup --python tools/art/f2_models.py -- radio_mast
    blender.exe -b --factory-startup --python tools/art/f2_models.py -- all
    blender.exe -b --factory-startup --python tools/art/f2_models.py -- contact

The contact render imports the finished GLBs and writes a 1500 px JPEG to
``tools/art/f2_models_contact.jpg``.  No randomness is used; every export is
independent because ``export_one()`` resets the Blender scene first.
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, deg, finish, lamp, mat, material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
CONTACT_PATH = Path(__file__).with_name("f2_models_contact.jpg")

# Extra prop names are deliberately limited to the established F1 prop palette.
PROP_MATERIALS = {
    "Prop Wood", "Prop Concrete", "Prop Fabric", "Prop Label", "Prop Glass",
}


def prop_mat(name: str, color: tuple[float, float, float], metallic: float = 0.0,
             roughness: float = 0.78, emission: float = 0.0):
    assert name in PROP_MATERIALS, f"Unapproved F2 prop material: {name}"
    return material(name, color, metallic, roughness, emission)


def torus(name: str, major_radius: float, minor_radius: float,
          location: tuple[float, float, float], material_, major_segments: int = 12,
          minor_segments: int = 4,
          rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=minor_segments,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    return obj


def tube_between(name: str, a: tuple[float, float, float], b: tuple[float, float, float],
                 radius: float, material_, vertices: int = 8):
    """Low-poly tube between two world-space points."""
    av, bv = Vector(a), Vector(b)
    delta = bv - av
    obj = cylinder(name, radius, delta.length, tuple((av + bv) / 2), material_, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def dish(name: str, location: tuple[float, float, float], radius: float, material_):
    """A shallow two-ring parabolic dish whose open face points toward FRONT (-Y)."""
    cx, cy, cz = location
    segments = 16
    verts = [(cx, cy + 0.17, cz)]
    for ring, r in enumerate((radius * 0.52, radius)):
        y = cy + (0.11 if ring == 0 else 0.0)
        for i in range(segments):
            a = math.tau * i / segments
            verts.append((cx + math.cos(a) * r, y, cz + math.sin(a) * r))
    faces: list[tuple[int, ...]] = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((0, 1 + j, 1 + i))
        faces.append((1 + i, 1 + j, 1 + segments + j, 1 + segments + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def map_string(name: str, points: list[tuple[float, float]], z: float, material_) -> None:
    for i, ((ax, ay), (bx, by)) in enumerate(zip(points, points[1:])):
        tube_between(f"{name}_{i}", (ax, ay, z), (bx, by, z), 0.008, material_, 6)


def build_hub() -> None:
    body = mat("body")
    body_dark = mat("body_dark")
    bare = mat("bare")
    bare_edge = mat("bare_edge")
    black = mat("black")
    red = mat("red")
    yellow = mat("yellow")
    rubber = mat("rubber")
    wood = prop_mat("Prop Wood", (0.48, 0.285, 0.115), 0.0, 0.86)
    paper = prop_mat("Prop Label", (0.82, 0.78, 0.64), 0.0, 0.82)
    fabric = prop_mat("Prop Fabric", (0.20, 0.25, 0.22), 0.0, 0.95)
    lantern_glass = prop_mat("Prop Glass", (0.82, 0.56, 0.16), 0.0, 0.35, 2.2)

    # Steel-legged survivor work table. Three separate planks and battered edge straps keep
    # it improvised, while the open front makes the supplies below readable to the player.
    for x in (-0.69, 0.69):
        for y in (-0.46, 0.46):
            box(f"Table_Leg_{x}_{y}", (0.105, 0.105, 0.79), (x, y, 0.405), bare, 0.018)
            box(f"Table_Foot_{x}_{y}", (0.19, 0.18, 0.055), (x, y - 0.015, 0.028), body_dark, 0.012)
    for y in (-0.45, 0.45):
        box(f"Table_Rail_X_{y}", (1.53, 0.09, 0.12), (0.0, y, 0.70), body_dark, 0.014)
    for x in (-0.69, 0.69):
        box(f"Table_Rail_Y_{x}", (0.09, 1.00, 0.12), (x, 0.0, 0.70), body_dark, 0.014)
    for i, y in enumerate((-0.38, -0.12, 0.14, 0.40)):
        box(f"Table_Plank_{i}", (1.64, 0.255, 0.085), (0.0, y, 0.815), wood, 0.018,
            rotation=(0.0, deg((i - 1.5) * 0.35), deg((i - 1.5) * 0.28)))
    for x in (-0.80, 0.80):
        box(f"Top_Edge_Strap_{x}", (0.045, 1.08, 0.105), (x, 0.01, 0.82), bare_edge, 0.008)

    # Big map, pinned flat where the survivor can work on it. Raised red threads remain
    # visible after material merging and make the planning-table read immediate.
    box("Paper_Map", (0.93, 0.62, 0.018), (-0.25, -0.13, 0.873), paper, 0.010,
        rotation=(0.0, 0.0, deg(-4)))
    for x in (-0.54, -0.23, 0.07):
        box(f"Map_Road_V_{x}", (0.020, 0.51, 0.008), (x, -0.13, 0.886), fabric, 0.002,
            rotation=(0.0, 0.0, deg(8 + x * 12)))
    for i, y in enumerate((-0.29, -0.06, 0.15)):
        box(f"Map_Road_H_{i}", (0.74, 0.017, 0.008), (-0.25, y, 0.887), fabric, 0.002,
            rotation=(0.0, 0.0, deg(-8 + i * 7)))
    map_string("Red_String_A", [(-0.58, -0.31), (-0.12, -0.05), (0.10, 0.11)], 0.903, red)
    map_string("Red_String_B", [(-0.46, 0.12), (-0.08, -0.19), (0.15, -0.31)], 0.904, red)
    for i, (x, y) in enumerate(((-0.58, -0.31), (-0.12, -0.05), (0.10, 0.11),
                                (-0.46, 0.12), (-0.08, -0.19), (0.15, -0.31))):
        cylinder(f"Map_Pin_{i}", 0.018, 0.028, (x, y, 0.909), red, 8)

    # Ham radio at the rear-right: chunky field set, front dial/speaker, microphone and whip.
    box("Radio_Case", (0.55, 0.34, 0.31), (0.48, 0.27, 1.02), body_dark, 0.045)
    box("Radio_Face", (0.49, 0.030, 0.25), (0.48, 0.083, 1.02), bare, 0.012)
    box("Radio_Speaker", (0.21, 0.014, 0.16), (0.36, 0.064, 1.02), black, 0.006)
    for i, z in enumerate((0.965, 1.005, 1.045, 1.085)):
        box(f"Speaker_Slot_{i}", (0.17, 0.010, 0.012), (0.36, 0.054, z), bare_edge, 0.002)
    cylinder("Tuning_Dial", 0.070, 0.045, (0.60, 0.052, 1.055), black, 14,
             rotation=(deg(90), 0.0, 0.0))
    cylinder("Volume_Dial", 0.038, 0.042, (0.69, 0.054, 0.970), black, 12,
             rotation=(deg(90), 0.0, 0.0))
    box("Frequency_Window", (0.16, 0.012, 0.045), (0.59, 0.052, 1.135), paper, 0.003)
    box("Radio_Handle", (0.35, 0.05, 0.045), (0.47, 0.27, 1.205), bare_edge, 0.010)
    for x in (0.31, 0.63):
        box(f"Radio_Handle_Post_{x}", (0.045, 0.05, 0.13), (x, 0.27, 1.16), bare_edge, 0.008)
    cylinder("Radio_Antenna", 0.014, 0.44, (0.69, 0.38, 1.44), bare_edge, 8,
             rotation=(0.0, deg(-7), 0.0))
    cylinder("Antenna_Base", 0.045, 0.07, (0.66, 0.38, 1.22), rubber, 10)

    # Hand microphone laid within reach, with an unmistakable coiled cable loop.
    cylinder("Microphone_Body", 0.045, 0.20, (0.41, -0.18, 0.94), black, 10,
             rotation=(deg(90), 0.0, deg(-18)))
    cylinder("Microphone_Grille", 0.067, 0.075, (0.38, -0.275, 0.94), bare_edge, 12,
             rotation=(deg(90), 0.0, deg(-18)))
    torus("Microphone_Cable_Loop", 0.105, 0.014, (0.61, -0.12, 0.903), rubber, 12, 4)
    tube_between("Microphone_Cable_Tail", (0.54, -0.05, 0.91), (0.64, 0.12, 0.96),
                 0.014, rubber, 7)

    # The radio's runtime status light. Pre-creating material "Lamp" gives the review render
    # a powered green lens; lamp() still supplies the required separately named object.
    material("Lamp", (0.08, 0.72, 0.20), 0.0, 0.28, 3.0)
    lamp((0.73, 0.12, 1.18), radius=0.045)

    # Milestone board on a steel stand at the rear. Paper strips and red completion marks are
    # geometry so the list survives at game distance without relying on a texture.
    for x in (-0.55, 0.55):
        box(f"Board_Post_{x}", (0.065, 0.075, 0.78), (x, 0.53, 1.16), bare, 0.010)
    box("Milestone_Board", (1.28, 0.075, 0.61), (0.0, 0.54, 1.38), wood, 0.025,
        rotation=(deg(-3), 0.0, 0.0))
    box("Milestone_Sheet", (1.10, 0.018, 0.50), (0.0, 0.493, 1.38), paper, 0.008,
        rotation=(deg(-3), 0.0, 0.0))
    box("Milestone_Header", (0.76, 0.010, 0.055), (-0.09, 0.479, 1.565), red, 0.003)
    for i, z in enumerate((1.48, 1.39, 1.30, 1.21)):
        box(f"Milestone_Line_{i}", (0.72 - i * 0.05, 0.010, 0.028),
            (0.02, 0.475, z), fabric, 0.003)
        box(f"Milestone_Check_{i}", (0.055, 0.010, 0.055), (-0.42, 0.474, z),
            red if i < 2 else bare_edge, 0.004, rotation=(0.0, 0.0, deg(45)))
    cylinder("Board_Top_Pin", 0.025, 0.025, (0.0, 0.468, 1.60), red, 8,
             rotation=(deg(90), 0.0, 0.0))

    # A warm kerosene lantern balances the electronics and makes the bench feel inhabited.
    cylinder("Lantern_Base", 0.115, 0.095, (-0.69, 0.20, 0.93), body_dark, 14)
    cylinder("Lantern_Globe", 0.082, 0.22, (-0.69, 0.20, 1.08), lantern_glass, 14)
    cylinder("Lantern_Cap", 0.10, 0.070, (-0.69, 0.20, 1.225), yellow, 14)
    for x in (-0.79, -0.59):
        cylinder(f"Lantern_Guard_{x}", 0.010, 0.28, (x, 0.20, 1.09), bare_edge, 6)
    torus("Lantern_Handle", 0.155, 0.012, (-0.69, 0.20, 1.25), bare_edge, 14, 4,
          rotation=(deg(90), 0.0, 0.0))

    # Two slatted supply crates under the table, offset so both read from the front-left view.
    for crate, (cx, cy, sx, sy, sz) in enumerate(((-0.42, 0.06, 0.56, 0.46, 0.43),
                                                  (0.37, 0.21, 0.48, 0.39, 0.34))):
        box(f"Crate_Core_{crate}", (sx, sy, sz), (cx, cy, sz / 2 + 0.06), wood, 0.018)
        for z in (0.10, sz / 2 + 0.06, sz + 0.02):
            box(f"Crate_Slat_Front_{crate}_{z}", (sx + 0.035, 0.045, 0.055),
                (cx, cy - sy / 2 - 0.018, z), bare_edge, 0.006)
        for x in (cx - sx / 2 + 0.035, cx + sx / 2 - 0.035):
            box(f"Crate_Corner_{crate}_{x}", (0.055, sy + 0.03, sz + 0.035),
                (x, cy, sz / 2 + 0.06), body_dark, 0.006)


def build_radio_mast() -> None:
    body = mat("body")
    body_dark = mat("body_dark")
    bare = mat("bare")
    bare_edge = mat("bare_edge")
    black = mat("black")
    red = mat("red")
    rubber = mat("rubber")
    concrete = prop_mat("Prop Concrete", (0.43, 0.42, 0.38), 0.0, 0.96)
    label = prop_mat("Prop Label", (0.78, 0.72, 0.53), 0.0, 0.80)

    # Broad footing and four bolted shoes anchor the silhouette before the taper begins.
    box("Concrete_Footing", (1.72, 1.66, 0.28), (0.0, 0.0, 0.14), concrete, 0.055)
    for x in (-0.66, 0.66):
        for y in (-0.66, 0.66):
            box(f"Tower_Shoe_{x}_{y}", (0.25, 0.25, 0.075), (x, y, 0.33), body_dark, 0.018)
            for dx in (-0.075, 0.075):
                for dy in (-0.075, 0.075):
                    cylinder(f"Anchor_Bolt_{x}_{y}_{dx}_{dy}", 0.018, 0.075,
                             (x + dx, y + dy, 0.40), bare_edge, 8)

    # Ten-bay tapered square lattice. Double diagonals on every face make the tower legible
    # from 100 m while staying comfortably below the 6000-triangle target.
    z_levels = [0.40 + i * 1.055 for i in range(11)]

    def half_width(z: float) -> float:
        return 0.66 + (0.19 - 0.66) * ((z - z_levels[0]) / (z_levels[-1] - z_levels[0]))

    def corners(z: float) -> list[tuple[float, float, float]]:
        h = half_width(z)
        return [(-h, -h, z), (h, -h, z), (h, h, z), (-h, h, z)]

    bottom = corners(z_levels[0])
    top = corners(z_levels[-1])
    for i in range(4):
        tube_between(f"Tower_Leg_{i}", bottom[i], top[i], 0.048, bare, 8)

    for level, z in enumerate(z_levels):
        ring = corners(z)
        for side in range(4):
            tube_between(f"Ring_{level}_{side}", ring[side], ring[(side + 1) % 4],
                         0.031, body_dark, 8)

    for bay in range(len(z_levels) - 1):
        lo = corners(z_levels[bay])
        hi = corners(z_levels[bay + 1])
        for side in range(4):
            nxt = (side + 1) % 4
            tube_between(f"Brace_A_{bay}_{side}", lo[side], hi[nxt], 0.022, bare_edge, 7)
            tube_between(f"Brace_B_{bay}_{side}", lo[nxt], hi[side], 0.022, bare_edge, 7)

    # Small service platform near the aerials gives scale and a strong horizontal break.
    platform_z = 9.93
    box("Service_Platform", (0.72, 0.72, 0.075), (0.0, 0.0, platform_z), body_dark, 0.018)
    for x in (-0.34, 0.34):
        for y in (-0.34, 0.34):
            cylinder(f"Platform_Rail_Post_{x}_{y}", 0.018, 0.43,
                     (x, y, platform_z + 0.24), bare_edge, 7)
    for y in (-0.34, 0.34):
        tube_between(f"Platform_Rail_X_{y}", (-0.34, y, platform_z + 0.44),
                     (0.34, y, platform_z + 0.44), 0.018, bare_edge, 7)
    for x in (-0.34, 0.34):
        tube_between(f"Platform_Rail_Y_{x}", (x, -0.34, platform_z + 0.44),
                     (x, 0.34, platform_z + 0.44), 0.018, bare_edge, 7)

    # Large front-facing microwave dish, feed horn and rear braces.
    dish("Main_Dish", (0.0, -0.31, 8.78), 0.50, body)
    torus("Dish_Rim", 0.50, 0.025, (0.0, -0.31, 8.78), bare_edge, 16, 4,
          rotation=(deg(90), 0.0, 0.0))
    tube_between("Dish_Feed_Arm", (0.0, -0.20, 8.78), (0.0, -0.75, 8.78),
                 0.025, bare_edge, 8)
    cylinder("Dish_Feed", 0.065, 0.15, (0.0, -0.79, 8.78), black, 10,
             rotation=(deg(90), 0.0, 0.0))
    for x in (-0.34, 0.34):
        tube_between(f"Dish_Back_Brace_{x}", (x, -0.05, 8.78),
                     (x * 0.35, 0.18, 8.47), 0.027, bare, 8)

    # VHF dipole array above the platform: thick, repeated cross-elements remain visible at
    # long range and make this unmistakably a radio mast rather than a power pylon.
    cylinder("Antenna_Spine", 0.035, 1.52, (0.0, 0.0, 10.78), bare_edge, 8)
    for i, z in enumerate((10.22, 10.62, 11.02, 11.42)):
        tube_between(f"Dipole_{i}", (-0.46, 0.0, z), (0.46, 0.0, z),
                     0.025, bare_edge, 8)
        tube_between(f"Dipole_Stub_{i}", (0.0, -0.18, z), (0.0, 0.18, z),
                     0.018, bare, 7)
    cylinder("Top_Whip", 0.018, 0.64, (0.0, 0.0, 11.48), bare_edge, 8)

    # Compact emergency generator/control box at the front of the footing.
    box("Generator_Skid", (0.76, 0.47, 0.08), (-0.36, -0.49, 0.38), body_dark, 0.018)
    box("Generator_Box", (0.68, 0.39, 0.50), (-0.36, -0.47, 0.67), body, 0.055)
    box("Generator_Face", (0.59, 0.030, 0.39), (-0.36, -0.682, 0.68), body_dark, 0.012)
    for i, z in enumerate((0.57, 0.64, 0.71, 0.78)):
        box(f"Generator_Vent_{i}", (0.27, 0.012, 0.025), (-0.46, -0.703, z), black, 0.003)
    cylinder("Generator_Gauge", 0.072, 0.035, (-0.17, -0.706, 0.74), label, 12,
             rotation=(deg(90), 0.0, 0.0))
    cylinder("Generator_Stop", 0.045, 0.044, (-0.17, -0.710, 0.59), red, 12,
             rotation=(deg(90), 0.0, 0.0))
    box("Generator_Handle", (0.42, 0.055, 0.055), (-0.36, -0.47, 0.98), bare_edge, 0.010)
    for x in (-0.54, -0.18):
        box(f"Generator_Handle_Post_{x}", (0.045, 0.055, 0.13),
            (x, -0.47, 0.93), bare_edge, 0.008)

    # Heavy cable snakes across the footing into a protected tower junction box.
    tube_between("Cable_Run_A", (-0.04, -0.45, 0.43), (0.32, -0.30, 0.43),
                 0.035, rubber, 10)
    tube_between("Cable_Run_B", (0.32, -0.30, 0.43), (0.43, -0.08, 0.48),
                 0.035, rubber, 10)
    box("Tower_Junction", (0.25, 0.16, 0.30), (0.43, -0.02, 0.60), body_dark, 0.025)
    box("Junction_Label", (0.16, 0.012, 0.09), (0.43, -0.107, 0.64), label, 0.004)

    # The red broadcast beacon is the required separate Lamp mesh. Its mounting base joins the
    # body; the lens is controlled by the game while the rescue transmission is active.
    box("Beacon_Mount", (0.20, 0.20, 0.075), (0.0, 0.0, 11.78), body_dark, 0.018)
    material("Lamp", (0.92, 0.025, 0.012), 0.0, 0.24, 4.0)
    lamp((0.0, 0.0, 11.82), radius=0.075)


Builder = Callable[[], None]
SPECS: dict[str, tuple[tuple[float, float, float], int, Builder]] = {
    "hub": ((1.9, 1.7, 1.9), 6000, build_hub),
    "radio_mast": ((1.9, 12.0, 1.9), 6000, build_radio_mast),
}


def export_one(model_id: str) -> Path:
    size, max_triangles, builder = SPECS[model_id]
    reset()
    builder()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert meshes, f"{model_id}: builder made no mesh geometry"
    assert sum(obj.name == "Lamp" for obj in meshes) == 1, f"{model_id}: needs one separate Lamp"
    used = sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material})
    print(f"F2_MODEL {model_id}: materials={','.join(used)}")
    return finish(model_id, size, max_triangles=max_triangles)


def look_at(obj, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_contact() -> None:
    missing = [model_id for model_id in SPECS if not (MODEL_DIR / f"{model_id}.glb").exists()]
    if missing:
        raise FileNotFoundError(f"Export all F2 models before contact render: {', '.join(missing)}")
    reset()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 850
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.quality = 94
    scene.render.filepath = str(CONTACT_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.024, 0.027)
    scene.view_settings.look = "AgX - Medium High Contrast"

    card_mat = material("Contact Card", (0.072, 0.082, 0.086), 0.0, 0.86)
    floor_mat = material("Contact Floor", (0.105, 0.115, 0.105), 0.0, 0.93)
    text_mat = material("Contact Text", (0.88, 0.87, 0.77), 0.0, 0.52, 0.12)
    for index, model_id in enumerate(SPECS):
        tx = -3.75 if index == 0 else 3.75
        before = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / f"{model_id}.glb"))
        imported = [obj for obj in scene.objects if obj not in before and obj.type == "MESH"]
        points = [obj.matrix_world @ Vector(corner) for obj in imported for corner in obj.bound_box]
        lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
        hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
        centre = (lo + hi) / 2
        extent = hi - lo
        scale = min(6.15 / max(extent.x, extent.y, 0.01), 6.45 / max(extent.z, 0.01))
        print(f"F2_CONTACT {model_id}: centre={tuple(round(v, 3) for v in centre)} "
              f"extent={tuple(round(v, 3) for v in extent)} scale={scale:.3f}")
        transform = (Matrix.Translation((tx, 0.0, 0.20)) @
                     Matrix.Rotation(deg(8), 4, "X") @ Matrix.Rotation(deg(151), 4, "Z") @
                     Matrix.Scale(scale, 4) @ Matrix.Translation(-centre))
        for obj in imported:
            obj.matrix_world = transform @ obj.matrix_world

        rendered_bottom = 0.20 - extent.z * scale / 2
        box(f"Card_{model_id}", (7.10, 0.040, 7.55), (tx, 1.52, 0.0), card_mat, 0.065)
        box(f"Floor_{model_id}", (6.85, 2.30, 0.045),
            (tx, 0.32, rendered_bottom - 0.05), floor_mat, 0.025)
        bpy.ops.object.text_add(location=(tx, -1.53, -3.42), rotation=(deg(90), 0.0, 0.0))
        text_obj = bpy.context.object
        text_obj.name = f"Label_{model_id}"
        text_obj.data.body = model_id.replace("_", " ").upper()
        text_obj.data.align_x = "CENTER"
        text_obj.data.align_y = "CENTER"
        text_obj.data.size = 0.37
        text_obj.data.extrude = 0.008
        text_obj.data.materials.append(text_mat)

    bpy.ops.object.camera_add(location=(0.0, -27.0, 0.2))
    camera = bpy.context.object
    look_at(camera, Vector((0.0, 0.0, 0.0)))
    camera.data.type = "ORTHO"
    # Blender's orthographic scale is the camera width with this horizontal sensor fit.
    # 15.8 gives a roughly 9 m-tall frame at 1500 x 850, leaving room for labels.
    camera.data.ortho_scale = 15.8
    scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-6.0, -9.0, 10.0))
    key = bpy.context.object
    key.data.energy = 1600
    key.data.shape = "DISK"
    key.data.size = 7.0
    look_at(key, Vector((0.0, 0.0, 1.0)))
    bpy.ops.object.light_add(type="AREA", location=(8.0, -7.0, 4.0))
    fill = bpy.context.object
    fill.data.energy = 1100
    fill.data.size = 6.0
    look_at(fill, Vector((0.0, 0.0, 0.5)))
    bpy.ops.object.light_add(type="AREA", location=(0.0, 5.0, 11.0))
    rim = bpy.context.object
    rim.data.energy = 1750
    rim.data.size = 6.0
    look_at(rim, Vector((0.0, 0.0, 1.0)))

    bpy.ops.render.render(write_still=True)
    print(f"F2_MODEL contact: {CONTACT_PATH.relative_to(ROOT)}")


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
        raise SystemExit(f"Unknown F2 model '{command}'. Valid choices: {valid}")


if __name__ == "__main__":
    main()
