"""Build Noise Floor's first-person arms from MPFB 2.0.18's CC0 human.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/fp_arm_mpfb.py

The MPFB HumanService creates a moderately muscular adult male and RigService supplies the
game_engine skeleton and weights.  Native right and left hands are cut from that human; the
left is never mirrored.  MPFB weights are merged onto the game's compact 17-bone contract,
then animator-authored UAL directions are retargeted onto its neutral bind pose.  The jacket
sleeve, turned cuff and tight-glove seam are deterministic procedural additions.

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
import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import material  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
SHOT_DIR = ROOT / ".shots"
UAL_PATH = Path(r"C:\projects\assets-src\quaternius-ual\UAL1_Standard.glb")
FPS = 30
ACTION_NAMES = ("Grip", "Open", "Flat", "HoldMag", "Pinch", "Fist")
UAL_POSE_SPECS = {
    # Frames chosen by inspecting both the silhouette and the individual phalanx
    # directions in Quaternius' CC0 Universal Animation Library.
    "Grip": ("Pistol_Idle_Loop", 0, "r"),
    # Idle_Loop's shipped hand channels are the library's closed default fist;
    # Idle_Talking frame 0 is the matching genuinely relaxed idle hand.
    "Open": ("Idle_Talking_Loop", 0, "r"),
    "Flat": ("Push_Loop", 32, "r"),
    "HoldMag": ("Pistol_Reload", 20, "l"),
    "Pinch": ("PickUp_Table", 12, "r"),
    "Fist": ("Punch_Jab", 10, "r"),
}
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
    bpy.context.scene.frame_set(0)


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


def load_ual_pose_library():
    """Sample animator-authored finger/wrist directions from the UAL mannequin.

    Values are directions in the posed hand/forearm frames, not copied Euler or
    quaternion channels.  Each direction is accompanied by the same bone's UAL
    rest direction, allowing the MPFB rest pose and bone rolls to be corrected
    geometrically when the pose is transferred.
    """
    assert UAL_PATH.exists(), UAL_PATH
    clean_scene(remove_actions=True)
    bpy.ops.import_scene.gltf(filepath=str(UAL_PATH), import_shading="FLAT")
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    armature.animation_data_create()
    library = {}
    for pose_name, (clip_name, frame, reference_side) in UAL_POSE_SPECS.items():
        action = bpy.data.actions.get(clip_name)
        assert action is not None, clip_name
        armature.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        hand_name = f"hand_{reference_side}"
        forearm_name = f"lowerarm_{reference_side}"
        hand_rest = armature.data.bones[hand_name].matrix_local.to_3x3()
        forearm_rest = armature.data.bones[forearm_name].matrix_local.to_3x3()
        hand_pose = armature.pose.bones[hand_name].matrix.to_3x3()
        forearm_pose = armature.pose.bones[forearm_name].matrix.to_3x3()
        finger_rest = {}
        finger_pose = {}
        for digit in ("Thumb", *FINGERS):
            for index in range(1, 4):
                source = source_name(digit, index, reference_side)
                output = output_name(digit, index)
                finger_rest[output] = (
                    hand_rest.inverted()
                    @ armature.data.bones[source].matrix_local.to_3x3()
                    @ Vector((0.0, 1.0, 0.0))
                ).normalized()
                finger_pose[output] = (
                    hand_pose.inverted()
                    @ armature.pose.bones[source].matrix.to_3x3()
                    @ Vector((0.0, 1.0, 0.0))
                ).normalized()
        # Canonical right-hand world directions.  Poses authored on the left
        # (HoldMag) are reflected once here, then every output side uses either
        # this canonical shape or its exact X mirror.
        finger_rest_world = {}
        finger_pose_world = {}
        for digit in ("Thumb", *FINGERS):
            for index in range(1, 4):
                source = source_name(digit, index, reference_side)
                output = output_name(digit, index)
                rest_world = (
                    armature.data.bones[source].matrix_local.to_3x3()
                    @ Vector((0.0, 1.0, 0.0))
                ).normalized()
                pose_world = (
                    hand_rest @ hand_pose.inverted()
                    @ armature.pose.bones[source].matrix.to_3x3()
                    @ Vector((0.0, 1.0, 0.0))
                ).normalized()
                if reference_side == "l":
                    rest_world.x *= -1.0
                    pose_world.x *= -1.0
                finger_rest_world[output] = rest_world
                finger_pose_world[output] = pose_world
        wrist_rest = (
            forearm_rest.inverted() @ hand_rest @ Vector((0.0, 1.0, 0.0))
        ).normalized()
        wrist_pose = (
            forearm_pose.inverted() @ hand_pose @ Vector((0.0, 1.0, 0.0))
        ).normalized()
        wrist_rest_world = (hand_rest @ Vector((0.0, 1.0, 0.0))).normalized()
        wrist_pose_world = (
            forearm_rest @ forearm_pose.inverted() @ hand_pose
            @ Vector((0.0, 1.0, 0.0))
        ).normalized()
        if reference_side == "l":
            wrist_rest_world.x *= -1.0
            wrist_pose_world.x *= -1.0
        library[pose_name] = {
            "clip": clip_name, "frame": frame, "reference_side": reference_side,
            "finger_rest": finger_rest, "finger_pose": finger_pose,
            "wrist_rest": wrist_rest, "wrist_pose": wrist_pose,
            "finger_rest_world": finger_rest_world,
            "finger_pose_world": finger_pose_world,
            "wrist_rest_world": wrist_rest_world,
            "wrist_pose_world": wrist_pose_world,
        }
        print("UAL_POSE", pose_name, "<-", clip_name, "frame", frame,
              "hand", reference_side)
        print("UAL_CURL", pose_name, {
            name: round(finger_rest_world[name].dot(finger_pose_world[name]), 3)
            for name in ("Thumb1", "Index1", "Index2", "Middle2", "Pinky2")
        })
    armature.animation_data.action = None
    return library


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

    # Pistol_Idle's curled phalanges define a grasp axis about 50 mm palmward
    # and 30 mm below the MPFB wrist placement.  Translate the complete hand and
    # arm to put that animator-authored aperture on the weapon axis; do not curl
    # the fingers farther to chase the prop.
    target_wrist_g = Vector((side * 0.00455, -0.010, 0.08350))
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


def make_rest_definition(source_armature, side, ual_library):
    suffix = source_side(side)
    source_bones = source_armature.data.bones
    hand_xform, hand_rotation, wrist_g = hand_transform(source_armature, side)
    # The single exported Forearm bone covers the complete visible arm.  Its far
    # end is at the shoulder, 0.75-0.8 m from the knuckles, and follows the
    # contract's +Z / 15-degree-down screen-exit direction.
    sleeve_end_g = Vector((side * 0.05755, -0.198, 0.75350))
    definition = {
        "Forearm": (sleeve_end_g, wrist_g, None),
    }

    source_hand = source_bones[f"hand_{suffix}"]
    hand_head = b2g(hand_xform @ source_hand.head_local)
    hand_tail = b2g(hand_xform @ source_hand.tail_local)
    definition["Hand"] = (hand_head, hand_tail, "Forearm")

    chains = {}
    natural_rel = {}
    for digit in ("Thumb", *FINGERS):
        source_chain = [source_bones[source_name(digit, 1, suffix)].head_local.copy()]
        for index in range(1, 4):
            source_chain.append(source_bones[source_name(digit, index, suffix)].tail_local.copy())
        lengths = [(source_chain[index + 1] - source_chain[index]).length for index in range(3)]
        target_root = b2g(hand_xform @ source_chain[0])
        directions = []
        for index in range(1, 4):
            name = output_name(digit, index)
            source_direction = (
                source_bones[source_name(digit, index, suffix)].tail_local
                - source_bones[source_name(digit, index, suffix)].head_local
            ).normalized()
            target_natural = (hand_rotation @ source_direction).normalized()
            natural_rel[name] = target_natural
            directions.append(b2g(target_natural))
        chain = target_chain(target_root, lengths, directions)
        chains[digit] = chain
        parent = "Hand"
        for index in range(3):
            name = output_name(digit, index + 1)
            definition[name] = (chain[index], chain[index + 1], parent)
            parent = name
    assert tuple(definition) == BONE_NAMES
    return definition, chains, hand_xform, hand_rotation, natural_rel


def build_armature(source_armature, side, ual_library):
    definition, chains, hand_xform, hand_rotation, natural_rel = make_rest_definition(
        source_armature, side, ual_library
    )
    suffix = source_side(side)
    source_bones = source_armature.data.bones
    # Copy every source rest transform before another armature enters Edit mode.
    # Blender invalidates Bone RNA references during edit-bone creation; holding
    # those references was the cause of the old intermittent displaced island.
    source_rest = {}
    for name in (f"lowerarm_{suffix}", f"hand_{suffix}",
                 *(source_name(digit, index, suffix)
                   for digit in ("Thumb", *FINGERS) for index in range(1, 4))):
        bone = source_bones[name]
        source_rest[name] = {
            "matrix": bone.matrix_local.copy(),
            "head": bone.head_local.copy(),
            "tail": bone.tail_local.copy(),
        }
    data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    rotations = {}

    source_forearm = source_rest[f"lowerarm_{suffix}"]
    source_forearm_rotation = source_forearm["matrix"].to_3x3()
    base_forearm_rotation = hand_rotation @ source_forearm_rotation
    forearm_direction = g2b(definition["Forearm"][1] - definition["Forearm"][0]).normalized()
    rotations["Forearm"] = orientation_with_y(base_forearm_rotation, forearm_direction)
    rotations["Hand"] = hand_rotation @ source_rest[f"hand_{suffix}"]["matrix"].to_3x3()
    for digit in ("Thumb", *FINGERS):
        for index in range(1, 4):
            name = output_name(digit, index)
            source_rotation = source_rest[source_name(digit, index, suffix)]["matrix"].to_3x3()
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
            source_bone = source_rest[source_name(digit, index, suffix)]
            target_bone = armature.data.bones[target_name]
            transforms[target_name] = target_bone.matrix_local @ source_bone["matrix"].inverted()
            assert (transforms[target_name] @ source_bone["head"] - target_bone.head_local).length < 1.0e-5
            assert (transforms[target_name] @ source_bone["tail"] - target_bone.tail_local).length < 1.0e-5
    src_tail = source_forearm["tail"]
    dst_tail = armature.data.bones["Forearm"].tail_local.copy()
    source_axis = (source_forearm["tail"] - source_forearm["head"]).normalized()
    target_axis = (armature.data.bones["Forearm"].tail_local
                   - armature.data.bones["Forearm"].head_local).normalized()
    relative_rotation = source_axis.rotation_difference(target_axis).to_matrix()
    transforms["Forearm"] = (Matrix.Translation(dst_tail) @ relative_rotation.to_4x4()
                              @ Matrix.Translation(-src_tail))
    return armature, definition, chains, transforms, natural_rel


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
        if sum(proximity[index] for index in indices) / len(indices) > 0.008:
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
            # A tight leather glove uses the MPFB hand itself.  Seven tenths of
            # a millimetre is enough to catch a highlight without turning the
            # fingers into the puffy offset shell rejected in the prior pass.
            source_point += source_normals[old_index] * 0.0007
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
            point_g.x += side * 0.0005 * (1.0 - abs(point_g.y) / 0.007)
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
        # The extracted anatomical surface is the tight glove itself.  Arm Skin
        # is supplied by a hidden under-cuff ring below, never by a loose shell.
        output_polygon.material_index = 0
        output_polygon.use_smooth = True
    boundary_mesh = bmesh.new()
    boundary_mesh.from_mesh(data)
    boundary_edges = [edge for edge in boundary_mesh.edges if edge.is_boundary]
    assert boundary_edges, "MPFB hand cut has no wrist boundary"
    bmesh.ops.holes_fill(boundary_mesh, edges=boundary_edges, sides=0)
    boundary_mesh.to_mesh(data)
    boundary_mesh.free()
    for polygon in data.polygons:
        polygon.use_smooth = True
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

    glove_cuff = make_ring_tube(
        "GloveCuffRidge",
        [at(0.006), at(0.011), at(0.016)],
        [(0.0345, 0.0390), (0.0353, 0.0398), (0.0345, 0.0390)],
        mats["glove"], {"Forearm": 1.0}, sides=20, fold=0.00035,
    )
    skin_under_cuff = make_ring_tube(
        "SkinUnderCuff",
        [at(0.014), at(0.022), at(0.030)],
        [(0.031, 0.035), (0.032, 0.036), (0.032, 0.036)],
        mats["skin"], {"Forearm": 1.0}, sides=16,
    )
    turned_cuff = make_ring_tube(
        "TurnedSleeveCuff",
        [at(-0.010), at(0.004), at(0.020), at(0.038), at(0.057)],
        [(0.037, 0.041), (0.040, 0.045), (0.043, 0.048),
         (0.044, 0.049), (0.041, 0.046)],
        mats["sleeve"], {"Forearm": 1.0}, sides=20, fold=0.0012,
    )
    # A slightly bent, anatomical path: mostly straight forearm, a shallow
    # 17-degree elbow transition, then a broader upper arm to the shoulder.
    distances = (0.052, 0.095, 0.165, 0.255, 0.345, 0.440, 0.535, 0.625, length)
    centres = []
    elbow = min(0.345, length * 0.48)
    bend = Vector((side * 0.075, -0.045, 0.010))
    for distance in distances:
        factor = max(0.0, min(1.0, (distance - elbow) / max(0.001, length - elbow)))
        centres.append(at(distance) + bend * math.sin(factor * math.pi * 0.5))
    sleeve = make_ring_tube(
        "CanvasSleeve",
        centres,
        [(0.039, 0.044), (0.041, 0.046), (0.043, 0.048),
         (0.046, 0.051), (0.051, 0.056), (0.056, 0.061),
         (0.062, 0.067), (0.067, 0.072), (0.071, 0.076)],
        mats["sleeve"], {"Forearm": 1.0}, sides=20, fold=0.0017, cap_end=True,
    )
    return [skin_under_cuff, glove_cuff, turned_cuff, sleeve]


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
    if projected_triangles < 18000:
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


def pose_targets(armature, side, natural_rel, ual_library):
    """Retarget UAL directions after aligning every source/MPFB rest bone."""
    target_hand_rest = armature.data.bones["Hand"].matrix_local.to_3x3()
    target_forearm_rest = armature.data.bones["Forearm"].matrix_local.to_3x3()
    target_wrist_world = (target_hand_rest @ Vector((0.0, 1.0, 0.0))).normalized()
    target_wrist = (
        target_forearm_rest.inverted() @ target_wrist_world
    ).normalized()
    grip_sample = ual_library["Grip"]
    grip_rest = grip_sample["wrist_rest_world"].copy()
    grip_pose = grip_sample["wrist_pose_world"].copy()
    if side < 0:
        grip_rest.x *= -1.0
        grip_pose.x *= -1.0
    grip_wrist = (grip_rest.rotation_difference(target_wrist_world) @ grip_pose).normalized()
    result = {}
    for pose_name in ACTION_NAMES:
        sample = ual_library[pose_name]
        directions = {}
        for digit in ("Thumb", *FINGERS):
            for index in range(1, 4):
                name = output_name(digit, index)
                source_rest = sample["finger_rest_world"][name].copy()
                source_pose = sample["finger_pose_world"][name].copy()
                if side < 0:
                    source_rest.x *= -1.0
                    source_pose.x *= -1.0
                correction = source_rest.rotation_difference(natural_rel[name])
                target_world = (correction @ source_pose).normalized()
                if pose_name == "Flat":
                    # Push_Loop closes the distal joints more than a production
                    # flat-palm read needs on this higher-detail MPFB hand.  A
                    # small rest-direction blend keeps the animator's pose while
                    # separating neighbouring fingertips.
                    target_world = target_world.slerp(natural_rel[name], 0.18).normalized()
                directions[name] = (target_hand_rest.inverted() @ target_world).normalized()
        source_wrist_rest = sample["wrist_rest_world"].copy()
        source_wrist_pose = sample["wrist_pose_world"].copy()
        if side < 0:
            source_wrist_rest.x *= -1.0
            source_wrist_pose.x *= -1.0
        mapped_wrist = (
            source_wrist_rest.rotation_difference(target_wrist_world) @ source_wrist_pose
        ).normalized()
        wrist_delta = grip_wrist.rotation_difference(mapped_wrist)
        desired_wrist_world = (wrist_delta @ target_wrist_world).normalized()
        result[pose_name] = {
            "wrist": (target_forearm_rest.inverted() @ desired_wrist_world).normalized(),
            "fingers": directions,
        }
        if pose_name == "Pinch":
            chains = {}
            for digit in ("Thumb", "Index"):
                root = target_hand_rest.inverted() @ armature.data.bones[f"{digit}1"].head_local
                points = [root]
                for index in range(1, 4):
                    length = armature.data.bones[f"{digit}{index}"].length
                    points.append(points[-1] + directions[f"{digit}{index}"] * length)
                chains[digit] = points
            pinch_target = (chains["Thumb"][-1] + chains["Index"][-1]) * 0.5
            for digit in ("Thumb", "Index"):
                fitted = fabrik(chains[digit], pinch_target)
                for index in range(3):
                    directions[f"{digit}{index + 1}"] = (
                        fitted[index + 1] - fitted[index]
                    ).normalized()
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
    hand = armature.pose.bones["Hand"]
    forearm_rotation = armature.pose.bones["Forearm"].matrix.to_3x3()
    desired_hand_direction = (forearm_rotation @ targets["wrist"]).normalized()
    current_hand_direction = (hand.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
    hand_swing = current_hand_direction.rotation_difference(desired_hand_direction)
    hand.matrix = (Matrix.Translation(hand.head)
                   @ (hand_swing.to_matrix() @ hand.matrix.to_3x3()).to_4x4())
    bpy.context.view_layer.update()
    assert hand.location.length < 2.5e-4, hand.location[:]
    hand.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    hand_rotation = hand.matrix.to_3x3()
    for digit in ("Thumb", *FINGERS):
        for index in range(3):
            pose_bone = armature.pose.bones[f"{digit}{index + 1}"]
            target_direction = (
                hand_rotation @ targets["fingers"][pose_bone.name]
            ).normalized()
            current_direction = (
                pose_bone.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0))
            ).normalized()
            swing = current_direction.rotation_difference(target_direction)
            rotation = swing.to_matrix() @ pose_bone.matrix.to_3x3()
            pose_bone.matrix = Matrix.Translation(pose_bone.head) @ rotation.to_4x4()
            bpy.context.view_layer.update()
            assert pose_bone.location.length < 2.5e-4, (pose_bone.name, pose_bone.location[:])
            pose_bone.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def make_actions(armature, side, natural_rel, ual_library):
    armature.animation_data_create()
    targets = pose_targets(armature, side, natural_rel, ual_library)
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


def build_side(HumanService, side, ual_library):
    clean_scene(remove_actions=True)
    bpy.context.scene.render.fps = FPS
    mats = {
        "glove": material("Arm Glove", (0.028, 0.010, 0.004), 0.0, 0.82),
        "skin": material("Arm Skin", (0.48, 0.235, 0.135), 0.0, 0.80),
        "sleeve": material("Arm Sleeve", (0.030, 0.040, 0.047), 0.0, 0.94),
    }
    source_mesh, source_armature = build_source(HumanService)
    armature, definition, _chains, transforms, natural_rel = build_armature(
        source_armature, side, ual_library
    )
    hand = extract_mpfb_arm(source_mesh, source_armature, armature, side, transforms, mats)
    clothing = add_clothing_parts(side, definition, mats)
    mesh = join_and_finish([hand, *clothing], armature)
    make_actions(armature, side, natural_rel, ual_library)
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


def segment_distance(first_a, first_b, second_a, second_b):
    """Shortest distance between two 3D line segments."""
    first = first_b - first_a
    second = second_b - second_a
    offset = first_a - second_a
    aa = first.dot(first)
    bb = first.dot(second)
    cc = second.dot(second)
    dd = first.dot(offset)
    ee = second.dot(offset)
    denominator = aa * cc - bb * bb
    if denominator < 1.0e-12:
        s = 0.0
        t = max(0.0, min(1.0, ee / cc if cc > 1.0e-12 else 0.0))
    else:
        s = max(0.0, min(1.0, (bb * ee - cc * dd) / denominator))
        t = (bb * s + ee) / cc if cc > 1.0e-12 else 0.0
        if t < 0.0:
            t = 0.0
            s = max(0.0, min(1.0, -dd / aa if aa > 1.0e-12 else 0.0))
        elif t > 1.0:
            t = 1.0
            s = max(0.0, min(1.0, (bb - dd) / aa if aa > 1.0e-12 else 0.0))
    return (offset + first * s - second * t).length


def finger_capsule_intersections(armature):
    """Conservative centreline/capsule check for non-neighbouring phalanges."""
    # A 0.2 mm core catches true phalanx centreline crossovers without treating
    # normal skin contact between neighbouring fingers as penetration.
    radii = {digit: (0.0002, 0.0002, 0.0002)
             for digit in ("Thumb", *FINGERS)}
    segments = []
    for digit in ("Thumb", *FINGERS):
        for index in range(1, 4):
            bone = armature.pose.bones[f"{digit}{index}"]
            segments.append((digit, index, bone.head.copy(), bone.tail.copy(), radii[digit][index - 1]))
    hits = []
    minimum_gap = float("inf")
    for first_index, first in enumerate(segments):
        for second in segments[first_index + 1:]:
            if first[0] == second[0] and abs(first[1] - second[1]) <= 1:
                continue
            # Proximal phalanges meet the shared palm/webbing surface, so their
            # anatomical overlap is not a finger-on-finger self-intersection.
            if first[0] != second[0] and (first[1] == 1 or second[1] == 1):
                continue
            distance = segment_distance(first[2], first[3], second[2], second[3])
            gap = distance - first[4] - second[4]
            minimum_gap = min(minimum_gap, gap)
            if gap < 0.0:
                hits.append((f"{first[0]}{first[1]}", f"{second[0]}{second[1]}", gap))
    return hits, minimum_gap


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
    sheet.filepath_raw = str(SHOT_DIR / "fp_arm_ual_sheet.png")
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

    camera.location = g2b((-0.235, -0.300, 0.100))
    look_at(camera, (0.0, 0.0, 0.0))
    for name in ACTION_NAMES:
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_ual_{name.lower()}.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
        rendered.append(Path(scene.render.filepath))
        if prop:
            bpy.data.objects.remove(prop, do_unlink=True)

    camera.location = g2b((0.245, -0.285, 0.115))
    look_at(camera, (0.0, 0.0, 0.0))
    for name in ("Grip", "HoldMag"):
        armature.animation_data.action = actions[name]
        scene.frame_set(1)
        bpy.context.view_layer.update()
        prop = add_preview_prop(name, side)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_ual_{name.lower()}_back.png")
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
    scene.render.filepath = str(SHOT_DIR / "fp_arm_ual_first_person.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    camera.data.angle_y = math.radians(75.0)
    camera.location = g2b((0.0, 0.20, 0.45))
    look_at(camera, (0.0, 0.0, 0.0))
    scene.render.filepath = str(SHOT_DIR / "fp_arm_ual_wide_first_person.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)
    rendered.append(Path(scene.render.filepath))
    bpy.data.objects.remove(handle, do_unlink=True)

    armature.animation_data.action = None
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
    assert triangles < 18000, triangles
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
    assert clearance >= 0.0001, (clearance, nearest)

    pose_tips = {}
    finger_intersections = {}
    finger_min_gaps = {}
    grip_clearance = None
    grip_inside = None
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
        hits, minimum_gap = finger_capsule_intersections(armature)
        finger_intersections[action_name] = len(hits)
        finger_min_gaps[action_name] = minimum_gap
        assert not hits, (action_name, hits)
        posed_points = evaluated_points(mesh)
        if action_name == "Grip":
            candidates = [point for point in posed_points if abs(point.y) < 0.040]
            grip_clearance = min(math.hypot(point.x, point.z) for point in candidates)
            grip_inside = sum(math.hypot(point.x, point.z) < 0.0168 for point in candidates)
        if action_name == "HoldMag":
            centre = Vector((side * 0.023, 0.0, -0.040))
            holdmag_inside = sum(
                abs(point.x - centre.x) < 0.011 - 0.0005
                and abs(point.y - centre.y) < 0.015 - 0.0005
                and abs(point.z - centre.z) < 0.060 - 0.0005
                for point in posed_points
            )
    assert 0.0170 <= grip_clearance <= 0.0180, grip_clearance
    assert grip_inside == 0, grip_inside
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
    arm_length = sleeve_end.length
    assert 0.75 <= arm_length <= 0.82, arm_length
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
          "nearest", tuple(round(value, 5) for value in nearest),
          "interior_vertices", grip_inside)
    print("  glove_handle_span_y", f"{hand_span:.5f}")
    print("  sleeve_direction", f"({sleeve_direction.x:.5f},{sleeve_direction.y:.5f},{sleeve_direction.z:.5f})")
    print("  holdmag_centre", f"({mag_centre.x:.5f},{mag_centre.y:.5f},{mag_centre.z:.5f})",
          "axis", f"({mag_axis.x:.1f},{mag_axis.y:.1f},{mag_axis.z:.1f})",
          "interior_vertices", holdmag_inside)
    print("  finger_intersections", finger_intersections,
          "minimum_capsule_gaps", {name: round(gap, 5)
                                    for name, gap in finger_min_gaps.items()})
    print("  arm_length_knuckles_to_shoulder", f"{arm_length:.5f}")
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
        "finger_intersections": finger_intersections, "arm_length": arm_length,
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
    ual_library = load_ual_pose_library()
    print("MPFB_SETTINGS", MACRO_SETTINGS)
    print("MPFB_TARGET_STACK", TargetService.calculate_target_stack_from_macro_info_dict(MACRO_SETTINGS))
    right_id, right_path = build_side(HumanService, 1, ual_library)
    left_id, left_path = build_side(HumanService, -1, ual_library)
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
