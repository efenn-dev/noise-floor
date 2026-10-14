"""Build Noise Floor's first-person arms from MPFB 2.0.18's CC0 human.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/fp_arm_mpfb.py

The MPFB HumanService creates a moderately muscular adult male and RigService supplies the
game_engine skeleton and weights.  Native right and left hands are cut from that human; the
left is never mirrored.  MPFB weights are merged onto the game's compact 17-bone contract,
then the anatomically correct hand is skinned directly into the Grip rest pose.  The jacket
sleeve, turned cuff and glove seam are deterministic procedural additions.

Important axis contract: authored points are in Godot coordinates and g2b maps them to
Blender.  glTF's Y-up conversion maps them back on import.  The grip centre is the scene
origin, the handle runs along Godot +Y, and every validation measurement is taken from the
re-imported GLB rather than the construction scene.
"""

import importlib
import math
import os
import sys
from pathlib import Path

import addon_utils
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import material  # noqa: E402


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
MACRO_SETTINGS = {
    "gender": 0.95,
    "age": 0.52,
    "muscle": 0.67,
    "weight": 0.52,
    "proportions": 0.55,
    "height": 0.55,
    "cupsize": 0.5,
    "firmness": 0.5,
    "race": {"asian": 0.33, "caucasian": 0.34, "african": 0.33},
}


def g2b(point):
    """Godot point/vector -> Blender point/vector for a Y-up glTF round trip."""
    return Vector((point[0], -point[2], point[1]))


def b2g(point):
    """Blender point/vector -> Godot point/vector after glTF re-import."""
    return Vector((point.x, point.z, -point.y))


def clean_scene(remove_actions=False):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.armatures, bpy.data.curves,
                       bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)
    if remove_actions:
        for action in list(bpy.data.actions):
            bpy.data.actions.remove(action)


def enable_mpfb():
    """Enable MPFB while keeping its generated logs inside this task's allowed tree.

    Under --factory-startup Blender does not create an extension preferences entry until
    registration starts, while MPFB asks for preferences during registration.  Pre-importing
    the extension, supplying deterministic preferences, and enabling with default_set=True
    gives MPFB the same entry the UI normally creates.  No preference file is saved.
    """
    runtime = SHOT_DIR / ".mpfb_runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    module_name = "bl_ext.blender_org.mpfb"
    module = importlib.import_module(module_name)

    def scripted_preference(name):
        if name == "mpfb_user_data":
            return str(runtime)
        if name in {"mh_auto_user_data", "mpfb_codechecks"}:
            return False
        return ""

    module.get_preference = scripted_preference
    module.__time__ = os.path.getmtime(module.__file__)
    enabled = addon_utils.enable(module_name, default_set=True, persistent=False)
    assert enabled is not None and getattr(enabled, "__addon_enabled__", False)
    from bl_ext.blender_org.mpfb.services import HumanService, RigService, TargetService
    print("MPFB", enabled.VERSION, "enabled from", enabled.__file__)
    return HumanService, RigService, TargetService


def source_name(digit, index, suffix):
    return f"{digit.lower()}_0{index}_{suffix}"


def output_name(digit, index):
    return f"{digit}{index}"


def source_side(side):
    # MakeHuman names anatomical right on its negative-X side.
    return "r" if side > 0 else "l"


def target_chain(root, lengths, directions):
    chain = [Vector(root)]
    for length, direction in zip(lengths, directions):
        chain.append(chain[-1] + Vector(direction).normalized() * length)
    return chain


def fabrik(chain, target, iterations=32):
    points = [Vector(point) for point in chain]
    root = points[0].copy()
    target = Vector(target)
    lengths = [(points[index + 1] - points[index]).length for index in range(len(points) - 1)]
    if (target - root).length >= sum(lengths):
        direction = (target - root).normalized()
        return target_chain(root, lengths, [direction] * len(lengths))
    for _ in range(iterations):
        points[-1] = target
        for index in range(len(points) - 2, -1, -1):
            direction = (points[index] - points[index + 1]).normalized()
            points[index] = points[index + 1] + direction * lengths[index]
        points[0] = root
        for index in range(len(points) - 1):
            direction = (points[index + 1] - points[index]).normalized()
            points[index + 1] = points[index] + direction * lengths[index]
    return points


def orientation_with_y(source_rotation, target_direction):
    """Keep source roll while swinging its local +Y onto target_direction."""
    source_y = (source_rotation @ Vector((0.0, 1.0, 0.0))).normalized()
    swing = source_y.rotation_difference(Vector(target_direction).normalized())
    return swing.to_matrix() @ source_rotation


def hand_transform(source_armature, side):
    """Rigidly align MPFB's native palm frame with the game's grip frame."""
    suffix = source_side(side)
    bones = source_armature.data.bones
    wrist = bones[f"hand_{suffix}"].head_local.copy()
    roots = [bones[source_name(digit, 1, suffix)].head_local.copy()
             for digit in FINGERS]
    source_long = (sum(roots, Vector()) / len(roots) - wrist).normalized()
    source_across = bones[f"pinky_01_{suffix}"].head_local - bones[f"index_01_{suffix}"].head_local
    source_across = (source_across - source_long * source_across.dot(source_long)).normalized()
    source_normal = (side * source_long.cross(source_across)).normalized()
    source_across = (side * source_normal.cross(source_long)).normalized()
    source_basis = Matrix((source_long, source_across, source_normal)).transposed()

    target_wrist_g = Vector((side * 0.052, -0.010, 0.112))
    target_long_g = Vector((side * 0.105, 0.0, -0.9945)).normalized()
    target_across_g = Vector((0.0, 1.0, 0.0))
    target_normal_g = (side * target_long_g.cross(target_across_g)).normalized()
    target_across_g = (side * target_normal_g.cross(target_long_g)).normalized()
    target_basis = Matrix((g2b(target_long_g), g2b(target_across_g),
                           g2b(target_normal_g))).transposed()
    rotation = target_basis @ source_basis.transposed()
    transform = (Matrix.Translation(g2b(target_wrist_g)) @ rotation.to_4x4()
                 @ Matrix.Translation(-wrist))
    assert abs(rotation.determinant() - 1.0) < 1.0e-5
    return transform, rotation, target_wrist_g


