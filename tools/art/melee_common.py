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


# First-person hands are authored in Godot coordinates because their grip convention is more
# important than the build-piece convention used by kit.finish().  glTF's Y-up conversion maps a
# Blender point (x, y, z) to Godot (x, z, -y), so every generated vertex goes through this function.
def _hand_blender_point(point):
    return Vector((point[0], -point[2], point[1]))


def _hand_godot_point(point):
    return Vector((point.x, point.z, -point.y))


def _hand_ellipsoid(name, centre, radii, material_, segments=12, rings=6):
    """Low-poly, transform-applied ellipsoid in Godot coordinates."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         location=_hand_blender_point(centre))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (radii[0], radii[2], radii[1])
    obj.data.materials.append(material_)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _hand_segment(name, start, end, radius, material_, width_scale=1.0):
    """Rounded phalanx between two Godot-space points, with all transforms applied."""
    a = _hand_blender_point(start)
    b = _hand_blender_point(end)
    direction = b - a
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (radius * width_scale, radius, direction.length / 2 + radius * 0.42)
    obj.data.materials.append(material_)
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _hand_taper(name, centres, radii, material_, sides=12):
    """Tapered oval tube through Godot-space centres; radii are (sideways X, cross-arm)."""
    vertices = []
    directions = []
    for i in range(len(centres)):
        if i == 0:
            direction = Vector(centres[1]) - Vector(centres[0])
        elif i == len(centres) - 1:
            direction = Vector(centres[-1]) - Vector(centres[-2])
        else:
            direction = Vector(centres[i + 1]) - Vector(centres[i - 1])
        directions.append(direction.normalized())
    for centre, (side_radius, cross_radius), direction in zip(centres, radii, directions):
        across = Vector((1.0, 0.0, 0.0))
        cross = direction.cross(across).normalized()
        for i in range(sides):
            angle = 2.0 * math.pi * i / sides
            point = (Vector(centre) + across * (side_radius * math.cos(angle))
                     + cross * (cross_radius * math.sin(angle)))
            vertices.append(tuple(_hand_blender_point(point)))
    faces = [tuple(range(sides - 1, -1, -1))]
    last = (len(centres) - 1) * sides
    faces.append(tuple(last + i for i in range(sides)))
    for ring in range(len(centres) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            a = ring * sides + i
            b = ring * sides + j
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material_)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons[2:]:
        poly.use_smooth = True
    return obj


def _hand_look_at(obj, target_godot):
    target = _hand_blender_point(target_godot)
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def build_fp_hand(piece_id: str, side: int):
    """Build, export, re-import, validate, and preview one grip-centred first-person hand.

    `side` is +1 for the right hand and -1 for the left.  Mirroring happens while vertices are
    authored, never with a negative object scale, so normals and winding remain valid.
    """
    from kit import material, reset

    assert side in (-1, 1)
    reset()
    glove = material("Arm Glove", (0.22, 0.095, 0.035), 0.0, 0.88)
    sleeve = material("Arm Sleeve", (0.035, 0.048, 0.052), 0.0, 0.96)
    skin = material("Arm Skin", (0.48, 0.245, 0.145), 0.0, 0.82)

    parts = []
    # Palm and heel: the inner face stops at 17 mm, leaving the requested handle bore clear.
    parts.append(_hand_ellipsoid("Palm", (side * 0.044, 0.0, 0.031),
                                  (0.027, 0.046, 0.055), glove, 16, 8))
    parts.append(_hand_ellipsoid("Palm_Heel", (side * 0.046, -0.003, 0.073),
                                  (0.027, 0.041, 0.035), glove, 14, 7))

    # Four two-segment fingers follow the outside of a 34 mm handle.  Staggering and changing
    # their sizes makes the glove read as a hand instead of four identical tubes.
    finger_y = (-0.034, -0.012, 0.011, 0.033)
    finger_scale = (0.88, 1.02, 1.0, 0.82)
    for index, (y, scale) in enumerate(zip(finger_y, finger_scale), 1):
        radius = 0.0075 * scale
        u0, z0 = 0.0365, 0.004
        u1, z1 = 0.010, 0.0355
        u2, z2 = -0.0305, 0.020
        p0 = (side * u0, y, z0)
        p1 = (side * u1, y - 0.0015, z1)
        p2 = (side * u2, y - 0.0025, z2)
        parts.append(_hand_segment(f"Finger_{index}_Proximal", p0, p1, radius, glove, 1.08))
        parts.append(_hand_segment(f"Finger_{index}_Distal", p1, p2, radius * 0.92, glove, 1.04))
        parts.append(_hand_ellipsoid(f"Knuckle_{index}",
                                      (side * 0.069, y, 0.019 + 0.002 * (index % 2)),
                                      (0.010, radius * 1.18, 0.013), glove, 12, 6))

    # The thumb crosses the target-facing (-Z) side and lies over the curled fingers.
    thumb0 = (side * 0.058, -0.022, -0.002)
    thumb1 = (side * 0.034, -0.006, -0.032)
    thumb2 = (side * -0.006, 0.008, -0.037)
    parts.append(_hand_segment("Thumb_Proximal", thumb0, thumb1, 0.0105, glove, 1.14))
    parts.append(_hand_segment("Thumb_Distal", thumb1, thumb2, 0.0092, glove, 1.10))
    parts.append(_hand_ellipsoid("Thumb_Knuckle", (side * 0.061, -0.020, -0.006),
                                  (0.013, 0.012, 0.015), glove, 12, 6))

    # Glove wrist, a visible skin break, then a heavy canvas cuff and tapered jacket forearm.
    direction = Vector((side * 0.020, -0.259, 0.966)).normalized()
    wrist_centres = [(side * 0.047, -0.010, 0.082), (side * 0.049, -0.018, 0.111)]
    parts.append(_hand_taper("Glove_Wrist", wrist_centres,
                             [(0.028, 0.039), (0.026, 0.036)], glove))
    skin_centres = [(side * 0.049, -0.018, 0.108), (side * 0.051, -0.024, 0.132)]
    parts.append(_hand_taper("Skin_Band", skin_centres,
                             [(0.0255, 0.035), (0.0265, 0.036)], skin))
    cuff_centres = [(side * 0.050, -0.023, 0.128), (side * 0.054, -0.034, 0.168)]
    parts.append(_hand_taper("Sleeve_Cuff", cuff_centres,
                             [(0.034, 0.044), (0.036, 0.046)], sleeve))
    sleeve_centres = [(side * 0.053, -0.031, 0.158),
                      (side * 0.058, -0.052, 0.237),
                      (side * 0.063, -0.075, 0.322),
                      (side * 0.067, -0.098, 0.407)]
    parts.append(_hand_taper("Forearm_Sleeve", sleeve_centres,
                             [(0.033, 0.043), (0.040, 0.049),
                              (0.047, 0.055), (0.054, 0.061)], sleeve, 14))

    # Join for a single mesh with three material slots, set the measured grip anchor to (0,0,0),
    # and ensure every transform is baked before export.
    anchor = bpy.data.objects.new("GripAnchor", None)
    bpy.context.collection.objects.link(anchor)
    anchor.location = _hand_blender_point((0.0, 0.0, 0.0))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = piece_id
    body.data.name = piece_id
    bpy.context.scene.cursor.location = anchor.matrix_world.translation
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    assert body.matrix_world.translation.length < 1.0e-7

    out = ROOT / "assets" / "models" / f"{piece_id}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False, export_animations=False, export_yup=True)
    measured_anchor = _hand_godot_point(anchor.matrix_world.translation)
    print("ANCHOR", piece_id, "grip_godot",
          f"({measured_anchor.x:.4f},{measured_anchor.y:.4f},{measured_anchor.z:.4f})")

    # Delete the authored scene and validate only data loaded back out of the GLB.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    bpy.ops.import_scene.gltf(filepath=str(out))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    points = []
    tris = 0
    material_names = set()
    sleeve_points = []
    glove_points = []
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
        material_names.update(mat.name for mat in obj.data.materials if mat)
        for vertex in obj.data.vertices:
            points.append(_hand_godot_point(obj.matrix_world @ vertex.co))
        for poly in obj.data.polygons:
            poly_material = obj.data.materials[poly.material_index].name
            converted = [_hand_godot_point(obj.matrix_world @ obj.data.vertices[i].co)
                         for i in poly.vertices]
            if poly_material == "Arm Sleeve":
                sleeve_points.extend(converted)
            elif poly_material == "Arm Glove":
                glove_points.extend(converted)
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    clearance_points = [p for p in points if abs(p.y) < 0.04]
    min_clearance = min(math.hypot(p.x, p.z) for p in clearance_points)
    # Measure the grip itself, excluding the sloped wrist and sleeve behind it.
    hand_points = [p for p in glove_points if -0.06 < p.z < 0.075]
    hand_span = max(p.y for p in hand_points) - min(p.y for p in hand_points)
    far_projection = max(p.dot(direction) for p in sleeve_points)
    far_ring = [p for p in sleeve_points if p.dot(direction) > far_projection - 0.004]
    sleeve_end = sum(far_ring, Vector()) / len(far_ring)
    sleeve_direction = sleeve_end.normalized()
    down_angle = math.degrees(math.atan2(-sleeve_direction.y, sleeve_direction.z))
    origin = _hand_godot_point(meshes[0].matrix_world.translation)
    expected = {"Arm Glove", "Arm Sleeve", "Arm Skin"}
    assert origin.length < 0.0005, (piece_id, origin)
    assert tris < 6000, (piece_id, tris)
    assert material_names == expected, (piece_id, material_names)
    assert min_clearance >= 0.015, (piece_id, min_clearance)
    assert 0.080 <= hand_span <= 0.105, (piece_id, hand_span)
    assert sleeve_direction.z > 0.90 and sleeve_direction.y < -0.10, (piece_id, sleeve_direction)
    assert 8.0 <= down_angle <= 22.0, (piece_id, down_angle)
    if side > 0:
        assert hi.x > abs(lo.x), (piece_id, lo.x, hi.x)
    else:
        assert abs(lo.x) > hi.x, (piece_id, lo.x, hi.x)

    print("VALIDATION", piece_id,
          "bounds_godot", f"({lo.x:.4f},{lo.y:.4f},{lo.z:.4f})..({hi.x:.4f},{hi.y:.4f},{hi.z:.4f})",
          "triangles", tris, "materials", sorted(material_names),
          "min_handle_clearance", f"{min_clearance:.4f}",
          "hand_y_span", f"{hand_span:.4f}",
          "sleeve_direction", f"({sleeve_direction.x:.4f},{sleeve_direction.y:.4f},{sleeve_direction.z:.4f})",
          "down_angle_deg", f"{down_angle:.2f}")

    # Preview-only 34 mm test handle.  It is created after export and can never enter the GLB.
    preview_grey = bpy.data.materials.new("Preview Handle")
    preview_grey.diffuse_color = (0.24, 0.27, 0.29, 1.0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.017, depth=0.6,
                                        location=_hand_blender_point((0.0, 0.0, 0.0)))
    handle = bpy.context.object
    handle.name = "PREVIEW_ONLY_Handle"
    handle.data.materials.append(preview_grey)
    apply_bevel(handle, 0.002, 2)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.010, 0.014, 0.018)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.sensor_fit = "VERTICAL"
    camera_data.angle_y = math.radians(75.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    for name, location, energy, size in (
            ("Key", (0.55, 0.35, 0.45), 65.0, 0.7),
            ("Fill", (-0.45, 0.15, 0.25), 28.0, 0.6),
            ("Rim", (0.0, -0.15, 0.65), 42.0, 0.5)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = _hand_blender_point(location)
        _hand_look_at(light, (0.0, -0.02, 0.16))
    shot_dir = ROOT / ".shots"
    shot_dir.mkdir(parents=True, exist_ok=True)
    camera.location = _hand_blender_point((0.25, 0.35, 0.65))
    _hand_look_at(camera, (0.0, 0.0, 0.0))
    scene.render.filepath = str(shot_dir / f"{piece_id}_fp.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    camera.location = _hand_blender_point((0.72 * side, 0.03, 0.22))
    _hand_look_at(camera, (side * 0.025, -0.035, 0.19))
    scene.render.filepath = str(shot_dir / f"{piece_id}_side.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    return out
