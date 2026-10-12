"""Shared helpers for Noise Floor's Blender model scripts (Blender 5.1, run headless).

A model script builds its parts with these helpers and ends with `finish()`. That merges the
parts into one mesh (one draw call per material in Godot), stands the model on the floor of its
collision box, checks it fits, and exports `assets/models/<id>.glb`.

    blender.exe -b --factory-startup --python tools/art/<id>.py

Conventions the game relies on (src/world/build_view.gd, test/test_art_models.gd):
- Metres. Build with the FRONT (a machine's output side) facing -Y and the BACK (input side)
  facing +Y, as in Blender's front view. finish() turns the model round so the front ends up
  at -Z in Godot, the game's front. The model must fit the piece's collision box from data/buildables.json.
  `finish()` checks that and puts the model's base on the box floor.
- Machines and generators get a status lamp from `lamp()`. It's exported as a separate object
  named "Lamp" that the game recolours (green running, red no power, orange output full).
  The lamp may poke up to LAMP_ALLOWANCE above the box. Nothing else may.
- A turret's aiming head is a separate object named "Head", made with `part()` and pivoting on a
  vertical axis through its origin, with the barrel pointing -Y (the front). It may also rise
  LAMP_ALLOWANCE above the box. In the game, FactoryView turns it toward its target.
- finish() turns the model 180 degrees, so Blender -X ends up on the game's +X side. That only
  matters for left/right details such as a door handle.
- Item machines show which side is which with paint: an OUTPUT_ORANGE part on the front (chute,
  hatch or tray) and an INPUT_BLUE part on the back (hopper or intake), each easy to see from 5 m.
"""

import logging
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

log = logging.getLogger("kit")
logging.basicConfig(level=logging.INFO, format="%(message)s")

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
LAMP_ALLOWANCE = 0.2  # metres a separate part (lamp, turret head) may rise above the collision box
SEPARATE = ("Lamp", "Head")  # objects exported as their own nodes; the game moves or recolours them
EPS = 1.0e-4

# The shared palette, so every machine looks like part of the same scavenged set.
# key: (material name, linear RGB, metallic, roughness)
PALETTE: dict[str, tuple[str, tuple[float, float, float], float, float]] = {
    "body": ("Painted Green-Grey Steel", (0.16, 0.22, 0.20), 0.55, 0.72),
    "body_dark": ("Worn Dark Green Steel", (0.095, 0.135, 0.125), 0.60, 0.78),
    "bare": ("Bare Dark Steel", (0.14, 0.16, 0.17), 0.82, 0.45),
    "bare_edge": ("Scuffed Steel", (0.25, 0.27, 0.27), 0.78, 0.50),
    "rust": ("Rust", (0.22, 0.075, 0.03), 0.30, 0.90),
    "yellow": ("Hazard Yellow", (0.88, 0.60, 0.035), 0.15, 0.62),
    "black": ("Hazard Black", (0.025, 0.030, 0.028), 0.20, 0.76),
    "red": ("Emergency Button Red", (0.72, 0.035, 0.025), 0.10, 0.55),
    "rubber": ("Rubber", (0.018, 0.022, 0.021), 0.05, 0.85),
    "input_blue": ("INPUT_BLUE", (0.05, 0.16, 0.62), 0.25, 0.60),
    "output_orange": ("OUTPUT_ORANGE", (0.90, 0.30, 0.03), 0.25, 0.60),
}

_materials: dict[str, bpy.types.Material] = {}


def reset() -> None:
    """Empty the scene and forget cached materials. Call first in every model script."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    _materials.clear()


def material(name: str, color: tuple[float, float, float], metallic: float = 0.1,
             roughness: float = 0.75, emission: float = 0.0) -> bpy.types.Material:
    """A flat-colour Principled material, made once per name."""
    if name not in _materials:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (*color, 1.0)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0.0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
        _materials[name] = mat
    return _materials[name]


def mat(key: str) -> bpy.types.Material:
    """A shared palette material by key (see PALETTE)."""
    name, color, metallic, roughness = PALETTE[key]
    return material(name, color, metallic, roughness)


def _bevel(obj: bpy.types.Object, width: float) -> None:
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = 1
    mod.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def box(name: str, size: tuple[float, float, float], location: tuple[float, float, float],
        material_: bpy.types.Material, bevel: float = 0.0,
        rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    """A box of `size` (X, Y, Z metres) centred on `location`, rotation in radians."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material_)
    if bevel > 0.0:
        _bevel(obj, bevel)
    return obj