def grip_directions(side, digit):
    if digit == "Thumb":
        return (
            (side * -0.20, 0.12, -0.97),
            (side * -0.56, 0.08, -0.82),
            (side * -0.61, 0.05, -0.79),
        )
    # Centres follow a broad arc around the 17 mm handle rather than collapsing
    # toward its axis.  Small Y offsets stop neighbouring fingers from clipping.
    spread = {"Index": -0.025, "Middle": -0.008, "Ring": 0.008, "Pinky": 0.025}[digit]
    return (
        (side * -0.50, spread, -0.866),
        (side * -0.85, spread * 0.3, -0.527),
        (side * -0.99, spread * 0.2, 0.14),
    )


def make_rest_definition(source_armature, side):
    suffix = source_side(side)
    source_bones = source_armature.data.bones
    hand_xform, hand_rotation, wrist_g = hand_transform(source_armature, side)
    sleeve_end_g = Vector((side * 0.070, -0.104, 0.424))
    definition = {
        "Forearm": (sleeve_end_g, wrist_g, None),
    }

    source_hand = source_bones[f"hand_{suffix}"]
    hand_head = b2g(hand_xform @ source_hand.head_local)
    hand_tail = b2g(hand_xform @ source_hand.tail_local)
    definition["Hand"] = (hand_head, hand_tail, "Forearm")

    chains = {}
    for digit in ("Thumb", *FINGERS):
        source_chain = [source_bones[source_name(digit, 1, suffix)].head_local.copy()]
        for index in range(1, 4):
            source_chain.append(source_bones[source_name(digit, index, suffix)].tail_local.copy())
        lengths = [(source_chain[index + 1] - source_chain[index]).length for index in range(3)]
        target_root = b2g(hand_xform @ source_chain[0])
        chain = target_chain(target_root, lengths, grip_directions(side, digit))
        chains[digit] = chain
        parent = "Hand"
        for index in range(3):
            name = output_name(digit, index + 1)
            definition[name] = (chain[index], chain[index + 1], parent)
            parent = name
    assert tuple(definition) == BONE_NAMES
    return definition, chains, hand_xform, hand_rotation


def build_armature(source_armature, side):
    definition, chains, hand_xform, hand_rotation = make_rest_definition(source_armature, side)
    suffix = source_side(side)
    source_bones = source_armature.data.bones
    data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    rotations = {}

    source_forearm = source_bones[f"lowerarm_{suffix}"]
    source_forearm_rotation = source_forearm.matrix_local.to_3x3()
    base_forearm_rotation = hand_rotation @ source_forearm_rotation
    forearm_direction = g2b(definition["Forearm"][1] - definition["Forearm"][0]).normalized()
    rotations["Forearm"] = orientation_with_y(base_forearm_rotation, forearm_direction)
    rotations["Hand"] = hand_rotation @ source_bones[f"hand_{suffix}"].matrix_local.to_3x3()
    for digit in ("Thumb", *FINGERS):
        for index in range(1, 4):
            name = output_name(digit, index)
            source_rotation = source_bones[source_name(digit, index, suffix)].matrix_local.to_3x3()
            base_rotation = hand_rotation @ source_rotation
            direction = g2b(definition[name][1] - definition[name][0]).normalized()
            rotations[name] = orientation_with_y(base_rotation, direction)

    for name, (head_g, tail_g, _parent) in definition.items():
        bone = data.edit_bones.new(name)
        bone.head = g2b(head_g)
        bone.tail = g2b(tail_g)
        bone.align_roll(rotations[name] @ Vector((0.0, 0.0, 1.0)))
        bone.use_deform = True
        made[name] = bone
    for name, (_head, _tail, parent) in definition.items():
        if parent:
            made[name].parent = made[parent]
            made[name].use_connect = name.endswith(("2", "3"))
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True

    # Exact source-rest -> target-rest skin transforms.  The forearm is anchored
    # at the wrist because the output sleeve bone is deliberately longer.
    transforms = {"Hand": hand_xform}
    for digit in ("Thumb", *FINGERS):
        for index in range(1, 4):
            target_name = output_name(digit, index)
            source_bone = source_bones[source_name(digit, index, suffix)]
            target_bone = armature.data.bones[target_name]
            transforms[target_name] = target_bone.matrix_local @ source_bone.matrix_local.inverted()
            assert (transforms[target_name] @ source_bone.head_local - target_bone.head_local).length < 1.0e-5
            assert (transforms[target_name] @ source_bone.tail_local - target_bone.tail_local).length < 1.0e-5
    src_tail = source_forearm.tail_local.copy()
    dst_tail = armature.data.bones["Forearm"].tail_local.copy()
    source_axis = (source_forearm.tail_local - source_forearm.head_local).normalized()
    target_axis = (armature.data.bones["Forearm"].tail_local
                   - armature.data.bones["Forearm"].head_local).normalized()
    relative_rotation = source_axis.rotation_difference(target_axis).to_matrix()
    transforms["Forearm"] = (Matrix.Translation(dst_tail) @ relative_rotation.to_4x4()
                              @ Matrix.Translation(-src_tail))
    return armature, definition, chains, transforms


