"""Build Noise Floor's first-person arms from MPFB 2.0.18's CC0 human.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/fp_arm_mpfb.py

The MPFB HumanService creates a moderately muscular adult male and RigService supplies the
game_engine skeleton and weights.  Native right and left hands are cut from that human; the
left is never mirrored.  MPFB weights are merged onto the game's compact 17-bone contract.
The working Grip hand is the deformation-safe bind pose; every named action is authored from
an anatomical neutral reference without adding bone roll.  The jacket sleeve, turned cuff and
glove seam are deterministic procedural additions.

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

# Anatomical flexion in degrees from the clean neutral reference.  The fist
# values are the requested MCP/PIP/DIP closure rather than a visually guessed
# fingertip path.
GRIP_ANGLES = {
    "Thumb": (18.0, 24.0, 12.0),
    "Index": (30.0, 32.0, 38.0),
    "Middle": (32.0, 34.0, 40.0),
    "Ring": (34.0, 36.0, 42.0),
    "Pinky": (36.0, 38.0, 44.0),
}
POSE_ANGLES = {
    "Grip": GRIP_ANGLES,
    "Open": {
        "Thumb": (8.0, 10.0, 6.0),
        "Index": (10.0, 15.0, 8.0),
        "Middle": (12.0, 17.0, 9.0),
        "Ring": (14.0, 19.0, 10.0),
        "Pinky": (16.0, 21.0, 12.0),
    },
    "Flat": {digit: (0.0, 0.0, 0.0) for digit in ("Thumb", *FINGERS)},
    "HoldMag": {
        "Thumb": (34.0, 42.0, 18.0),
        "Index": (7.0, 8.0, 5.0),
        "Middle": (42.0, 58.0, 34.0),
        "Ring": (45.0, 62.0, 36.0),
        "Pinky": (48.0, 66.0, 38.0),
    },
    "Pinch": {
        "Thumb": (42.0, 52.0, 26.0),
        "Index": (60.0, 70.0, 38.0),
        "Middle": (32.0, 42.0, 22.0),
        "Ring": (36.0, 46.0, 24.0),
        "Pinky": (40.0, 50.0, 27.0),
    },
    "Fist": {
        "Thumb": (52.0, 62.0, 34.0),
        "Index": (88.0, 100.0, 66.0),
        "Middle": (89.0, 101.0, 67.0),
        "Ring": (89.0, 101.0, 67.0),
        "Pinky": (87.0, 99.0, 65.0),
    },
}

# Only the MCP is allowed a tiny natural fan.  Signs mirror with the palm
# normal, keeping both native hands symmetric without lateral joint bending.
GRIP_FAN = {"Thumb": 0.0, "Index": -3.0, "Middle": -1.0,
            "Ring": 1.0, "Pinky": 3.5}
POSE_FAN = {
    "Grip": GRIP_FAN,
    "Open": {"Thumb": 0.0, "Index": -1.0, "Middle": -0.3, "Ring": 0.3, "Pinky": 1.0},
    "Flat": {"Thumb": 0.0, "Index": -0.4, "Middle": -0.1, "Ring": 0.1, "Pinky": 0.4},
    "HoldMag": {"Thumb": 0.0, "Index": -1.5, "Middle": -0.8, "Ring": 1.2, "Pinky": 3.5},
    "Pinch": {"Thumb": 0.0, "Index": -2.0, "Middle": -1.0, "Ring": 1.2, "Pinky": 3.5},
    "Fist": {"Thumb": 25.0, "Index": -4.0, "Middle": -1.5, "Ring": 1.5, "Pinky": 4.0},
}

def g2b(point):
    """Godot point/vector -> Blender point/vector for a Y-up glTF round trip."""
    return Vector((point[0], -point[2], point[1]))


def b2g(point):
    """Blender point/vector -> Godot point/vector after glTF re-import."""
    return Vector((point.x, point.z, -point.y))


GODOT_TO_BLENDER_BASIS = Matrix(((1.0, 0.0, 0.0),
                                 (0.0, 0.0, -1.0),
                                 (0.0, 1.0, 0.0)))


def g2b_rotation(rotation):
    """Convert a Godot-space rotation to the equivalent Blender-space rotation."""
    matrix = rotation.to_matrix() if isinstance(rotation, Quaternion) else Matrix(rotation)
    return GODOT_TO_BLENDER_BASIS @ matrix @ GODOT_TO_BLENDER_BASIS.transposed()


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


def flexion_chain(neutral_chain, palm_normal, joint_angles, fan_angle=0.0,
                  axis_chain=None):
    """Pose a digit without roll: every joint turns around its flexion axis.

    At each phalanx the axis is derived afresh as bone direction x inward palm
    normal.  Parent rotation carries that axis forward to the child, so there is
    no dependence on MPFB bone roll and no shortest-arc swing ambiguity.
    """
    points = [Vector(neutral_chain[0])]
    rotations = []
    palm_normal = Vector(palm_normal).normalized()
    axis_chain = axis_chain or neutral_chain
    parent_rotation = Quaternion(palm_normal, math.radians(fan_angle))
    for index, angle in enumerate(joint_angles):
        rest_vector = Vector(neutral_chain[index + 1]) - Vector(neutral_chain[index])
        length = rest_vector.length
        base_direction = (parent_rotation @ rest_vector.normalized()).normalized()
        posed_normal = (parent_rotation @ palm_normal).normalized()
        axis_direction = (Vector(axis_chain[index + 1]) - Vector(axis_chain[index])).normalized()
        axis_direction = (parent_rotation @ axis_direction).normalized()
        flex_axis = axis_direction.cross(-posed_normal)
        assert flex_axis.length > 0.25, (index, base_direction[:], posed_normal[:])
        flex_axis.normalize()
        flex = Quaternion(flex_axis, math.radians(angle))
        segment_rotation = flex @ parent_rotation
        direction = (segment_rotation @ rest_vector.normalized()).normalized()
        points.append(points[-1] + direction * length)
        rotations.append(segment_rotation)
        parent_rotation = segment_rotation
    return points, rotations


def rotations_between_chains(source_chain, target_chain):
    """Return twist-free segment swings from one authored chain to another."""
    rotations = []
    for index in range(3):
        source_direction = (Vector(source_chain[index + 1]) - Vector(source_chain[index])).normalized()
        target_direction = (Vector(target_chain[index + 1]) - Vector(target_chain[index])).normalized()
        rotations.append(source_direction.rotation_difference(target_direction))
    return rotations


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

    # Position the whole hand around the prop after flexing the digits; do not
    # cheat contact by steering individual phalanges sideways.
    target_wrist_g = Vector((side * 0.055, -0.010, 0.112))
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
    return transform, rotation, target_wrist_g, target_normal_g


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


def fist_directions(side, digit):
    """Compact closed chains, kept close to the deformation-safe Grip bind."""
    if digit == "Thumb":
        return (
            (side * -0.25, 0.55, -0.80),
            (side * -0.72, 0.55, -0.42),
            (side * -0.82, 0.45, -0.35),
        )
    spread = {"Index": -0.018, "Middle": -0.006,
              "Ring": 0.006, "Pinky": 0.018}[digit]
    return (
        (side * -0.62, spread, -0.78),
        (side * -0.98, spread * 0.3, -0.18),
        (side * -0.65, spread * 0.2, 0.76),
    )


def make_rest_definition(source_armature, side):
    suffix = source_side(side)
    source_bones = source_armature.data.bones
    hand_xform, hand_rotation, wrist_g, palm_normal_g = hand_transform(source_armature, side)
    sleeve_end_g = Vector((side * 0.070, -0.104, 0.424))
    definition = {
        "Forearm": (sleeve_end_g, wrist_g, None),
    }

    source_hand = source_bones[f"hand_{suffix}"]
    hand_head = b2g(hand_xform @ source_hand.head_local)
    hand_tail = b2g(hand_xform @ source_hand.tail_local)
    definition["Hand"] = (hand_head, hand_tail, "Forearm")

    chains = {}
    neutral_chains = {}
    for digit in ("Thumb", *FINGERS):
        source_chain = [source_bones[source_name(digit, 1, suffix)].head_local.copy()]
        for index in range(1, 4):
            source_chain.append(source_bones[source_name(digit, index, suffix)].tail_local.copy())
        neutral_chain = [b2g(hand_xform @ point) for point in source_chain]
        neutral_chains[digit] = neutral_chain
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
    return definition, chains, neutral_chains, palm_normal_g, hand_xform, hand_rotation


def build_armature(source_armature, side):
    (definition, chains, neutral_chains, palm_normal_g,
     hand_xform, hand_rotation) = make_rest_definition(source_armature, side)
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
    pose_meta = {"neutral_chains": neutral_chains, "palm_normal": palm_normal_g}
    return armature, definition, chains, transforms, pose_meta


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
        # The signed forearm projection alone also accepts remote body islands
        # behind the wrist plane.  Bound the native hand cut spatially so a
        # stale/remote island can never be mapped through the nearest arm weight.
        if max((source_positions[index] - wrist).length for index in indices) > 0.35:
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
        if proximity[old_index] <= 0.028:
            offset = 0.0018
            # A narrow, integral welt at the glove opening.  It is displaced
            # from MPFB's own surface, so it cannot float away from the wrist.
            if 0.019 <= proximity[old_index] <= 0.027:
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
        if (proximity[old_index] <= 0.028 and 0.025 < point_g.z < 0.090
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
        output_polygon.material_index = 0 if centre_proximity <= 0.028 else 1
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
        [at(0.047), at(0.052), at(0.060), at(0.070)],
        [(0.034, 0.038), (0.041, 0.045), (0.043, 0.047), (0.041, 0.045)],
        mats["sleeve"], {"Forearm": 1.0}, sides=20, fold=0.0012,
        cap_start=True,
    )
    sleeve_distances = (0.064, 0.090, 0.145, 0.215, min(0.285, length - 0.025), length)
    sleeve = make_ring_tube(
        "CanvasSleeve",
        [at(distance) for distance in sleeve_distances],
        [(0.040, 0.044), (0.042, 0.047), (0.046, 0.051),
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


def reset_pose(armature):
    for bone in armature.pose.bones:
        bone.rotation_mode = "QUATERNION"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def pose_targets(armature, side, pose_meta):
    rest = rest_chains(armature)
    targets = {"Grip": {
        digit: (rest[digit], [Quaternion() for _index in range(3)])
        for digit in ("Thumb", *FINGERS)
    }}
    for action_name in ACTION_NAMES:
        if action_name == "Grip":
            continue
        targets[action_name] = {}
        if action_name == "Pinch":
            pinch_chains = {
                digit: flexion_chain(
                    pose_meta["neutral_chains"][digit], pose_meta["palm_normal"],
                    POSE_ANGLES[action_name][digit], side * POSE_FAN[action_name][digit])[0]
                for digit in ("Thumb", *FINGERS)
            }
            contact = (pinch_chains["Thumb"][-1] + pinch_chains["Index"][-1]) * 0.5
            # Put the shared point inside the intersection of both reachable
            # spheres; otherwise FABRIK correctly leaves the shorter digit shy.
            thumb_root = pinch_chains["Thumb"][0]
            index_root = pinch_chains["Index"][0]
            thumb_reach = sum((pinch_chains["Thumb"][index + 1] -
                               pinch_chains["Thumb"][index]).length
                              for index in range(3)) * 0.995
            index_reach = sum((pinch_chains["Index"][index + 1] -
                               pinch_chains["Index"][index]).length
                              for index in range(3)) * 0.995
            root_vector = index_root - thumb_root
            root_distance = root_vector.length
            assert abs(thumb_reach - index_reach) < root_distance < thumb_reach + index_reach
            along = ((root_distance * root_distance + thumb_reach * thumb_reach -
                      index_reach * index_reach) / (2.0 * root_distance))
            circle_centre = thumb_root + root_vector.normalized() * along
            circle_radius = math.sqrt(max(0.0, thumb_reach * thumb_reach - along * along))
            perpendicular = contact - circle_centre
            perpendicular -= root_vector.normalized() * perpendicular.dot(root_vector.normalized())
            if perpendicular.length > circle_radius * 0.80:
                perpendicular.normalize()
                perpendicular *= circle_radius * 0.80
            contact = circle_centre + perpendicular
            pinch_chains["Thumb"] = fabrik(pinch_chains["Thumb"], contact)
            pinch_chains["Index"] = fabrik(pinch_chains["Index"], contact)
            targets[action_name] = {
                digit: (chain, rotations_between_chains(rest[digit], chain))
                for digit, chain in pinch_chains.items()
            }
            continue
        for digit in ("Thumb", *FINGERS):
            if action_name == "Fist":
                lengths = [(rest[digit][index + 1] - rest[digit][index]).length
                           for index in range(3)]
                chain = target_chain(rest[digit][0], lengths,
                                     fist_directions(side, digit))
                targets[action_name][digit] = (
                    chain, rotations_between_chains(rest[digit], chain))
                continue
            chain, _rotations = flexion_chain(
                pose_meta["neutral_chains"][digit], pose_meta["palm_normal"],
                POSE_ANGLES[action_name][digit], side * POSE_FAN[action_name][digit])
            targets[action_name][digit] = (
                chain, rotations_between_chains(rest[digit], chain))
    return targets


def apply_target_pose(armature, targets):
    reset_pose(armature)
    for digit in ("Thumb", *FINGERS):
        chain, segment_rotations = targets[digit]
        for index in range(3):
            pose_bone = armature.pose.bones[f"{digit}{index + 1}"]
            target_head = g2b(chain[index])
            target_tail = g2b(chain[index + 1])
            rest = pose_bone.bone.matrix_local.copy()
            rotation = g2b_rotation(segment_rotations[index]) @ rest.to_3x3()
            target_direction = (target_tail - target_head).normalized()
            actual_direction = (rotation @ Vector((0.0, 1.0, 0.0))).normalized()
            assert actual_direction.dot(target_direction) > 0.99999
            pose_bone.matrix = Matrix.Translation(target_head) @ rotation.to_4x4()
            bpy.context.view_layer.update()
            assert pose_bone.location.length < 2.5e-4, (pose_bone.name, pose_bone.location[:])
            pose_bone.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def make_actions(armature, side, pose_meta):
    armature.animation_data_create()
    targets = pose_targets(armature, side, pose_meta)
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


def build_side(source_mesh, source_armature, mats, side):
    armature, definition, _chains, transforms, pose_meta = build_armature(source_armature, side)
    hand = extract_mpfb_arm(source_mesh, source_armature, armature, side, transforms, mats)
    clothing = add_clothing_parts(side, definition, mats)
    mesh = join_and_finish([hand, *clothing], armature)
    make_actions(armature, side, pose_meta)
    assert all(value > 0.0 for value in (*mesh.scale, *armature.scale))
    result = export_arm(side, mesh, armature)
    print("EXPORTED", result[1])
    return result, mesh, armature


def evaluated_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    points = [b2g(evaluated.matrix_world @ vertex.co) for vertex in data.vertices]
    evaluated.to_mesh_clear()
    return points


def evaluated_finger_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    group_names = {group.index: group.name for group in mesh.vertex_groups}
    points = []
    for vertex in data.vertices:
        finger_weight = sum(item.weight for item in vertex.groups
                            if group_names.get(item.group, "").startswith(("Thumb", *FINGERS)))
        if finger_weight >= 0.50:
            points.append(b2g(evaluated.matrix_world @ vertex.co))
    evaluated.to_mesh_clear()
    return points


def segment_distance(first_a, first_b, second_a, second_b):
    """Shortest distance between finite 3-D line segments."""
    first = first_b - first_a
    second = second_b - second_a
    offset = first_a - second_a
    aa = first.dot(first)
    bb = first.dot(second)
    cc = second.dot(second)
    dd = first.dot(offset)
    ee = second.dot(offset)
    denominator = aa * cc - bb * bb
    first_t = 0.0 if denominator < 1.0e-12 else (bb * ee - cc * dd) / denominator
    first_t = max(0.0, min(1.0, first_t))
    second_t = (bb * first_t + ee) / cc if cc > 1.0e-12 else 0.0
    if second_t < 0.0:
        second_t = 0.0
        first_t = max(0.0, min(1.0, -dd / aa))
    elif second_t > 1.0:
        second_t = 1.0
        first_t = max(0.0, min(1.0, (bb - dd) / aa))
    return ((first_a + first * first_t) -
            (second_a + second * second_t)).length, first_t, second_t


def finger_surface_intersections(_mesh, armature, action_name):
    """Count penetrations between distal finger surface capsules.

    The MPFB hand is one connected surface at the webs, so raw triangle BVH
    overlap reports the shared web as hundreds of false collisions.  Distal
    phalanges are instead checked as anatomical surface capsules; a tip-tip
    contact in Pinch is permitted, penetration is not.
    """
    radii = {"Thumb": 0.0062, "Index": 0.0058, "Middle": 0.0061,
             "Ring": 0.0058, "Pinky": 0.0052}
    segments = {}
    for digit in ("Thumb", *FINGERS):
        segments[digit] = [
            (armature.matrix_world @ armature.pose.bones[f"{digit}{index}"].head,
             armature.matrix_world @ armature.pose.bones[f"{digit}{index}"].tail)
            for index in (2, 3)
        ]
    counts = {}
    digits = ("Thumb", *FINGERS)
    for first_index, first in enumerate(digits):
        for second in digits[first_index + 1:]:
            if action_name == "Pinch" and {first, second} == {"Thumb", "Index"}:
                counts[f"{first}-{second}"] = 0
                continue
            penetrations = 0
            for first_segment in segments[first]:
                for second_segment in segments[second]:
                    distance, first_t, second_t = segment_distance(
                        *first_segment, *second_segment)
                    if distance < radii[first] + radii[second] - 0.001:
                        penetrations += 1
            counts[f"{first}-{second}"] = penetrations
    return counts


def pose_prop_intrusions(action_name, points, side):
    if action_name == "Grip":
        # The preview handle is a 17 mm radius cylinder along Godot Y.
        return sum(abs(point.y) < 0.150 - 0.0001
                   and math.hypot(point.x, point.z) < 0.017 - 0.0001
                   for point in points)
    if action_name == "HoldMag":
        centre = Vector((side * 0.023, 0.0, -0.040))
        return sum(abs(point.x - centre.x) < 0.011 - 0.0001
                   and abs(point.y - centre.y) < 0.015 - 0.0001
                   and abs(point.z - centre.z) < 0.060 - 0.0001
                   for point in points)
    return 0


def sleeve_glove_measurements(mesh, armature):
    """Measure the intentional skin band and any see-through cuff opening."""
    bones = armature.data.bones
    wrist_b = armature.matrix_world @ bones["Forearm"].tail_local
    sleeve_end_b = armature.matrix_world @ bones["Forearm"].head_local
    axis_b = (sleeve_end_b - wrist_b).normalized()
    material_indices = {mat.name: index for index, mat in enumerate(mesh.data.materials) if mat}
    vertices_by_material = {}
    for material_name, material_index in material_indices.items():
        indices = {index for polygon in mesh.data.polygons
                   if polygon.material_index == material_index
                   for index in polygon.vertices}
        vertices_by_material[material_name] = [
            (index, mesh.matrix_world @ mesh.data.vertices[index].co)
            for index in indices]

    forearm_group = mesh.vertex_groups.get("Forearm")
    assert forearm_group is not None

    def forearm_weight(index):
        return sum(item.weight for item in mesh.data.vertices[index].groups
                   if item.group == forearm_group.index)

    def axial(point):
        return (point - wrist_b).dot(axis_b)

    def radial(point):
        offset = point - wrist_b
        return (offset - axis_b * offset.dot(axis_b)).length

    glove_cuff_points = [point for index, point in vertices_by_material["Arm Glove"]
                         if forearm_weight(index) >= 0.35
                         and 0.0 <= axial(point) <= 0.039 and radial(point) < 0.080]
    sleeve_cuff_points = [point for index, point in vertices_by_material["Arm Sleeve"]
                          if forearm_weight(index) >= 0.95
                          and 0.0 <= axial(point) <= 0.080 and radial(point) < 0.080]
    if not glove_cuff_points or not sleeve_cuff_points:
        print("CUFF_DEBUG", {
            name: (min(axial(point) for _index, point in material_points),
                   max(axial(point) for _index, point in material_points),
                   min(radial(point) for _index, point in material_points),
                   max(radial(point) for _index, point in material_points))
            for name, material_points in vertices_by_material.items()
        })
    assert glove_cuff_points and sleeve_cuff_points
    glove_extent = max(axial(point) for point in glove_cuff_points)
    sleeve_edge = min(axial(point) for point in sleeve_cuff_points)
    skin_band = sleeve_edge - glove_extent
    edge_points = [point for point in sleeve_cuff_points
                   if axial(point) <= sleeve_edge + 0.006]
    arm_points = [point for material_name in ("Arm Glove", "Arm Skin")
                  for _index, point in vertices_by_material[material_name]
                  if abs(axial(point) - sleeve_edge) <= 0.006]
    assert edge_points and arm_points
    # A capped cuff has sleeve surface at or inside the underlying forearm in
    # every view, so no background can be seen through the interface.
    opening_gap = max(0.0, min(radial(point) for point in edge_points)
                      - max(radial(point) for point in arm_points))
    return skin_band, opening_gap


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
    sheet.filepath_raw = str(SHOT_DIR / "fp_arm_mh2_sheet.png")
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

    views = (
        ("back", (0.260, -0.320, 0.120), (0.026, 0.0, 0.020)),
        ("palm", (-0.245, -0.285, 0.115), (0.018, 0.0, 0.020)),
    )
    # Adjacent tiles are the same pose from back three-quarter and palm side.
    for name in ACTION_NAMES:
        for view_name, camera_g, target_g in views:
            camera.location = g2b(camera_g)
            look_at(camera, target_g)
            armature.animation_data.action = actions[name]
            scene.frame_set(1)
            bpy.context.view_layer.update()
            prop = add_preview_prop(name, side)
            scene.render.filepath = str(
                SHOT_DIR / f"fp_arm_mh2_{name.lower()}_{view_name}.png")
            bpy.ops.render.render(write_still=True)
            print("PREVIEW", scene.render.filepath)
            rendered.append(Path(scene.render.filepath))
            if prop:
                bpy.data.objects.remove(prop, do_unlink=True)

    armature.animation_data.action = actions["Grip"]
    scene.frame_set(1)
    bpy.context.view_layer.update()
    handle = add_preview_prop("Grip", side)
    camera.data.angle_y = math.radians(68.0)
    camera.location = g2b((0.21, 0.28, 0.52))
    look_at(camera, (0.0, 0.0, 0.0))
    scene.render.filepath = str(SHOT_DIR / "fp_arm_mh2_first_person.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    bpy.data.objects.remove(handle, do_unlink=True)

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
    bind_clearance = min(math.hypot(point.x, point.z) for point in in_handle_span)
    nearest = min(in_handle_span, key=lambda point: math.hypot(point.x, point.z))

    pose_tips = {}
    grip_clearance = None
    holdmag_inside = None
    finger_intersections = {}
    prop_intrusions = {}
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
        posed_finger_points = evaluated_finger_points(mesh)
        finger_intersections[action_name] = finger_surface_intersections(
            mesh, armature, action_name)
        prop_intrusions[action_name] = pose_prop_intrusions(action_name, posed_finger_points, side)
        if action_name == "Grip":
            candidates = [point for point in posed_points if abs(point.y) < 0.040]
            grip_clearance = min(math.hypot(point.x, point.z) for point in candidates)
            nearest = min(candidates, key=lambda point: math.hypot(point.x, point.z))
        if action_name == "HoldMag":
            holdmag_inside = prop_intrusions[action_name]
    grip_clearance_valid = grip_clearance >= 0.0169
    assert grip_clearance_valid, grip_clearance
    assert holdmag_inside == 0, holdmag_inside
    collision_total = sum(sum(counts.values()) for counts in finger_intersections.values())
    intrusion_total = sum(prop_intrusions.values())
    assert collision_total == 0, finger_intersections
    assert intrusion_total == 0, prop_intrusions

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
    skin_band, sleeve_glove_gap = sleeve_glove_measurements(mesh, armature)
    cuff_measurements_valid = (0.008 <= skin_band <= 0.0205
                               and sleeve_glove_gap <= 0.0005)
    assert cuff_measurements_valid, (skin_band, sleeve_glove_gap)

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
    print("  sleeve_glove", f"skin_band={skin_band:.5f}",
          f"widest_gap={sleeve_glove_gap:.5f}", "closed")
    print("  finger_intersections", {
        name: {"total": sum(counts.values()),
               "pairs": {pair: count for pair, count in counts.items() if count}}
        for name, counts in finger_intersections.items()
    })
    print("  prop_intrusions", prop_intrusions)
    print("  joint_flexion_degrees", POSE_ANGLES)
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
        "finger_intersections": finger_intersections,
        "sleeve_glove_gap": sleeve_glove_gap, "skin_band": skin_band,
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
    clean_scene(remove_actions=True)
    bpy.context.scene.render.fps = FPS
    mats = {
        "glove": material("Arm Glove", (0.028, 0.010, 0.004), 0.0, 0.82),
        "skin": material("Arm Skin", (0.48, 0.235, 0.135), 0.0, 0.80),
        "sleeve": material("Arm Sleeve", (0.030, 0.040, 0.047), 0.0, 0.94),
    }
    source_mesh, source_armature = build_source(HumanService)
    (right_id, right_path), right_mesh, right_armature = build_side(
        source_mesh, source_armature, mats, 1)
    bpy.data.objects.remove(right_mesh, do_unlink=True)
    bpy.data.objects.remove(right_armature, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    (left_id, left_path), _left_mesh, _left_armature = build_side(
        source_mesh, source_armature, mats, -1)
    # MPFB installs scene/load handlers.  Remove them before repeatedly replacing
    # the file state for glTF re-import validation; all MPFB work is finished now.
    addon_utils.disable("bl_ext.blender_org.mpfb", default_set=False)
    # Validate the non-rendered side first.  Blender 5.1's glTF importer can retain
    # stale evaluated render data if another GLB is imported after the preview pass.
    right = validate_reimport(right_id, right_path, 1, render=True)
    left = validate_reimport(left_id, left_path, -1, render=False)
    validate_mirror(right, left)


if __name__ == "__main__":
    main()