def cylinder(name: str, radius: float, depth: float, location: tuple[float, float, float],
             material_: bpy.types.Material, vertices: int = 12,
             rotation: tuple[float, float, float] = (0.0, 0.0, 0.0), bevel: float = 0.0) -> bpy.types.Object:
    """A cylinder along Z (rotate to lay it down), centred on `location`."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                        end_fill_type="NGON", location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material_)
    if bevel > 0.0:
        _bevel(obj, bevel)
    return obj


def quad(name: str, corners: list[tuple[float, float, float]], material_: bpy.types.Material) -> bpy.types.Object:
    """A single flat face through four corners (hazard stripes, labels, panel inlays)."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(corners, [], [(0, 1, 2, 3)])
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def hazard_stripes(name: str, centre: tuple[float, float, float], width: float, height: float,
                   count: int = 5, facing: str = "-Y") -> None:
    """A black panel with slanted yellow stripes, flush on a face pointing along `facing` (-Y, +Y, -X, +X)."""
    depth = 0.018
    cx, cy, cz = centre
    along_x = facing in ("-Y", "+Y")
    sign = -1.0 if facing.startswith("-") else 1.0
    size = (width, depth, height) if along_x else (depth, width, height)
    box(f"{name}_Backing", size, centre, mat("black"), 0.006)
    out = sign * (depth / 2 + 0.002)
    pitch = width / count
    w, s = pitch * 0.5, pitch * 0.35
    for i in range(count):
        u = -width / 2 + pitch * (i + 0.5) - s / 2
        pts = [(u - w / 2, -height * 0.4), (u + w / 2, -height * 0.4), (u + w / 2 + s, height * 0.4), (u - w / 2 + s, height * 0.4)]
        if along_x:
            corners = [(cx + a, cy + out, cz + b) for a, b in pts]
        else:
            corners = [(cx + out, cy + a, cz + b) for a, b in pts]
        if (sign > 0) == along_x:
            corners.reverse()  # keep the face pointing outward
        quad(f"{name}_Stripe_{i}", corners, mat("yellow"))


def lamp(location: tuple[float, float, float], radius: float = 0.08) -> None:
    """A status beacon standing on `location` (the point it's mounted on): a dark base plus the
    separate "Lamp" object the game recolours. Top-centre of the machine reads best."""
    x, y, z = location
    cylinder("Lamp_Base", radius * 1.3, 0.04, (x, y, z + 0.02), mat("black"), 12)
    cylinder("Lamp", radius, 0.11, (x, y, z + 0.04 + 0.055), material("Lamp", (0.2, 0.2, 0.2), 0.0, 0.4), 12)


def part(name: str, objects: list[bpy.types.Object], pivot: tuple[float, float, float]) -> bpy.types.Object:
    """Join `objects` into one separate, named object whose origin is `pivot`. The game moves it on
    its own, e.g. a turret's "Head" turns about a vertical axis through its pivot."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.scene.cursor.location = pivot
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.name = name
    obj.data.name = name
    return obj


def _bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def _triangles(obj: bpy.types.Object) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def finish(piece_id: str, size: tuple[float, float, float], max_triangles: int = 4000,
           overhang: tuple[float, float] = (0.0, 0.0)) -> Path:
    """Merge, place, check and export the scene as assets/models/<piece_id>.glb.

    `size` is the piece's collision box from data/buildables.json, in Godot order
    (width X, height Y, depth Z). `overhang` lets parts stick out past the box in X and depth
    (only the power pole's crossbar needs it). Objects named in SEPARATE stay their own nodes."""
    separate = [bpy.data.objects[n] for n in SEPARATE if n in bpy.data.objects]
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in separate]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = piece_id
    body.data.name = piece_id
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    everything = [body] + separate

    # Centre the footprint and stand the base on the floor of the box (Godot centres the box).
    lo, hi = _bounds([body])
    shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z - size[1] / 2))
    for o in everything:
        o.location += shift
    bpy.context.view_layer.update()  # matrix_world is stale until this runs
    # Turn it around: the glTF exporter maps Blender -Y to +Z, but the game's front is -Z.
    half_turn = Matrix.Rotation(math.pi, 4, "Z")
    for o in everything:
        o.matrix_world = half_turn @ o.matrix_world
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=o is body, rotation=True, scale=False)
    bpy.context.view_layer.update()

    hx, hz, hy = size[0] / 2 + overhang[0], size[1] / 2, size[2] / 2 + overhang[1]
    lo, hi = _bounds([body])
    assert lo.x >= -hx - EPS and hi.x <= hx + EPS, f"{piece_id}: {hi.x - lo.x:.3f} m wide, box allows {2 * hx:.3f}"
    assert lo.y >= -hy - EPS and hi.y <= hy + EPS, f"{piece_id}: {hi.y - lo.y:.3f} m deep, box allows {2 * hy:.3f}"
    assert hi.z <= hz + EPS, f"{piece_id}: {hi.z - lo.z:.3f} m tall, box allows {2 * hz:.3f}"
    for o in separate:
        slo, shi = _bounds([o])
        assert shi.z <= hz + LAMP_ALLOWANCE + EPS, f"{piece_id}: {o.name} top {shi.z:.3f} is too far above the box"
        assert slo.x >= -hx - EPS and shi.x <= hx + EPS and slo.y >= -hy - EPS and shi.y <= hy + EPS,             f"{piece_id}: {o.name} sticks out of the footprint"
    tris = sum(_triangles(o) for o in everything)
    assert tris <= max_triangles, f"{piece_id}: {tris} triangles, limit {max_triangles}"

    out = MODEL_DIR / f"{piece_id}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in everything:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False, export_animations=False, export_yup=True)
    log.info("MODEL %s: %d tris, %.2f x %.2f x %.2f m (w x h x d), parts=%s, %d KiB -> %s",
             piece_id, tris, hi.x - lo.x, hi.z - lo.z, hi.y - lo.y, [o.name for o in separate] or "-",
             out.stat().st_size // 1024, out.relative_to(ROOT))
    return out


def deg(degrees: float) -> float:
    """Degrees to radians, for rotation tuples."""
    return math.radians(degrees)