def nearest_mapping(source_armature, source_bone_name, side):
    suffix = source_side(side)
    direct = {
        f"lowerarm_{suffix}": "Forearm",
        f"hand_{suffix}": "Hand",
    }
    for digit in ("Thumb", *FINGERS):
        for index in range(1, 4):
            direct[source_name(digit, index, suffix)] = output_name(digit, index)
    if source_bone_name in direct:
        return direct[source_bone_name]
    if not source_bone_name.endswith(f"_{suffix}"):
        return None
    lower = source_bone_name.lower()
    if "upperarm" in lower or "lowerarm" in lower or "twist" in lower:
        return "Forearm"
    if "metacarp" in lower or "palm" in lower or "hand" in lower:
        return "Hand"
    for digit in ("Thumb", *FINGERS):
        if digit.lower() in lower:
            # Any optional MPFB metacarpal/carpal helper is nearest to the palm;
            # extra phalanx/twist helpers go to the nearest retained digit bone.
            if "meta" in lower or "carp" in lower:
                return "Hand"
            digits = [index for index in range(1, 4) if f"0{index}" in lower]
            return output_name(digit, digits[0] if digits else 1)
    return None


def source_vertex_weights(source_mesh, source_armature, side):
    index_names = {group.index: group.name for group in source_mesh.vertex_groups}
    source_bones = {bone.name for bone in source_armature.data.bones}
    result = []
    influences = []
    for vertex in source_mesh.data.vertices:
        merged = {}
        for item in vertex.groups:
            group_name = index_names[item.group]
            if group_name not in source_bones:
                continue
            target_name = nearest_mapping(source_armature, group_name, side)
            if target_name:
                merged[target_name] = merged.get(target_name, 0.0) + item.weight
        total = sum(merged.values())
        influences.append(total)
        if total > 1.0e-8:
            merged = {name: value / total for name, value in merged.items()}
            if len(merged) > 4:
                strongest = sorted(merged.items(), key=lambda item: item[1], reverse=True)[:4]
                strongest_total = sum(value for _name, value in strongest)
                merged = {name: value / strongest_total for name, value in strongest}
        result.append(merged)
    return result, influences


def extract_mpfb_arm(source_mesh, source_armature, output_armature, side, transforms, mats):
    suffix = source_side(side)
    body_group = source_mesh.vertex_groups.get("body")
    assert body_group is not None
    body_index = body_group.index
    body_vertices = {vertex.index for vertex in source_mesh.data.vertices
                     if any(item.group == body_index and item.weight > 0.5 for item in vertex.groups)}
    source_weights, source_influences = source_vertex_weights(source_mesh, source_armature, side)
    # Evaluate MPFB's target shape keys but never its freshly added armature modifier.
    # Letting that modifier into this dependency-graph copy can expose a transient pose
    # and sporadically displace a complete vertex island during the first side build.
    for modifier in source_mesh.modifiers:
        if modifier.type == "ARMATURE":
            modifier.show_viewport = False
            modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source_mesh.evaluated_get(depsgraph)
    source_data = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    mesh_to_rig = source_armature.matrix_world.inverted() @ source_mesh.matrix_world
    normal_to_rig = mesh_to_rig.to_3x3().inverted().transposed()
    source_positions = [mesh_to_rig @ vertex.co for vertex in source_data.vertices]
    source_normals = [(normal_to_rig @ vertex.normal).normalized()
                      for vertex in source_data.vertices]
    source_bones = source_armature.data.bones
    wrist = source_bones[f"hand_{suffix}"].head_local.copy()
    elbow = source_bones[f"lowerarm_{suffix}"].head_local.copy()
    proximal = (elbow - wrist).normalized()
    proximity = [(point - wrist).dot(proximal) for point in source_positions]

    selected_faces = []
    for polygon in source_data.polygons:
        indices = list(polygon.vertices)
        if not all(index in body_vertices for index in indices):
            continue
        if sum(proximity[index] for index in indices) / len(indices) > 0.056:
            continue
        if min(source_influences[index] for index in indices) < 0.25:
            continue
        selected_faces.append(polygon)
    assert selected_faces, "MPFB arm cut selected no faces"

    used = sorted({index for polygon in selected_faces for index in polygon.vertices})
    weighted_indices = [index for index, influence in enumerate(source_influences)
                        if influence >= 0.25 and source_weights[index]]
    weight_tree = KDTree(len(weighted_indices))
    for index in weighted_indices:
        weight_tree.insert(source_positions[index], index)
    weight_tree.balance()
    remap = {old: new for new, old in enumerate(used)}
    vertices = []
    mapped_weights = []
    for old_index in used:
        source_point = source_positions[old_index].copy()
        if proximity[old_index] <= 0.015:
            offset = 0.0018
            # A narrow, integral welt at the glove opening.  It is displaced
            # from MPFB's own surface, so it cannot float away from the wrist.
            if 0.006 <= proximity[old_index] <= 0.014:
                offset += 0.0015
            source_point += source_normals[old_index] * offset
        weights = source_weights[old_index]
        if not weights:
            _coordinate, nearest_index, _distance = weight_tree.find(source_point)
            weights = source_weights[nearest_index]
        point = Vector()
        for target_name, weight in weights.items():
            point += (transforms[target_name] @ source_point) * weight
        point_g = b2g(point)
        if (proximity[old_index] <= 0.015 and 0.025 < point_g.z < 0.090
                and abs(point_g.y) < 0.007 and side * point_g.x > 0.066):
            # Integral raised back-of-hand seam: move an existing narrow strip
            # rather than adding a disconnected decorative object.
            point_g.x += side * 0.0012 * (1.0 - abs(point_g.y) / 0.007)
            point = g2b(point_g)
        vertices.append(tuple(point))
        mapped_weights.append(weights)

    faces = [tuple(remap[index] for index in polygon.vertices) for polygon in selected_faces]
    data = bpy.data.meshes.new("MPFBHand")
    data.from_pydata(vertices, [], faces)
    data.materials.append(mats["glove"])
    data.materials.append(mats["skin"])
    mesh = bpy.data.objects.new("MPFBHand", data)
    bpy.context.collection.objects.link(mesh)
    for output_polygon, source_polygon in zip(data.polygons, selected_faces):
        centre_proximity = sum(proximity[index] for index in source_polygon.vertices) / len(source_polygon.vertices)
        output_polygon.material_index = 0 if centre_proximity <= 0.015 else 1
        output_polygon.use_smooth = True
    groups = {name: mesh.vertex_groups.new(name=name) for name in BONE_NAMES}
    for vertex_index, weights in enumerate(mapped_weights):
        for name, value in weights.items():
            groups[name].add([vertex_index], value, "REPLACE")
    evaluated.to_mesh_clear()
    print("MPFB_CUT", "right" if side > 0 else "left",
          "body_vertices", len(body_vertices), "kept_vertices", len(vertices),
          "kept_faces", len(faces))
    return mesh


