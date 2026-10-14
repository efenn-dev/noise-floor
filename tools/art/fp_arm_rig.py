"""Build Noise Floor's mirrored, rigged first-person work-gloved arms.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/fp_arm_rig.py

Both arms are authored in Godot coordinates and converted point-by-point to Blender.  The
left arm therefore has genuinely mirrored mesh and bone data; neither export contains a
negative scale.  The grip centre is the scene origin.  The construction scene is discarded
after each export and every measurement/render is made from the re-imported GLB.

The rest pose is Grip.  Actions are two-key held poses containing bone rotations only.  The
glove uses a voxel-fused palm, thumb web and cuff with full-length continuous finger tubes
nested deeply into that shell.  Localized weights keep the joined visible surface closed.
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
SHOT_DIR = ROOT / ".shots"
FPS = 30
ACTION_NAMES = ("Grip", "Open", "Flat", "HoldMag", "Pinch", "Fist")
FINGERS = ("Index", "Middle", "Ring", "Pinky")
BONE_NAMES = (
    "Forearm", "Hand",
    "Thumb1", "Thumb2", "Thumb3",
    "Index1", "Index2", "Index3",
    "Middle1", "Middle2", "Middle3",
    "Ring1", "Ring2", "Ring3",
    "Pinky1", "Pinky2", "Pinky3",
)


def g2b(point):
    """Godot point -> Blender point, matching melee_common._hand_blender_point."""
    return Vector((point[0], -point[2], point[1]))


def b2g(point):
    """Blender point -> Godot point after GLB re-import."""
    return Vector((point.x, point.z, -point.y))


def mirrored(point, side):
    return Vector((side * point[0], point[1], point[2]))


def smooth(obj, sharp_caps=False):
    for poly in obj.data.polygons:
        poly.use_smooth = not (sharp_caps and len(poly.vertices) > 4)
    return obj


def weight_all(obj, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


def ellipsoid(name, centre_g, radii_g, mat, bone, segments=16, rings=10):
    centre = g2b(centre_g)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=centre)
    obj = bpy.context.object
    obj.name = name
    # g2b permutes Godot Y/Z into Blender Z/Y.
    obj.scale = (radii_g[0], radii_g[2], radii_g[1])
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    smooth(obj)
    return weight_all(obj, bone)


def capsule(name, start_g, end_g, radius, mat, bone, width=1.0, depth=1.0,
            segments=12, rings=8):
    """A rounded, overlapping segment aligned to a rest-pose bone."""
    start, end = g2b(start_g), g2b(end_g)
    direction = end - start
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=(start + end) * 0.5
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = (radius * width, radius * depth, direction.length * 0.54 + radius * 0.30)
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    smooth(obj)
    return weight_all(obj, bone)


def ring_tube(name, centres_g, radii, mat, ring_weights, sides=14):
    """Oval tube through Godot points, with explicit per-ring bone weights."""
    assert len(centres_g) == len(radii) == len(ring_weights)
    centres = [Vector(p) for p in centres_g]
    verts = []
    for index, centre in enumerate(centres):
        if index == 0:
            axis = centres[1] - centre
        elif index == len(centres) - 1:
            axis = centre - centres[index - 1]
        else:
            axis = centres[index + 1] - centres[index - 1]
        axis.normalize()
        across = Vector((1.0, 0.0, 0.0))
        cross = axis.cross(across)
        if cross.length < 1.0e-6:
            across = Vector((0.0, 1.0, 0.0))
            cross = axis.cross(across)
        cross.normalize()
        across = cross.cross(axis).normalized()
        rx, rc = radii[index]
        for step in range(sides):
            angle = 2.0 * math.pi * step / sides
            p = centre + across * (rx * math.cos(angle)) + cross * (rc * math.sin(angle))
            verts.append(tuple(g2b(p)))
    faces = [tuple(range(sides - 1, -1, -1))]
    last = (len(centres) - 1) * sides
    faces.append(tuple(last + step for step in range(sides)))
    for ring in range(len(centres) - 1):
        for step in range(sides):
            nxt = (step + 1) % sides
            a, b = ring * sides + step, ring * sides + nxt
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons[2:]:
        poly.use_smooth = True
    groups = {}
    for weights in ring_weights:
        for bone in weights:
            if bone not in groups:
                groups[bone] = obj.vertex_groups.new(name=bone)
    for ring, weights in enumerate(ring_weights):
        indices = list(range(ring * sides, (ring + 1) * sides))
        for bone, value in weights.items():
            groups[bone].add(indices, value, "REPLACE")
    return obj


def raw_finger_tube(name, chain, mat, base_width, tip_width, side):
    """Closed tapered finger source used by the glove's voxel union.

    The cross-section has a broad back, a slightly flattened palm face, a tiny integral side
    seam, shallow joint waists, and a subdued distal nail bulge.  These are silhouette changes
    in the same surface rather than independent floating detail objects.
    """
    lengths = [(chain[i + 1] - chain[i]).length for i in range(3)]
    total = sum(lengths)
    cumulative = (0.0, lengths[0], lengths[0] + lengths[1])
    samples = [(chain[0] - (chain[1] - chain[0]).normalized() * 0.010, -0.010, 1.02)]
    for segment, ts in enumerate(((0.0, 0.22, 0.48, 0.74, 1.0),
                                  (0.20, 0.46, 0.74, 1.0),
                                  (0.18, 0.43, 0.68, 0.84, 0.94, 1.0))):
        start, end = chain[segment], chain[segment + 1]
        for t in ts:
            s = cumulative[segment] + lengths[segment] * t
            joint_scale = 0.955 if t == 1.0 and segment < 2 else 1.0
            if segment == 2 and t >= 0.84:
                joint_scale *= {0.84: 0.96, 0.94: 0.68, 1.0: 0.18}[t]
            samples.append((start.lerp(end, t), s, joint_scale))

    sides = 14
    verts = []
    rings = []
    seam_sign = -1.0 if chain[0].y < 0.0 else 1.0
    for ring_index, (centre, s, profile_scale) in enumerate(samples):
        if ring_index == 0:
            axis = samples[1][0] - centre
        elif ring_index == len(samples) - 1:
            axis = centre - samples[ring_index - 1][0]
        else:
            axis = samples[ring_index + 1][0] - samples[ring_index - 1][0]
        axis.normalize()
        across = Vector((0.0, 1.0, 0.0))
        across = (across - axis * across.dot(axis)).normalized()
        back = across.cross(axis).normalized()
        if back.x * side < 0.0:
            back.negate()
        progress = max(0.0, min(1.0, s / total))
        half_width = (base_width * (1.0 - progress) + tip_width * progress) * profile_scale
        half_depth = half_width * (0.84 - 0.03 * progress)
        ring = []
        for step in range(sides):
            angle = 2.0 * math.pi * step / sides
            ca, sa = math.cos(angle), math.sin(angle)
            seam = 0.0009 * max(0.0, ca * seam_sign) ** 10
            nail_window = max(0.0, 1.0 - abs(progress - 0.86) / 0.16)
            nail = 0.0010 * nail_window * max(0.0, sa) ** 8
            palm_depth = half_depth * (0.76 if sa < 0.0 else 1.0)
            point = centre + across * ((half_width + seam) * ca) + back * (palm_depth * sa + nail)
            radial = math.hypot(point.x, point.z)
            if abs(point.y) < 0.043 and radial < 0.0178:
                scale = 0.0178 / max(radial, 1.0e-6)
                point.x *= scale
                point.z *= scale
            ring.append(len(verts))
            verts.append(tuple(g2b(point)))
        rings.append(ring)

    faces = [tuple(reversed(rings[0]))]
    for a, b in zip(rings, rings[1:]):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((a[step], a[nxt], b[nxt], b[step]))
    faces.append(tuple(rings[-1]))
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    smooth(obj)
    digit = name.split("_", 1)[0]
    groups = {bone: obj.vertex_groups.new(name=bone)
              for bone in ("Hand", f"{digit}1", f"{digit}2", f"{digit}3")}
    for ring_index, (_centre, along, _scale) in enumerate(samples):
        weights = digit_weights(digit, lengths, along)
        indices = rings[ring_index]
        for bone, value in weights.items():
            if value > 1.0e-6:
                groups[bone].add(indices, value, "REPLACE")
    return obj


def digit_weights(digit, lengths, along):
    """Localized LBS weights: rigid phalanges with narrow, smooth knuckle transitions."""
    joint1 = lengths[0]
    joint2 = lengths[0] + lengths[1]
    total = sum(lengths)
    nodes = [(-0.010, "Hand"), (0.004, f"{digit}1"),
             (joint1 - 0.006, f"{digit}1"), (joint1 + 0.006, f"{digit}2"),
             (joint2 - 0.005, f"{digit}2"), (joint2 + 0.005, f"{digit}3"),
             (total, f"{digit}3")]
    if along <= nodes[0][0]:
        return {nodes[0][1]: 1.0}
    if along >= nodes[-1][0]:
        return {nodes[-1][1]: 1.0}
    for (s0, bone0), (s1, bone1) in zip(nodes, nodes[1:]):
        if s0 <= along <= s1:
            if bone0 == bone1:
                return {bone0: 1.0}
            blend = (along - s0) / (s1 - s0)
            return {bone0: 1.0 - blend, bone1: blend}
    raise AssertionError((digit, along, nodes))


def fuse_glove(sources, mat, side):
    """Voxel-union the palm, then transfer its Hand/Forearm weights to the new shell."""
    bpy.ops.object.select_all(action="DESELECT")
    for source in sources:
        source.select_set(True)
    bpy.context.view_layer.objects.active = sources[0]
    bpy.ops.object.join()
    glove = bpy.context.object
    glove.name = "ContinuousGlove"
    glove.data.name = "ContinuousGlove"

    # Capture the broad wrist transition before fusing the overlapping palm construction forms.
    source_groups = {group.index: group.name for group in glove.vertex_groups}
    source_weights = []
    source_tree = KDTree(len(glove.data.vertices))
    for vertex in glove.data.vertices:
        source_tree.insert(vertex.co, vertex.index)
        weights = {source_groups[item.group]: item.weight for item in vertex.groups}
        total = sum(weights.values())
        source_weights.append({bone: value / total for bone, value in weights.items()})
    source_tree.balance()
    for group in list(glove.vertex_groups):
        glove.vertex_groups.remove(group)
    glove.data.remesh_voxel_size = 0.00105
    glove.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    smooth(glove)

    glove.data.calc_loop_triangles()
    target = 7500
    if len(glove.data.loop_triangles) > target:
        modifier = glove.modifiers.new("Production triangle budget", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = target / len(glove.data.loop_triangles)
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = glove
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    smooth(glove)

    glove.data.materials.clear()
    glove.data.materials.append(mat)
    groups = {name: glove.vertex_groups.new(name=name) for name in BONE_NAMES}
    for vertex in glove.data.vertices:
        point = b2g(vertex.co)
        radial = math.hypot(point.x, point.z)
        if abs(point.y) < 0.040 and radial < 0.0162:
            scale = 0.0162 / max(radial, 1.0e-6)
            point.x *= scale
            point.z *= scale
            vertex.co = g2b(point)

        transferred = {}
        neighbours = source_tree.find_n(vertex.co, 4)
        for _co, source_index, distance in neighbours:
            influence = 1.0 / (distance + 0.00035) ** 2
            for bone, value in source_weights[source_index].items():
                transferred[bone] = transferred.get(bone, 0.0) + influence * value
        total = sum(transferred.values())
        weights = {bone: value / total for bone, value in transferred.items()}
        weights = {bone: value for bone, value in weights.items()
                   if bone in {"Hand", "Forearm"}}
        if not weights:
            weights = {"Hand": 1.0}
        total = sum(weights.values())
        weights = {bone: value / total for bone, value in weights.items()}
        for bone, value in weights.items():
            if value > 1.0e-6:
                groups[bone].add([vertex.index], value, "REPLACE")
    return glove


def finger_rest(side):
    """Joint chains in Grip.  Each digit has exactly three phalanges."""
    ys = {"Index": -0.034, "Middle": -0.012, "Ring": 0.012, "Pinky": 0.034}
    # Middle is longest, then index, ring, pinky.  Curvature clears a 17 mm radius handle.
    lengths = {
        "Index": (0.038, 0.029, 0.022),
        "Middle": (0.041, 0.031, 0.023),
        "Ring": (0.039, 0.029, 0.022),
        "Pinky": (0.033, 0.024, 0.019),
    }
    result = {}
    for finger in FINGERS:
        y = ys[finger]
        root_z = 0.014 + (0.002 if finger in {"Index", "Pinky"} else 0.0)
        root = Vector((side * 0.058, y, root_z))
        directions = (
            Vector((side * -0.72, -0.02, 0.69)),
            Vector((side * -0.96, -0.02, -0.28)),
            Vector((side * -0.82, -0.03, -0.57)),
        )
        chain = [root]
        for length, direction in zip(lengths[finger], directions):
            chain.append(chain[-1] + direction.normalized() * length)
        result[finger] = chain
    thumb_lengths = (0.037, 0.031, 0.024)
    thumb_dirs = (
        Vector((side * -0.24, 0.36, -0.90)),
        Vector((side * -0.78, 0.32, -0.54)),
        # Tip stays on the -Z side of the handle instead of cutting across its axis.
        Vector((side * -0.55, 0.20, -0.81)),
    )
    thumb = [Vector((side * 0.061, -0.031, 0.018))]
    for length, direction in zip(thumb_lengths, thumb_dirs):
        thumb.append(thumb[-1] + direction.normalized() * length)
    result["Thumb"] = thumb
    return result


def bone_table(side):
    fingers = finger_rest(side)
    wrist = Vector((side * 0.048, -0.010, 0.108))
    sleeve_end = Vector((side * 0.066, -0.105, 0.414))
    bones = {
        "Forearm": (sleeve_end, wrist, None),
        "Hand": (wrist, fingers["Middle"][0], "Forearm"),
    }
    for digit in ("Thumb", *FINGERS):
        chain = fingers[digit]
        parent = "Hand"
        for index in range(3):
            name = f"{digit}{index + 1}"
            bones[name] = (chain[index], chain[index + 1], parent)
            parent = name
    assert tuple(bones) == BONE_NAMES
    return bones


def build_armature(side):
    bones = bone_table(side)
    data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, (head, tail, _parent) in bones.items():
        bone = data.edit_bones.new(name)
        bone.head = g2b(head)
        bone.tail = g2b(tail)
        bone.use_deform = True
        made[name] = bone
    for name, (_head, _tail, parent) in bones.items():
        if parent:
            made[name].parent = made[parent]
            made[name].use_connect = name not in {f"{finger}1" for finger in ("Thumb", *FINGERS)}
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def build_mesh(side, mats):
    parts = []
    glove, skin, sleeve = mats["glove"], mats["skin"], mats["sleeve"]
    fingers = finger_rest(side)

    # Broad overlapping metacarpal and heel volumes fuse into the palm; the thenar and web forms
    # carry the thumb into it. Full-length finger tubes are nested through this shell at the roots
    # but stay independent of one another, so the closed Grip rest pose cannot weld digits.
    glove_sources = [
        ellipsoid("PalmCore", (side * 0.052, 0.0, 0.048),
                  (0.029, 0.048, 0.059), glove, "Hand", 18, 12),
        ellipsoid("MetacarpalBridge", (side * 0.051, 0.0, 0.021),
                  (0.028, 0.049, 0.031), glove, "Hand", 18, 10),
        ellipsoid("PalmHeel", (side * 0.051, 0.002, 0.085),
                  (0.028, 0.043, 0.034), glove, "Hand", 16, 10),
        ellipsoid("ThenarPad", (side * 0.034, -0.027, 0.052),
                  (0.016, 0.022, 0.034), glove, "Hand", 16, 10),
        ellipsoid("ThumbWeb", (side * 0.046, -0.031, 0.013),
                  (0.019, 0.016, 0.023), glove, "Hand", 16, 10),
    ]
    widths = {
        "Index": (0.0101, 0.0075), "Middle": (0.0104, 0.0077),
        "Ring": (0.0100, 0.0073), "Pinky": (0.0088, 0.0065),
        "Thumb": (0.0108, 0.0078),
    }
    finger_sources = []
    for digit in ("Thumb", *FINGERS):
        finger_sources.append(raw_finger_tube(
            f"{digit}_Continuous", fingers[digit], glove, *widths[digit], side
        ))

    # The glove wrist and its slightly proud welt are part of the same union as the hand.
    glove_sources.append(ring_tube(
        "GloveWristSource",
        [(side * 0.050, -0.004, 0.077), (side * 0.049, -0.007, 0.093),
         (side * 0.048, -0.010, 0.108), (side * 0.049, -0.014, 0.121)],
        [(0.029, 0.041), (0.028, 0.039), (0.027, 0.037), (0.0315, 0.0405)],
        glove, [{"Hand": 1.0}, {"Hand": 0.82, "Forearm": 0.18},
                {"Hand": 0.38, "Forearm": 0.62}, {"Forearm": 1.0}], sides=18,
    ))
    glove_sources.append(ring_tube(
        "WristSeamSource",
        [(side * 0.049, -0.013, 0.1165), (side * 0.049, -0.014, 0.1220)],
        [(0.0325, 0.0415), (0.0320, 0.0410)], glove,
        [{"Hand": 0.18, "Forearm": 0.82}, {"Forearm": 1.0}], sides=18,
    ))
    parts.append(fuse_glove(glove_sources, glove, side))
    parts.extend(finger_sources)

    # The visible skin band is rigid to Forearm; the fused glove above carries its own broad
    # Hand/Forearm transition and flares over this band.
    parts.append(ring_tube(
        "SkinBand",
        [(side * 0.049, -0.014, 0.116), (side * 0.050, -0.018, 0.128),
         (side * 0.051, -0.022, 0.138)],
        [(0.0255, 0.0345), (0.0260, 0.0350), (0.0270, 0.0360)], skin,
        [{"Forearm": 1.0}] * 3,
    ))
    parts.append(ring_tube(
        "TurnedCuff",
        [(side * 0.051, -0.020, 0.134), (side * 0.053, -0.027, 0.157),
         (side * 0.055, -0.034, 0.181)],
        [(0.034, 0.044), (0.037, 0.047), (0.035, 0.045)], sleeve,
        [{"Forearm": 1.0}] * 3,
    ))
    parts.append(ring_tube(
        "ForearmSleeve",
        [(side * 0.054, -0.031, 0.171), (side * 0.057, -0.047, 0.227),
         (side * 0.061, -0.067, 0.294), (side * 0.064, -0.088, 0.366),
         (side * 0.066, -0.105, 0.414)],
        [(0.034, 0.044), (0.040, 0.048), (0.046, 0.053),
         (0.052, 0.059), (0.056, 0.063)], sleeve,
        [{"Forearm": 1.0}] * 5,
        sides=16,
    ))
    # Join only mesh parts.  Blender preserves named vertex groups and the three material slots.
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = "FPArm"
    mesh.data.name = "FPArm"
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Joining may leave the slots in construction order; exact names matter, order does not.
    assert {m.name for m in mesh.data.materials} == {"Arm Glove", "Arm Skin", "Arm Sleeve"}
    assert set(mesh.vertex_groups.keys()) == set(BONE_NAMES)
    return mesh


def bind(mesh, armature):
    mesh.parent = armature
    mesh.matrix_parent_inverse.identity()
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    modifier.use_bone_envelopes = False
    # Normalize every vertex explicitly; all geometry is intentionally influenced.
    for vertex in mesh.data.vertices:
        total = sum(group.weight for group in vertex.groups)
        assert total > 0.999 and abs(total - 1.0) < 1.0e-5, (vertex.index, total)


def target_chain(root, lengths, directions):
    chain = [Vector(root)]
    for length, direction in zip(lengths, directions):
        chain.append(chain[-1] + Vector(direction).normalized() * length)
    return chain


def fabrik(chain, target, iterations=24):
    """Reach target without scaling any phalanx; deterministic and adequate for Pinch."""
    points = [Vector(p) for p in chain]
    root = points[0].copy()
    target = Vector(target)
    lengths = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
    if (target - root).length >= sum(lengths):
        direction = (target - root).normalized()
        return target_chain(root, lengths, [direction] * len(lengths))
    for _ in range(iterations):
        points[-1] = target
        for i in range(len(points) - 2, -1, -1):
            direction = (points[i] - points[i + 1]).normalized()
            points[i] = points[i + 1] + direction * lengths[i]
        points[0] = root
        for i in range(len(points) - 1):
            direction = (points[i + 1] - points[i]).normalized()
            points[i + 1] = points[i] + direction * lengths[i]
    return points


def pose_targets(side):
    rest = finger_rest(side)
    result = {"Grip": rest}

    def finger_pose(kind):
        posed = {}
        for finger in FINGERS:
            chain = rest[finger]
            lengths = [(chain[i + 1] - chain[i]).length for i in range(3)]
            y = chain[0].y
            if kind == "Open":
                directions = [
                    (side * -0.12, 0.0, -0.99),
                    (side * -0.25, 0.0, -0.97),
                    (side * -0.38, 0.0, -0.92),
                ]
            elif kind == "Flat":
                inward = -0.08 if y > 0 else 0.08
                directions = [(side * -0.04, inward, -1.0)] * 3
            elif kind == "HoldMag":
                if finger == "Index":
                    directions = [(side * -0.15, 0.10, -0.98)] * 3
                else:
                    directions = [
                        (side * -0.88, -0.05, -0.47),
                        (side * -0.88, -0.05, 0.47),
                        (side * 0.05, -0.03, 1.0),
                    ]
            elif kind == "Fist":
                directions = [
                    (side * -0.72, 0.0, 0.69),
                    (side * -0.96, 0.0, -0.28),
                    (side * 0.18, 0.0, -0.98),
                ]
            else:
                raise ValueError(kind)
            posed[finger] = target_chain(chain[0], lengths, directions)
        return posed

    opened = finger_pose("Open")
    opened["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][i + 1] - rest["Thumb"][i]).length for i in range(3)],
        [(side * -0.55, -0.72, -0.42), (side * -0.70, -0.58, -0.42),
         (side * -0.76, -0.48, -0.44)],
    )
    result["Open"] = opened

    flat = finger_pose("Flat")
    flat["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][i + 1] - rest["Thumb"][i]).length for i in range(3)],
        [(side * -0.20, 0.05, -0.98), (side * -0.16, 0.05, -0.99),
         (side * -0.10, 0.04, -0.99)],
    )
    result["Flat"] = flat

    hold = finger_pose("HoldMag")
    hold["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][i + 1] - rest["Thumb"][i]).length for i in range(3)],
        [(side * -0.78, 0.28, -0.56), (side * -0.92, 0.18, 0.34),
         (side * 0.05, 0.04, 1.0)],
    )
    result["HoldMag"] = hold

    pinch_target = Vector((side * -0.002, -0.020, -0.052))
    pinch = finger_pose("Open")
    pinch["Index"] = fabrik(rest["Index"], pinch_target)
    pinch["Thumb"] = fabrik(rest["Thumb"], pinch_target)
    for finger in ("Middle", "Ring", "Pinky"):
        chain = rest[finger]
        lengths = [(chain[i + 1] - chain[i]).length for i in range(3)]
        pinch[finger] = target_chain(
            chain[0], lengths,
            [(side * -0.45, 0.0, -0.89), (side * -0.68, 0.0, -0.73),
             (side * -0.82, 0.0, -0.57)],
        )
    result["Pinch"] = pinch

    fist = finger_pose("Fist")
    fist["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][i + 1] - rest["Thumb"][i]).length for i in range(3)],
        [(side * -0.35, 0.42, -0.84), (side * -0.91, 0.20, -0.36),
         (side * -0.66, 0.05, 0.75)],
    )
    result["Fist"] = fist
    return result


def reset_pose(armature):
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)


def apply_target_pose(armature, targets):
    """Assign pose rotations from desired armature-space joint chains."""
    reset_pose(armature)
    bpy.context.view_layer.update()
    # Forearm and Hand deliberately remain in rest for every hand pose.
    for digit in ("Thumb", *FINGERS):
        chain = targets[digit]
        for index in range(3):
            pose_bone = armature.pose.bones[f"{digit}{index + 1}"]
            target_head = g2b(chain[index])
            target_tail = g2b(chain[index + 1])
            rest = pose_bone.bone.matrix_local.copy()
            rest_direction = (rest.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
            target_direction = (target_tail - target_head).normalized()
            swing = rest_direction.rotation_difference(target_direction)
            rotation = swing.to_matrix() @ rest.to_3x3()
            desired = Matrix.Translation(target_head) @ rotation.to_4x4()
            pose_bone.matrix = desired
            bpy.context.view_layer.update()
            # Connected-chain geometry makes translation numerically zero; never animate it.
            assert pose_bone.location.length < 2.0e-4, (pose_bone.name, pose_bone.location[:])
            pose_bone.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def make_actions(armature, side):
    armature.animation_data_create()
    targets = pose_targets(side)
    for name in ACTION_NAMES:
        action = bpy.data.actions.new(name)
        armature.animation_data.action = action
        for frame in (1, 2):
            bpy.context.scene.frame_set(frame)
            apply_target_pose(armature, targets[name])
            # Rotation-only channels.  Forearm remains identity but is keyed to document the hold.
            for pose_bone in armature.pose.bones:
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
        for slot in action.slots:
            bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
            if bag:
                for curve in bag.fcurves:
                    assert curve.data_path.endswith("rotation_quaternion"), curve.data_path
                    for point in curve.keyframe_points:
                        point.interpolation = "CONSTANT"
    armature.animation_data.action = None
    bpy.context.scene.frame_set(0)
    reset_pose(armature)
    return targets


def export_arm(side, mesh, armature):
    piece_id = "fp_arm_right" if side > 0 else "fp_arm_left"
    out = MODEL_DIR / f"{piece_id}.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_skins=True,
        export_animations=True, export_animation_mode="ACTIONS",
        export_bake_animation=True, export_force_sampling=False,
        export_frame_range=True,
    )
    return piece_id, out


def evaluated_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    points = [b2g(evaluated.matrix_world @ vertex.co) for vertex in data.vertices]
    evaluated.to_mesh_clear()
    return points


def look_at(obj, target_g):
    target = g2b(target_g)
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_prop(kind, side):
    grey = bpy.data.materials.get("Preview Grey") or bpy.data.materials.new("Preview Grey")
    grey.diffuse_color = (0.25, 0.28, 0.30, 1.0)
    if kind == "Grip":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.017, depth=0.6,
                                            location=g2b((0.0, 0.0, 0.0)))
        prop = bpy.context.object
        prop.name = "PREVIEW_ONLY_Handle"
    elif kind == "HoldMag":
        centre = Vector((side * 0.023, 0.0, -0.040))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(centre))
        prop = bpy.context.object
        prop.name = "PREVIEW_ONLY_Magazine"
        # Godot dimensions: X 22 mm, Y 30 mm, Z 120 mm.
        prop.scale = (0.022, 0.120, 0.030)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = prop.modifiers.new("Magazine edge bevel", "BEVEL")
        bevel.width = 0.002
        bevel.segments = 2
        bpy.context.view_layer.objects.active = prop
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    else:
        return None
    prop.data.materials.append(grey)
    return prop


def setup_preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.008, 0.011, 0.016)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.sensor_fit = "VERTICAL"
    camera_data.angle_y = math.radians(50.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    for name, point, energy, size in (
        ("Key", (0.55, -0.35, 0.42), 28.0, 0.55),
        ("Fill", (-0.32, -0.20, 0.28), 14.0, 0.45),
        ("Rim", (0.12, 0.38, 0.48), 22.0, 0.42),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = g2b(point)
        look_at(light, (0.03, -0.01, 0.16))
    return camera


def make_contact_sheet(paths):
    """Make a compact 3x3 proof sheet without depending on external image utilities."""
    import numpy as np

    tile = 512
    columns = 3
    rows = math.ceil(len(paths) / columns)
    canvas = np.zeros((rows * tile, columns * tile, 4), dtype=np.float32)
    canvas[:, :, 3] = 1.0
    for index, path in enumerate(paths):
        image = bpy.data.images.load(str(path), check_existing=False)
        width, height = image.size
        assert width == 1024 and height == 1024, (path, image.size[:])
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape((height, width, 4)).reshape(tile, 2, tile, 2, 4).mean(axis=(1, 3))
        row, column = divmod(index, columns)
        canvas[(rows - 1 - row) * tile:(rows - row) * tile,
               column * tile:(column + 1) * tile] = pixels
        bpy.data.images.remove(image)
    sheet = bpy.data.images.new("FP Arm V2 Contact Sheet", width=columns * tile,
                                height=rows * tile, alpha=True)
    sheet.pixels.foreach_set(canvas.ravel())
    sheet.filepath_raw = str(SHOT_DIR / "fp_arm_v2_sheet.png")
    sheet.file_format = "PNG"
    sheet.save()
    print("PREVIEW", sheet.filepath_raw)


def render_previews(piece_id, side, armature, actions):
    if side < 0:
        return
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    camera = setup_preview()
    armature.data.pose_position = "POSE"
    rendered = []

    # Roughly 25 cm from the hand, looking across the back at a three-quarter angle.
    camera.data.angle_y = math.radians(50.0)
    camera.location = g2b((0.235, -0.145, 0.175))
    look_at(camera, (0.025, 0.0, 0.035))
    for name in ACTION_NAMES:
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_v2_{name.lower()}.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        rendered.append(Path(scene.render.filepath))
        if prop:
            bpy.data.objects.remove(prop, do_unlink=True)

    # Palm-side close-ups for the two prop-contact poses.
    camera.location = g2b((-0.205, -0.145, 0.145))
    look_at(camera, (0.018, 0.0, 0.025))
    for name in ("Grip", "HoldMag", "Fist"):
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_v2_{name.lower()}_palm.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        if name != "Fist":
            rendered.append(Path(scene.render.filepath))
        if prop:
            bpy.data.objects.remove(prop, do_unlink=True)

    # Exact requested in-game-style first-person proof with the 34 mm diameter cylinder.
    armature.animation_data.action = actions["Grip"]
    scene.frame_set(1)
    bpy.context.view_layer.update()
    handle = add_preview_prop("Grip", side)
    camera.data.angle_y = math.radians(75.0)
    camera.location = g2b((0.25, 0.35, 0.65))
    look_at(camera, (0.0, 0.0, 0.0))
    scene.render.filepath = str(SHOT_DIR / "fp_arm_v2_first_person.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    bpy.data.objects.remove(handle, do_unlink=True)
    make_contact_sheet(rendered)


def validate_reimport(piece_id, out, side):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(out))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"
              and not any(c.name == "glTF_not_exported" for c in obj.users_collection)]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert len(meshes) == 1 and len(armatures) == 1, (meshes, armatures)
    mesh, armature = meshes[0], armatures[0]
    assert mesh.name == "FPArm" and armature.name == "Armature"
    assert mesh.parent == armature
    assert all(abs(value - 1.0) < 1.0e-6 for value in (*mesh.scale, *armature.scale))

    materials = sorted(mat.name for mat in mesh.data.materials if mat)
    assert materials == ["Arm Glove", "Arm Skin", "Arm Sleeve"], materials
    mesh.data.calc_loop_triangles()
    triangles = len(mesh.data.loop_triangles)
    assert triangles < 14000, triangles

    bones = armature.data.bones
    assert tuple(bones.keys()) == BONE_NAMES, tuple(bones.keys())
    parents = {bone.name: bone.parent.name if bone.parent else None for bone in bones}
    expected_parents = {"Forearm": None, "Hand": "Forearm"}
    for digit in ("Thumb", *FINGERS):
        expected_parents[f"{digit}1"] = "Hand"
        expected_parents[f"{digit}2"] = f"{digit}1"
        expected_parents[f"{digit}3"] = f"{digit}2"
    assert parents == expected_parents, parents

    actions = {action.name: action for action in bpy.data.actions}
    assert set(actions) == set(ACTION_NAMES), sorted(actions)
    for action in actions.values():
        paths = []
        for slot in action.slots:
            bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
            if bag:
                paths.extend(curve.data_path for curve in bag.fcurves)
        assert paths and all(path.endswith("rotation_quaternion") for path in paths), paths

    # Re-imported pose proof: Forearm is exactly its rest matrix in every action.  Print the
    # distal bone tails as compact evidence that all six held poses are distinct and usable.
    pose_tips = {}
    armature.data.pose_position = "POSE"
    for action_name in ACTION_NAMES:
        armature.animation_data_create()
        armature.animation_data.action = actions[action_name]
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        forearm = armature.pose.bones["Forearm"]
        rest_matrix = forearm.bone.matrix_local
        matrix_error = max(abs(forearm.matrix[row][column] - rest_matrix[row][column])
                           for row in range(4) for column in range(4))
        assert matrix_error < 1.0e-5, (action_name, matrix_error)
        pose_tips[action_name] = {
            digit: b2g(armature.matrix_world @ armature.pose.bones[f"{digit}3"].tail)
            for digit in ("Thumb", *FINGERS)
        }

    armature.animation_data_create()
    armature.animation_data.action = None
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    points = evaluated_points(mesh)
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    clearance_points = [p for p in points if abs(p.y) < 0.04]
    clearance = min(math.hypot(p.x, p.z) for p in clearance_points)
    nearest = min(clearance_points, key=lambda p: math.hypot(p.x, p.z))
    print("  nearest_clearance_vertex", tuple(round(value, 6) for value in nearest))
    assert clearance >= 0.015, clearance

    # Forearm's exported root is the measured centre of the geometric sleeve-end ring.  Using
    # its centre avoids bias toward one side of the wide oval end cap.
    sleeve_end = b2g(armature.matrix_world @ bones["Forearm"].head_local)
    sleeve_direction = sleeve_end.normalized()
    assert sleeve_direction.z > 0.92 and sleeve_direction.y < -0.10, sleeve_direction

    mag_centre = Vector((side * 0.023, 0.0, -0.040))
    mag_axis = Vector((0.0, 0.0, 1.0))
    # Rest mirror and root-at-grip checks.
    assert armature.matrix_world.translation.length < 1.0e-6
    assert mesh.matrix_world.translation.length < 1.0e-6
    if side > 0:
        assert hi.x > abs(lo.x)
    else:
        assert abs(lo.x) > hi.x

    chains = []
    for name in BONE_NAMES:
        chain = [name]
        parent = bones[name].parent
        while parent:
            chain.append(parent.name)
            parent = parent.parent
        chains.append(f"{name}<-" + "<-".join(chain[1:]) if len(chain) > 1 else name)
    bone_rest = {
        bone.name: (b2g(armature.matrix_world @ bone.head_local),
                    b2g(armature.matrix_world @ bone.tail_local))
        for bone in bones
    }
    glove_points = []
    for poly in mesh.data.polygons:
        if mesh.data.materials[poly.material_index].name == "Arm Glove":
            glove_points.extend(b2g(mesh.matrix_world @ mesh.data.vertices[i].co) for i in poly.vertices)
    hand_y = (min(point.y for point in glove_points), max(point.y for point in glove_points))
    knuckle_to_sleeve = (bone_rest["Forearm"][0] - bone_rest["Hand"][1]).length
    print("VALIDATION", piece_id)
    print("  bounds_godot", f"({lo.x:.4f},{lo.y:.4f},{lo.z:.4f})..({hi.x:.4f},{hi.y:.4f},{hi.z:.4f})")
    print("  triangles", triangles)
    print("  materials", materials)
    print("  bones", list(BONE_NAMES))
    print("  parent_chains", chains)
    print("  animations", sorted(actions))
    print("  pose_tips", {name: {digit: tuple(round(value, 4) for value in tip)
                                for digit, tip in tips.items()}
                           for name, tips in pose_tips.items()})
    print("  min_handle_clearance", f"{clearance:.5f}")
    print("  glove_hand_y", f"{hand_y[0]:.5f}..{hand_y[1]:.5f}")
    print("  middle_knuckle_to_sleeve_end", f"{knuckle_to_sleeve:.5f}")
    print("  sleeve_direction", f"({sleeve_direction.x:.5f},{sleeve_direction.y:.5f},{sleeve_direction.z:.5f})")
    print("  holdmag_centre", f"({mag_centre.x:.5f},{mag_centre.y:.5f},{mag_centre.z:.5f})",
          "axis", f"({mag_axis.x:.1f},{mag_axis.y:.1f},{mag_axis.z:.1f})")
    render_previews(piece_id, side, armature, actions)
    return {
        "bounds": (lo, hi), "triangles": triangles, "materials": materials,
        "bones": list(BONE_NAMES), "parents": parents, "animations": sorted(actions),
        "clearance": clearance, "sleeve_direction": sleeve_direction,
        "mag_centre": mag_centre, "mag_axis": mag_axis,
        "points": points, "bone_rest": bone_rest,
    }


def build_side(side):
    # The right-side validation imports actions.  Start the other side from a genuinely empty
    # file so Blender cannot suffix the required action names with .001.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    reset()
    bpy.context.scene.render.fps = FPS
    mats = {
        "glove": material("Arm Glove", (0.110, 0.030, 0.006), 0.0, 0.82),
        "skin": material("Arm Skin", (0.48, 0.235, 0.135), 0.0, 0.80),
        "sleeve": material("Arm Sleeve", (0.030, 0.040, 0.047), 0.0, 0.94),
    }
    armature = build_armature(side)
    # Build one canonical topology.  The left copy is mirrored by rewriting vertex data and
    # reversing winding, never by leaving a negative object/armature scale in the export.
    mesh = build_mesh(1, mats)
    if side < 0:
        for vertex in mesh.data.vertices:
            vertex.co.x = -vertex.co.x
        mesh.data.flip_normals()
        mesh.data.update()
    bind(mesh, armature)
    make_actions(armature, side)
    assert all(value > 0.0 for value in (*mesh.scale, *armature.scale))
    piece_id, out = export_arm(side, mesh, armature)
    return validate_reimport(piece_id, out, side)


def main():
    right = build_side(1)
    left = build_side(-1)
    # Prove the two exports are true coordinate mirrors, mesh and armature, from re-imported data.
    rlo, rhi = right["bounds"]
    llo, lhi = left["bounds"]
    assert abs(rlo.x + lhi.x) < 2.0e-5 and abs(rhi.x + llo.x) < 2.0e-5
    assert (rlo.yz - llo.yz).length < 2.0e-5 and (rhi.yz - lhi.yz).length < 2.0e-5
    assert right["triangles"] == left["triangles"]
    right_points = {(round(-point.x, 4), round(point.y, 4), round(point.z, 4))
                    for point in right["points"]}
    left_points = {(round(point.x, 4), round(point.y, 4), round(point.z, 4))
                   for point in left["points"]}
    assert right_points == left_points, (len(right_points - left_points), len(left_points - right_points))
    for name in BONE_NAMES:
        for right_point, left_point in zip(right["bone_rest"][name], left["bone_rest"][name]):
            assert abs(right_point.x + left_point.x) < 2.0e-5, (name, right_point, left_point)
            assert (right_point.yz - left_point.yz).length < 2.0e-5, (name, right_point, left_point)
    print("MIRROR_CHECK every mesh vertex and bone rest endpoint matches without negative scales")


if __name__ == "__main__":
    main()
