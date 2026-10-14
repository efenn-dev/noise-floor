"""Small shared helpers for the first-person melee asset scripts.

The geometry is authored Z-up in Blender.  Blender's glTF Y-up conversion makes that
Godot +Y.  Because kit.finish() also half-turns the model, author the striking side at
Blender -Y; after finish it is Blender +Y and therefore Godot -Z.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

from kit import ROOT, finish


def apply_bevel(obj, width: float, segments: int = 2):
    """Apply, rather than merely leave, a bevel modifier before GLB export."""
    mod = obj.modifiers.new("Applied edge bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.affect = "EDGES"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def profile_prism(name, yz_points, thickness: float, material_, bevel: float = 0.0):
    """Extrude a closed (Blender Y, Z) silhouette through X thickness."""
    count = len(yz_points)
    vertices = [(-thickness / 2, y, z) for y, z in yz_points]
    vertices += [(thickness / 2, y, z) for y, z in yz_points]
    faces = [tuple(range(count - 1, -1, -1)), tuple(range(count, count * 2))]
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if bevel:
        apply_bevel(obj, bevel, 2)
    return obj


def swept_oval(name, stations, radii, material_, sides: int = 12):
    """Make a gently curved handle along Z; stations are (Y, Z), radii are (X, Y)."""
    verts = []
    for (cy, z), (rx, ry) in zip(stations, radii):
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            verts.append((rx * math.cos(a), cy + ry * math.sin(a), z))
    faces = []
    rings = len(stations)
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple((rings - 1) * sides + i for i in range(sides)))
    for r in range(rings - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b = r * sides + i, r * sides + j
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def lathe(name, profile, material_, sides: int = 20, dents=()):
    """Turn an (Z, radius) profile; dents are (z centre, angle, depth, spread)."""
    verts = []
    for z, radius in profile:
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            r = radius
            for dz, da, depth, spread in dents:
                ad = abs((a - da + math.pi) % (2 * math.pi) - math.pi)
                if abs(z - dz) < spread and ad < 0.38:
                    falloff = (1 - abs(z - dz) / spread) * (1 - ad / 0.38)
                    r -= depth * falloff
            verts.append((r * math.cos(a), r * math.sin(a), z))
    faces = []
    rings = len(profile)
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple((rings - 1) * sides + i for i in range(sides)))
    for r in range(rings - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a, b = r * sides + i, r * sides + j
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def grip_anchor():
    """A zero-face separate part used only to measure finish()'s placement transform."""
    mesh = bpy.data.meshes.new("GripAnchor")
    mesh.from_pydata([(0.0, 0.0, 0.0)], [], [])
    obj = bpy.data.objects.new("Wheel_GripAnchor", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _world_bounds(objects):
    pts = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


def _godot(v):
    return Vector((v.x, v.z, -v.y))


def _look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def held_finish(piece_id: str, envelope, stated_length: float, expected_materials,
                preview_scale: float = 1.0):
    """Use kit.finish(), restore the grip-centred origin, overwrite, re-import and validate."""
    finish(piece_id, envelope, max_triangles=3000)
    body = bpy.data.objects[piece_id]
    anchor = bpy.data.objects["Wheel_GripAnchor"]
    grip = anchor.matrix_world.translation.copy()
    bpy.data.objects.remove(anchor, do_unlink=True)

    body.location -= grip
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    out = ROOT / "assets" / "models" / f"{piece_id}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False, export_animations=False, export_yup=True)

    # Validate the actual file, not the construction scene.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    bpy.ops.import_scene.gltf(filepath=str(out))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo_b, hi_b = _world_bounds(meshes)
    corners_g = [_godot(Vector((x, y, z)))
                 for x in (lo_b.x, hi_b.x) for y in (lo_b.y, hi_b.y) for z in (lo_b.z, hi_b.z)]
    lo = Vector((min(v.x for v in corners_g), min(v.y for v in corners_g), min(v.z for v in corners_g)))
    hi = Vector((max(v.x for v in corners_g), max(v.y for v in corners_g), max(v.z for v in corners_g)))
    dims = hi - lo
    tris = 0
    names = set()
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
        names.update(m.name for m in obj.data.materials if m)
    names = sorted(names)
    origin = _godot(meshes[0].matrix_world.translation)
    tip = Vector(((lo.x + hi.x) / 2, hi.y, (lo.z + hi.z) / 2))

    assert abs(dims.y - stated_length) <= 0.02, (piece_id, dims.y, stated_length)
    assert origin.length <= 0.0005, (piece_id, origin)
    assert tris < 3000, (piece_id, tris)
    assert names == sorted(expected_materials), (piece_id, names, expected_materials)

    # The sharpened material must sit toward Godot -Z (Blender +Y).
    if "Weapon Edge" in names:
        edge_z = []
        other_z = []
        for obj in meshes:
            for poly in obj.data.polygons:
                mat_name = obj.data.materials[poly.material_index].name
                bucket = edge_z if mat_name == "Weapon Edge" else other_z
                bucket.extend(-((obj.matrix_world @ obj.data.vertices[i].co).y) for i in poly.vertices)
        assert sum(edge_z) / len(edge_z) < sum(other_z) / len(other_z), piece_id

    print("VALIDATION", piece_id,
          "bounds_godot", f"({lo.x:.4f},{lo.y:.4f},{lo.z:.4f})..({hi.x:.4f},{hi.y:.4f},{hi.z:.4f})",
          "grip_origin", f"({origin.x:.4f},{origin.y:.4f},{origin.z:.4f})",
          "tip", f"({tip.x:.4f},{tip.y:.4f},{tip.z:.4f})",
          "triangles", tris, "materials", names)

    # Side preview: mostly along +X, with a little view of the striking side.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.055, 0.065, 0.075)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(0.36, dims.y * 1.18) * preview_scale
    centre_z = (lo_b.z + hi_b.z) / 2
    camera.location = (1.4, -0.42, centre_z + 0.02)
    _look_at(camera, (0.0, 0.0, centre_z))
    for name, loc, energy, size in (
            ("Key", (1.5, -1.2, centre_z + 1.0), 850.0, 1.2),
            ("Fill", (-0.8, 0.8, centre_z + 0.4), 500.0, 1.0)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = loc
        _look_at(light, (0.0, 0.0, centre_z))
    shot_dir = ROOT / ".shots"
    shot_dir.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(shot_dir / f"{piece_id}.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    return out