def make_ring_tube(name, centres_g, radii, mat, weights, sides=18, fold=0.0,
                   cap_start=False, cap_end=False):
    centres = [Vector(point) for point in centres_g]
    vertices = []
    rings = []
    for ring_index, centre in enumerate(centres):
        if ring_index == 0:
            axis = (centres[1] - centre).normalized()
        elif ring_index == len(centres) - 1:
            axis = (centre - centres[ring_index - 1]).normalized()
        else:
            axis = (centres[ring_index + 1] - centres[ring_index - 1]).normalized()
        axis_b = g2b(axis)
        across_b = Vector((1.0, 0.0, 0.0))
        across_b = (across_b - axis_b * across_b.dot(axis_b)).normalized()
        around_b = axis_b.cross(across_b).normalized()
        rx, ry = radii[ring_index]
        ring = []
        for step in range(sides):
            angle = 2.0 * math.pi * step / sides
            wrinkle = fold * math.sin(3.0 * angle + ring_index * 1.7)
            point = g2b(centre) + across_b * ((rx + wrinkle) * math.cos(angle))
            point += around_b * ((ry + wrinkle * 0.7) * math.sin(angle))
            ring.append(len(vertices))
            vertices.append(tuple(point))
        rings.append(ring)
    faces = []
    if cap_start:
        faces.append(tuple(reversed(rings[0])))
    for first, second in zip(rings, rings[1:]):
        for step in range(sides):
            nxt = (step + 1) % sides
            faces.append((first[step], first[nxt], second[nxt], second[step]))
    if cap_end:
        faces.append(tuple(rings[-1]))
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    for polygon in data.polygons:
        polygon.use_smooth = True
    for group_name, value in weights.items():
        group = obj.vertex_groups.new(name=group_name)
        group.add(list(range(len(vertices))), value, "REPLACE")
    return obj


def add_clothing_parts(side, definition, mats):
    wrist = Vector(definition["Forearm"][1])
    sleeve_end = Vector(definition["Forearm"][0])
    direction = (sleeve_end - wrist).normalized()
    length = (sleeve_end - wrist).length

    def at(distance):
        return wrist + direction * distance

    turned_cuff = make_ring_tube(
        "TurnedSleeveCuff",
        [at(0.022), at(0.030), at(0.040), at(0.054)],
        [(0.038, 0.043), (0.043, 0.048), (0.044, 0.049), (0.041, 0.046)],
        mats["sleeve"], {"Forearm": 1.0}, sides=20, fold=0.0012,
    )
    sleeve_distances = (0.048, 0.085, 0.145, 0.215, min(0.285, length - 0.025), length)
    sleeve = make_ring_tube(
        "CanvasSleeve",
        [at(distance) for distance in sleeve_distances],
        [(0.039, 0.044), (0.042, 0.047), (0.046, 0.051),
         (0.051, 0.056), (0.056, 0.061), (0.060, 0.065)],
        mats["sleeve"], {"Forearm": 1.0}, sides=20, fold=0.0017, cap_end=True,
    )
    return [turned_cuff, sleeve]


def join_and_finish(parts, armature):
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
    for name in BONE_NAMES:
        if mesh.vertex_groups.get(name) is None:
            mesh.vertex_groups.new(name=name)
    assert {slot.name for slot in mesh.data.materials} == {"Arm Glove", "Arm Skin", "Arm Sleeve"}
    mesh.data.validate(verbose=True, clean_customdata=False)

    modifier = mesh.modifiers.new("One level production subdivision", "SUBSURF")
    modifier.subdivision_type = "CATMULL_CLARK"
    modifier.levels = 1
    modifier.render_levels = 1
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    evaluated_data = evaluated.to_mesh()
    evaluated_data.calc_loop_triangles()
    projected_triangles = len(evaluated_data.loop_triangles)
    evaluated.to_mesh_clear()
    if projected_triangles < 16000:
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        print("SUBDIVISION applied level 1; triangles", projected_triangles)
    else:
        mesh.modifiers.remove(modifier)
        print("SUBDIVISION skipped; projected triangles", projected_triangles)

    group_names = {group.index: group.name for group in mesh.vertex_groups}
    for vertex in mesh.data.vertices:
        weighted = sorted(((item.group, item.weight) for item in vertex.groups),
                          key=lambda item: item[1], reverse=True)
        keep = weighted[:4]
        total = sum(weight for _index, weight in keep)
        assert total > 1.0e-8
        for index, _weight in weighted:
            mesh.vertex_groups[group_names[index]].remove([vertex.index])
        for index, weight in keep:
            normalized = min(0.999999, max(0.0, weight / total))
            mesh.vertex_groups[group_names[index]].add([vertex.index], normalized, "REPLACE")

    mesh.parent = armature
    mesh.matrix_parent_inverse.identity()
    armature_modifier = mesh.modifiers.new("Armature", "ARMATURE")
    armature_modifier.object = armature
    armature_modifier.use_vertex_groups = True
    armature_modifier.use_bone_envelopes = False
    return mesh


def rest_chains(armature):
    result = {}
    for digit in ("Thumb", *FINGERS):
        result[digit] = [b2g(armature.data.bones[f"{digit}1"].head_local)]
        for index in range(1, 4):
            result[digit].append(b2g(armature.data.bones[f"{digit}{index}"].tail_local))
    return result


def pose_targets(armature, side):
    rest = rest_chains(armature)
    result = {"Grip": rest}

    def finger_pose(kind):
        posed = {}
        for finger in FINGERS:
            chain = rest[finger]
            lengths = [(chain[index + 1] - chain[index]).length for index in range(3)]
            if kind == "Open":
                directions = [(side * -0.18, 0.0, -0.98),
                              (side * -0.10, 0.0, -0.995),
                              (side * -0.05, 0.0, -0.999)]
            elif kind == "Flat":
                directions = [(side * 0.04, 0.0, -1.0)] * 3
            elif kind == "HoldMag":
                if finger == "Index":
                    directions = [(side * -0.14, -0.05, -0.99),
                                  (side * -0.30, -0.04, -0.95),
                                  (side * -0.55, -0.03, -0.83)]
                else:
                    outward = -0.18 if chain[0].y < 0.0 else 0.18
                    directions = [(side * -0.22, outward, -0.96),
                                  (side * -0.52, outward * 0.7, -0.84),
                                  (side * -0.82, outward * 0.4, -0.55)]
            elif kind == "Fist":
                directions = [(side * -0.70, 0.0, -0.71),
                              (side * -0.96, 0.0, 0.28),
                              (side * 0.02, 0.0, 1.0)]
            else:
                raise ValueError(kind)
            posed[finger] = target_chain(chain[0], lengths, directions)
        return posed

    opened = finger_pose("Open")
    opened["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][index + 1] - rest["Thumb"][index]).length for index in range(3)],
        [(side * -0.54, -0.71, -0.45), (side * -0.70, -0.57, -0.43),
         (side * -0.77, -0.46, -0.44)],
    )
    result["Open"] = opened

    flat = finger_pose("Flat")
    flat["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][index + 1] - rest["Thumb"][index]).length for index in range(3)],
        [(side * -0.20, 0.05, -0.98), (side * -0.15, 0.05, -0.99),
         (side * -0.09, 0.04, -0.995)],
    )
    result["Flat"] = flat

    hold = finger_pose("HoldMag")
    hold["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][index + 1] - rest["Thumb"][index]).length for index in range(3)],
        [(side * -0.30, 0.18, -0.94), (side * -0.74, 0.10, -0.67),
         (side * -0.95, 0.04, -0.30)],
    )
    result["HoldMag"] = hold

    pinch_target = Vector((side * -0.001, -0.020, -0.050))
    pinch = finger_pose("Open")
    pinch["Index"] = fabrik(rest["Index"], pinch_target)
    pinch["Thumb"] = fabrik(rest["Thumb"], pinch_target)
    for finger in ("Middle", "Ring", "Pinky"):
        chain = rest[finger]
        lengths = [(chain[index + 1] - chain[index]).length for index in range(3)]
        pinch[finger] = target_chain(chain[0], lengths,
                                     [(side * -0.40, 0.0, -0.92),
                                      (side * -0.64, 0.0, -0.77),
                                      (side * -0.79, 0.0, -0.61)])
    result["Pinch"] = pinch

    fist = {digit: [point.copy() for point in chain] for digit, chain in rest.items()}
    fist["Thumb"] = target_chain(
        rest["Thumb"][0],
        [(rest["Thumb"][index + 1] - rest["Thumb"][index]).length for index in range(3)],
        [(side * -0.25, 0.10, -0.96), (side * -0.60, 0.06, -0.80),
         (side * -0.70, 0.03, -0.71)],
    )
    result["Fist"] = fist
    return result


def reset_pose(armature):
    for bone in armature.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def apply_target_pose(armature, targets):
    reset_pose(armature)
    bpy.context.view_layer.update()
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
            pose_bone.matrix = Matrix.Translation(target_head) @ rotation.to_4x4()
            bpy.context.view_layer.update()
            assert pose_bone.location.length < 2.5e-4, (pose_bone.name, pose_bone.location[:])
            pose_bone.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def make_actions(armature, side):
    armature.animation_data_create()
    targets = pose_targets(armature, side)
    actions = {}
    for name in ACTION_NAMES:
        action = bpy.data.actions.new(name)
        actions[name] = action
        armature.animation_data.action = action
        for frame in (1, 2):
            bpy.context.scene.frame_set(frame)
            apply_target_pose(armature, targets[name])
            for pose_bone in armature.pose.bones:
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
        for slot in action.slots:
            bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
            if bag:
                for curve in bag.fcurves:
                    assert curve.data_path.endswith("rotation_quaternion")
                    for point in curve.keyframe_points:
                        point.interpolation = "CONSTANT"
    armature.animation_data.action = None
    bpy.context.scene.frame_set(0)
    reset_pose(armature)
    return actions


def export_arm(side, mesh, armature):
    piece_id = "fp_arm_right" if side > 0 else "fp_arm_left"
    output = MODEL_DIR / f"{piece_id}.glb"
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_skins=True,
        export_animations=True, export_animation_mode="ACTIONS",
        export_bake_animation=True, export_force_sampling=False,
        export_frame_range=True,
    )
    return piece_id, output


def build_source(HumanService):
    human = HumanService.create_human(
        mask_helpers=False, detailed_helpers=False, extra_vertex_groups=False,
        feet_on_ground=False, scale=0.1, macro_detail_dict=MACRO_SETTINGS,
    )
    rig = HumanService.add_builtin_rig(human, "game_engine", import_weights=True)
    assert rig is not None
    return human, rig


def build_side(HumanService, side):
    clean_scene(remove_actions=True)
    bpy.context.scene.render.fps = FPS
    mats = {
        "glove": material("Arm Glove", (0.028, 0.010, 0.004), 0.0, 0.82),
        "skin": material("Arm Skin", (0.48, 0.235, 0.135), 0.0, 0.80),
        "sleeve": material("Arm Sleeve", (0.030, 0.040, 0.047), 0.0, 0.94),
    }
    source_mesh, source_armature = build_source(HumanService)
    armature, definition, _chains, transforms = build_armature(source_armature, side)
    hand = extract_mpfb_arm(source_mesh, source_armature, armature, side, transforms, mats)
    clothing = add_clothing_parts(side, definition, mats)
    mesh = join_and_finish([hand, *clothing], armature)
    make_actions(armature, side)
    assert all(value > 0.0 for value in (*mesh.scale, *armature.scale))
    result = export_arm(side, mesh, armature)
    print("EXPORTED", result[1])
    return result


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


def preview_material():
    mat = bpy.data.materials.get("Preview Grey") or bpy.data.materials.new("Preview Grey")
    mat.diffuse_color = (0.23, 0.27, 0.30, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.23, 0.27, 0.30, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.25
    bsdf.inputs["Roughness"].default_value = 0.48
    return mat


def add_preview_prop(kind, side):
    if kind == "Grip":
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.017, depth=0.30,
                                            location=g2b((0.0, 0.0, 0.0)))
        prop = bpy.context.object
        prop.name = "PREVIEW_ONLY_Handle"
    elif kind == "HoldMag":
        centre = Vector((side * 0.023, 0.0, -0.040))
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(centre))
        prop = bpy.context.object
        prop.name = "PREVIEW_ONLY_Magazine"
        # Godot dimensions are X 22 mm, Y 30 mm, Z 120 mm.
        prop.scale = (0.022, 0.120, 0.030)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = prop.modifiers.new("Magazine edge bevel", "BEVEL")
        bevel.width = 0.002
        bevel.segments = 2
        bpy.context.view_layer.objects.active = prop
        bpy.ops.object.modifier_apply(modifier=bevel.name)
    else:
        return None
    prop.data.materials.append(preview_material())
    return prop


def setup_preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.006, 0.009, 0.014)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.sensor_fit = "VERTICAL"
    camera_data.angle_y = math.radians(48.0)
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    for name, point, energy, size in (
        ("Key", (0.50, -0.34, 0.38), 9.0, 0.45),
        ("Fill", (-0.34, -0.18, 0.26), 5.0, 0.38),
        ("Rim", (0.12, 0.40, 0.48), 7.0, 0.34),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = g2b(point)
        look_at(light, (0.03, 0.0, 0.10))
    return camera


def make_contact_sheet(paths):
    import numpy as np

    tile = 512
    columns = 4
    rows = math.ceil(len(paths) / columns)
    canvas = np.zeros((rows * tile, columns * tile, 4), dtype=np.float32)
    canvas[:, :, 3] = 1.0
    for index, path in enumerate(paths):
        image = bpy.data.images.load(str(path), check_existing=False)
        width, height = image.size
        assert (width, height) == (1024, 1024)
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape((height, width, 4)).reshape(tile, 2, tile, 2, 4).mean(axis=(1, 3))
        row, column = divmod(index, columns)
        canvas[(rows - 1 - row) * tile:(rows - row) * tile,
               column * tile:(column + 1) * tile] = pixels
        bpy.data.images.remove(image)
    sheet = bpy.data.images.new("MPFB Arm Contact Sheet", width=columns * tile,
                                height=rows * tile, alpha=True)
    sheet.pixels.foreach_set(canvas.ravel())
    sheet.filepath_raw = str(SHOT_DIR / "fp_arm_mh_sheet.png")
    sheet.file_format = "PNG"
    sheet.save()
    print("PREVIEW", sheet.filepath_raw)


def render_previews(side, armature, actions):
    if side < 0:
        return
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    camera = setup_preview()
    armature.data.pose_position = "POSE"
    rendered = []

    camera.location = g2b((0.260, -0.320, 0.120))
    look_at(camera, (0.026, 0.0, 0.020))
    for name in ACTION_NAMES:
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_mh_{name.lower()}.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        rendered.append(Path(scene.render.filepath))
        if prop:
            bpy.data.objects.remove(prop, do_unlink=True)

    camera.location = g2b((-0.245, -0.285, 0.115))
    look_at(camera, (0.018, 0.0, 0.020))
    for name in ("Grip", "HoldMag"):
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_mh_{name.lower()}_palm.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        rendered.append(Path(scene.render.filepath))
        if prop:
            bpy.data.objects.remove(prop, do_unlink=True)

    armature.animation_data.action = actions["Grip"]
    scene.frame_set(1)
    bpy.context.view_layer.update()
    handle = add_preview_prop("Grip", side)
    camera.data.angle_y = math.radians(75.0)
    camera.location = g2b((0.25, 0.35, 0.65))
    look_at(camera, (0.0, 0.0, 0.0))
    scene.render.filepath = str(SHOT_DIR / "fp_arm_mh_first_person.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    bpy.data.objects.remove(handle, do_unlink=True)

    armature.animation_data.action = None
    reset_pose(armature)
    hand = armature.pose.bones["Hand"]
    hand.rotation_mode = "QUATERNION"
    hand.rotation_quaternion = Quaternion((0.0, 0.0, 1.0), math.radians(40.0))
    bpy.context.view_layer.update()
    camera.data.angle_y = math.radians(48.0)
    camera.location = g2b((0.260, -0.320, 0.120))
    look_at(camera, (0.028, 0.0, 0.020))
    scene.render.filepath = str(SHOT_DIR / "fp_arm_mh_wrist_bent.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    reset_pose(armature)
    make_contact_sheet(rendered)


def action_paths(action):
    paths = []
    for slot in action.slots:
        bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
        if bag:
            paths.extend(curve.data_path for curve in bag.fcurves)
    return paths


def validate_reimport(piece_id, output, side, render=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(output))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"
              and not any(collection.name == "glTF_not_exported"
                          for collection in obj.users_collection)]
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
    assert triangles < 16000, triangles
    bones = armature.data.bones
    assert tuple(bones.keys()) == BONE_NAMES, tuple(bones.keys())
    parents = {bone.name: bone.parent.name if bone.parent else None for bone in bones}
    expected = {"Forearm": None, "Hand": "Forearm"}
    for digit in ("Thumb", *FINGERS):
        expected[f"{digit}1"] = "Hand"
        expected[f"{digit}2"] = f"{digit}1"
        expected[f"{digit}3"] = f"{digit}2"
    assert parents == expected, parents
    actions = {action.name: action for action in bpy.data.actions}
    assert set(actions) == set(ACTION_NAMES), sorted(actions)
    for action in actions.values():
        paths = action_paths(action)
        assert paths and all(path.endswith("rotation_quaternion") for path in paths), paths

    armature.animation_data_create()
    armature.animation_data.action = None
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    points = evaluated_points(mesh)
    lo = Vector((min(point.x for point in points), min(point.y for point in points),
                 min(point.z for point in points)))
    hi = Vector((max(point.x for point in points), max(point.y for point in points),
                 max(point.z for point in points)))
    in_handle_span = [point for point in points if abs(point.y) < 0.040]
    clearance = min(math.hypot(point.x, point.z) for point in in_handle_span)
    nearest = min(in_handle_span, key=lambda point: math.hypot(point.x, point.z))
    assert clearance >= 0.015, (clearance, nearest)

    pose_tips = {}
    grip_clearance = None
    holdmag_inside = None
    armature.data.pose_position = "POSE"
    for action_name in ACTION_NAMES:
        armature.animation_data.action = actions[action_name]
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        forearm = armature.pose.bones["Forearm"]
        rest_matrix = forearm.bone.matrix_local
        error = max(abs(forearm.matrix[row][column] - rest_matrix[row][column])
                    for row in range(4) for column in range(4))
        assert error < 1.0e-5, (action_name, error)
        pose_tips[action_name] = {
            digit: b2g(armature.matrix_world @ armature.pose.bones[f"{digit}3"].tail)
            for digit in ("Thumb", *FINGERS)
        }
        posed_points = evaluated_points(mesh)
        if action_name == "Grip":
            candidates = [point for point in posed_points if abs(point.y) < 0.040]
            grip_clearance = min(math.hypot(point.x, point.z) for point in candidates)
        if action_name == "HoldMag":
            centre = Vector((side * 0.023, 0.0, -0.040))
            holdmag_inside = sum(
                abs(point.x - centre.x) < 0.011 - 0.0005
                and abs(point.y - centre.y) < 0.015 - 0.0005
                and abs(point.z - centre.z) < 0.060 - 0.0005
                for point in posed_points
            )
    assert grip_clearance >= 0.015, grip_clearance
    assert holdmag_inside == 0, holdmag_inside

    armature.animation_data.action = None
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    sleeve_end = b2g(armature.matrix_world @ bones["Forearm"].head_local)
    sleeve_direction = sleeve_end.normalized()
    assert sleeve_direction.z > 0.92 and sleeve_direction.y < -0.10, sleeve_direction
    mag_centre = Vector((side * 0.023, 0.0, -0.040))
    mag_axis = Vector((0.0, 0.0, 1.0))
    assert armature.matrix_world.translation.length < 1.0e-6
    assert mesh.matrix_world.translation.length < 1.0e-6

    glove_index = next(index for index, mat in enumerate(mesh.data.materials)
                       if mat and mat.name == "Arm Glove")
    glove_vertex_indices = {index for polygon in mesh.data.polygons if polygon.material_index == glove_index
                            for index in polygon.vertices}
    glove_points = [b2g(mesh.matrix_world @ mesh.data.vertices[index].co)
                    for index in glove_vertex_indices]
    # Restrict the span measurement to the gripping hand.  The glove material also
    # covers the short section under the cuff, whose diagonal forearm direction would
    # otherwise inflate the Y extent.
    grip_glove_points = [point for point in glove_points
                         if math.hypot(point.x, point.z) < 0.10 and point.z < 0.08]
    hand_span = (max(point.y for point in grip_glove_points)
                 - min(point.y for point in grip_glove_points))
    chains = []
    for name in BONE_NAMES:
        parent = bones[name].parent
        chain = [name]
        while parent:
            chain.append(parent.name)
            parent = parent.parent
        chains.append("<-".join(chain))
    bone_rest = {
        bone.name: (b2g(armature.matrix_world @ bone.head_local),
                    b2g(armature.matrix_world @ bone.tail_local))
        for bone in bones
    }
    print("VALIDATION", piece_id)
    print("  bounds_godot", f"({lo.x:.4f},{lo.y:.4f},{lo.z:.4f})..({hi.x:.4f},{hi.y:.4f},{hi.z:.4f})")
    print("  triangles", triangles)
    print("  materials", materials)
    print("  bones", list(BONE_NAMES))
    print("  parent_chains", chains)
    print("  animations", sorted(actions))
    print("  min_handle_clearance", f"{grip_clearance:.5f}",
          "nearest", tuple(round(value, 5) for value in nearest))
    print("  glove_handle_span_y", f"{hand_span:.5f}")
    print("  sleeve_direction", f"({sleeve_direction.x:.5f},{sleeve_direction.y:.5f},{sleeve_direction.z:.5f})")
    print("  holdmag_centre", f"({mag_centre.x:.5f},{mag_centre.y:.5f},{mag_centre.z:.5f})",
          "axis", f"({mag_axis.x:.1f},{mag_axis.y:.1f},{mag_axis.z:.1f})",
          "interior_vertices", holdmag_inside)
    print("  pose_tips", {name: {digit: tuple(round(value, 4) for value in tip)
                                for digit, tip in tips.items()}
                           for name, tips in pose_tips.items()})
    if render:
        render_previews(side, armature, actions)
    return {
        "bounds": (lo, hi), "triangles": triangles, "materials": materials,
        "bones": list(BONE_NAMES), "parents": parents, "animations": sorted(actions),
        "clearance": grip_clearance, "sleeve_direction": sleeve_direction,
        "mag_centre": mag_centre, "mag_axis": mag_axis, "hand_span": hand_span,
        "points": points, "bone_rest": bone_rest,
    }


def validate_mirror(right, left):
    rlo, rhi = right["bounds"]
    llo, lhi = left["bounds"]
    assert abs(rlo.x + lhi.x) < 0.008 and abs(rhi.x + llo.x) < 0.008
    assert (rlo.yz - llo.yz).length < 5.0e-4 and (rhi.yz - lhi.yz).length < 5.0e-4
    assert right["triangles"] == left["triangles"]
    left_tree = KDTree(len(left["points"]))
    for index, point in enumerate(left["points"]):
        left_tree.insert(point, index)
    left_tree.balance()
    errors = [left_tree.find(Vector((-point.x, point.y, point.z)))[2]
              for point in right["points"]]
    max_error = max(errors)
    mean_error = sum(errors) / len(errors)
    assert max_error < 0.012 and mean_error < 0.0015, (max_error, mean_error)
    for name in BONE_NAMES:
        for right_point, left_point in zip(right["bone_rest"][name], left["bone_rest"][name]):
            assert abs(right_point.x + left_point.x) < 3.0e-4, (name, right_point, left_point)
            assert (right_point.yz - left_point.yz).length < 3.0e-4, (name, right_point, left_point)
    print("MIRROR_CHECK native left/right across X",
          f"nearest_surface_mean={mean_error:.6f}", f"max={max_error:.6f}",
          "bone endpoints matched; no negative scales")


def main():
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    HumanService, _RigService, TargetService = enable_mpfb()
    print("MPFB_SETTINGS", MACRO_SETTINGS)
    print("MPFB_TARGET_STACK", TargetService.calculate_target_stack_from_macro_info_dict(MACRO_SETTINGS))
    right_id, right_path = build_side(HumanService, 1)
    left_id, left_path = build_side(HumanService, -1)
    # MPFB installs scene/load handlers.  Remove them before repeatedly replacing
    # the file state for glTF re-import validation; all MPFB work is finished now.
    addon_utils.disable("bl_ext.blender_org.mpfb", default_set=False)
    # Validate the non-rendered side first.  Blender 5.1's glTF importer can retain
    # stale evaluated render data if another GLB is imported after the preview pass.
    left = validate_reimport(left_id, left_path, -1, render=False)
    right = validate_reimport(right_id, right_path, 1, render=True)
    validate_mirror(right, left)


if __name__ == "__main__":
    main()
