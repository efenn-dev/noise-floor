"""Build Noise Floor's five realistic zombies from MakeHuman/MPFB and Quaternius UAL.

Run with Blender 5.1 (the all-five build is the default):
    blender.exe -b --factory-startup --python tools/art/zombie_mpfb.py
    blender.exe -b --factory-startup --python tools/art/zombie_mpfb.py -- --variant=heavy

MPFB 2.0.18 supplies each adult body and its 53-bone ``game_engine`` rig.  Quaternius
Universal Animation Library 1 and 2 supply the CC0 motion.  Motion is corrected from the
UAL rest pose to the MPFB rest pose, then baked onto the game's established compact 17-bone
zombie contract.  The human surface is reduced, and offset copies of its own weighted surface
form torn clothing; the exported GLB remains one skinned mesh under 25k triangles.

The original UAL GLBs are intentionally local-only at ``UAL_DIR`` and are too large to commit.
Cloud sessions can use the committed zombie GLBs but cannot rebuild them.

Axis contract: MakeHuman, UAL, and construction coordinates are Blender Z-up with the person
facing -Y.  Blender's glTF exporter converts this to Godot Y-up; ``zombie_body.gd`` turns the
model PI so the body walks toward game -Z.
"""

import importlib
import math
import os
import sys
from collections import OrderedDict
from pathlib import Path

import addon_utils
import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import material  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
SHOT_DIR = ROOT / ".shots"
FRAME_DIR = SHOT_DIR / ".zombie_mh_frames"
UAL_DIR = Path(r"C:\projects\assets-src\quaternius-ual")
UAL1 = UAL_DIR / "UAL1_Standard.glb"
UAL2 = UAL_DIR / "UAL2_Standard.glb"
FPS = 30
SOURCE_FPS = 24.0
MAX_TRIANGLES = 25000
APPROVED_MATERIALS = {
    "Zombie Skin", "Shirt", "Jeans", "Boots", "Hair", "Eyes", "Stain", "Shadow",
    "Vest", "Hard Hat", "Cap",
}
ACTION_NAMES = ("Idle", "Walk", "Run", "Punch", "Crawl", "Death", "HitReact", "Scream")
LOOPED = {"Idle", "Walk", "Run", "Punch", "Crawl"}


def _arg(name, default):
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for value in argv:
        if value.startswith(f"--{name}="):
            return value.split("=", 1)[1]
    return os.environ.get(name.upper(), default)


VARIANTS = OrderedDict((
    ("default", {
        "height": 1.78,
        "macro": {"gender": 0.90, "age": 0.54, "muscle": 0.42, "weight": 0.48,
                  "proportions": 0.52, "height": 0.53, "cupsize": 0.50, "firmness": 0.50},
        "sleeves": "short", "hair": "short", "extra": None,
    }),
    ("heavy", {
        "height": 1.80,
        "width": 1.06,
        "macro": {"gender": 0.92, "age": 0.56, "muscle": 0.34, "weight": 0.88,
                  "proportions": 0.45, "height": 0.50, "cupsize": 0.50, "firmness": 0.50},
        "sleeves": "short", "hair": "short", "extra": "hardhat", "vest": True,
    }),
    ("slim", {
        "height": 1.84,
        "macro": {"gender": 0.90, "age": 0.66, "muscle": 0.16, "weight": 0.10,
                  "proportions": 0.60, "height": 0.61, "cupsize": 0.50, "firmness": 0.50},
        "sleeves": "long", "hair": "short", "extra": None,
    }),
    ("short", {
        "height": 1.62,
        "macro": {"gender": 0.86, "age": 0.48, "muscle": 0.38, "weight": 0.52,
                  "proportions": 0.46, "height": 0.38, "cupsize": 0.50, "firmness": 0.50},
        "sleeves": "short", "hair": "short", "extra": "cap",
    }),
    ("woman", {
        "height": 1.70,
        "macro": {"gender": 0.08, "age": 0.50, "muscle": 0.28, "weight": 0.43,
                  "proportions": 0.55, "height": 0.45, "cupsize": 0.58, "firmness": 0.44},
        "sleeves": "short", "hair": "long", "extra": None,
    }),
))


# Ordered parents are also the bake order.  Each tuple is (source head bone, source tail bone,
# parent); Chest spans the two discarded middle-spine joints and Foot includes the toe joint.
BONE_DEFINITION = OrderedDict((
    ("Hips", ("pelvis", "pelvis", None)),
    ("Spine", ("spine_01", "spine_01", "Hips")),
    ("Chest", ("spine_02", "spine_03", "Spine")),
    ("Neck", ("neck_01", "neck_01", "Chest")),
    ("Head", ("head", "head", "Neck")),
    ("UpperArm.L", ("upperarm_l", "upperarm_l", "Chest")),
    ("LowerArm.L", ("lowerarm_l", "lowerarm_l", "UpperArm.L")),
    ("Hand.L", ("hand_l", "hand_l", "LowerArm.L")),
    ("UpperArm.R", ("upperarm_r", "upperarm_r", "Chest")),
    ("LowerArm.R", ("lowerarm_r", "lowerarm_r", "UpperArm.R")),
    ("Hand.R", ("hand_r", "hand_r", "LowerArm.R")),
    ("UpperLeg.L", ("thigh_l", "thigh_l", "Hips")),
    ("LowerLeg.L", ("calf_l", "calf_l", "UpperLeg.L")),
    ("Foot.L", ("foot_l", "ball_l", "LowerLeg.L")),
    ("UpperLeg.R", ("thigh_r", "thigh_r", "Hips")),
    ("LowerLeg.R", ("calf_r", "calf_r", "UpperLeg.R")),
    ("Foot.R", ("foot_r", "ball_r", "LowerLeg.R")),
))
BONE_NAMES = tuple(BONE_DEFINITION)
RETARGET_SOURCE = {
    "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_03", "Neck": "neck_01",
    "Head": "Head", "UpperArm.L": "upperarm_l", "LowerArm.L": "lowerarm_l",
    "Hand.L": "hand_l", "UpperArm.R": "upperarm_r", "LowerArm.R": "lowerarm_r",
    "Hand.R": "hand_r", "UpperLeg.L": "thigh_l", "LowerLeg.L": "calf_l",
    "Foot.L": "foot_l", "UpperLeg.R": "thigh_r", "LowerLeg.R": "calf_r",
    "Foot.R": "foot_r",
}
CLIP_SOURCE = {
    "Idle": (2, "Zombie_Idle_Loop"),
    "Walk": (2, "Zombie_Walk_Fwd_Loop"),
    "Run": (1, "Sprint_Loop"),
    "Punch": (2, "Zombie_Scratch"),
    "Crawl": (1, "Crouch_Fwd_Loop"),
    "Death": (1, "Death01"),
    "HitReact": (1, "Hit_Chest"),
}


def clean_scene(remove_actions=True):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.armatures, bpy.data.cameras, bpy.data.lights,
                   bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    if remove_actions:
        for action in list(bpy.data.actions):
            bpy.data.actions.remove(action)


def enable_mpfb():
    """Enable the extension headlessly without writing Blender preferences."""
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
    from bl_ext.blender_org.mpfb.services import HumanService
    print("MPFB", enabled.VERSION, "enabled")
    return HumanService


def build_materials(spec):
    jeans = (0.035, 0.052, 0.075)
    if spec.get("extra") == "hardhat":
        jeans = (0.13, 0.095, 0.050)
    elif spec.get("extra") == "cap":
        jeans = (0.085, 0.050, 0.030)
    mats = {
        "skin": material("Zombie Skin", (0.105, 0.145, 0.095), 0.0, 0.91),
        "shirt": material("Shirt", (0.13, 0.075, 0.050), 0.0, 0.93),
        "jeans": material("Jeans", jeans, 0.0, 0.95),
        "boots": material("Boots", (0.042, 0.034, 0.028), 0.0, 0.88),
        "hair": material("Hair", (0.012, 0.009, 0.007), 0.0, 0.98),
        "eyes": material("Eyes", (0.10, 0.003, 0.002), 0.0, 0.72),
        "stain": material("Stain", (0.040, 0.002, 0.002), 0.0, 0.96),
        "shadow": material("Shadow", (0.018, 0.014, 0.012), 0.0, 1.0),
    }
    if spec.get("vest"):
        mats["vest"] = material("Vest", (0.48, 0.22, 0.035), 0.0, 0.86)
    if spec.get("extra") == "hardhat":
        mats["hardhat"] = material("Hard Hat", (0.52, 0.37, 0.045), 0.04, 0.58)
    if spec.get("extra") == "cap":
        mats["cap"] = material("Cap", (0.055, 0.095, 0.20), 0.0, 0.94)
    return mats


def source_to_target_group(name):
    direct = {
        "Root": "Hips", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest",
        "spine_03": "Chest", "clavicle_l": "Chest", "clavicle_r": "Chest",
        "neck_01": "Neck", "head": "Head", "upperarm_l": "UpperArm.L",
        "lowerarm_l": "LowerArm.L", "upperarm_r": "UpperArm.R",
        "lowerarm_r": "LowerArm.R", "thigh_l": "UpperLeg.L", "calf_l": "LowerLeg.L",
        "foot_l": "Foot.L", "ball_l": "Foot.L", "thigh_r": "UpperLeg.R",
        "calf_r": "LowerLeg.R", "foot_r": "Foot.R", "ball_r": "Foot.R",
    }
    if name in direct:
        return direct[name]
    if name.endswith("_l") and any(token in name for token in ("hand", "thumb", "index", "middle", "ring", "pinky")):
        return "Hand.L"
    if name.endswith("_r") and any(token in name for token in ("hand", "thumb", "index", "middle", "ring", "pinky")):
        return "Hand.R"
    return None


def normalized_weights(source_mesh):
    group_names = {group.index: group.name for group in source_mesh.vertex_groups}
    result = []
    for vertex in source_mesh.data.vertices:
        merged = {}
        for item in vertex.groups:
            target = source_to_target_group(group_names[item.group])
            if target:
                merged[target] = merged.get(target, 0.0) + item.weight
        strongest = sorted(merged.items(), key=lambda pair: pair[1], reverse=True)[:4]
        total = sum(value for _name, value in strongest)
        result.append({name: value / total for name, value in strongest} if total > 1.0e-8 else {})
    return result


def body_faces(source_mesh, evaluated_data):
    body = source_mesh.vertex_groups.get("body")
    assert body is not None
    body_vertices = {vertex.index for vertex in source_mesh.data.vertices
                     if any(item.group == body.index and item.weight > 0.5 for item in vertex.groups)}
    faces = [polygon for polygon in evaluated_data.polygons
             if all(index in body_vertices for index in polygon.vertices)]
    assert len(faces) > 10000, len(faces)
    return faces


def transformed_point(point, floor_z, scale):
    return Vector((point.x * scale, point.y * scale, (point.z - floor_z) * scale))


def build_compact_armature(source_armature, floor_z, scale):
    source = source_armature.data.bones
    data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, (head_name, tail_name, _parent) in BONE_DEFINITION.items():
        head_source = source[head_name]
        tail_source = source[tail_name]
        bone = data.edit_bones.new(name)
        bone.head = transformed_point(head_source.head_local, floor_z, scale)
        bone.tail = transformed_point(tail_source.tail_local, floor_z, scale)
        if (bone.tail - bone.head).length < 0.02:
            bone.tail.z += 0.02
        roll_source = tail_source.matrix_local.to_3x3() @ Vector((0.0, 0.0, 1.0))
        bone.align_roll(roll_source)
        bone.use_deform = True
        made[name] = bone
    for name, (_head, _tail, parent) in BONE_DEFINITION.items():
        if parent:
            made[name].parent = made[parent]
            made[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def build_body(source_mesh, source_armature, target_height, skin_material):
    for modifier in source_mesh.modifiers:
        if modifier.type == "ARMATURE":
            modifier.show_viewport = False
            modifier.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = source_mesh.evaluated_get(depsgraph)
    evaluated_data = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    faces = body_faces(source_mesh, evaluated_data)
    used = sorted({index for polygon in faces for index in polygon.vertices})
    mesh_to_rig = source_armature.matrix_world.inverted() @ source_mesh.matrix_world
    source_points = [mesh_to_rig @ vertex.co for vertex in evaluated_data.vertices]
    floor_z = min(source_points[index].z for index in used)
    top_z = max(source_points[index].z for index in used)
    # Leave a little height for close hair without changing the requested overall stature.
    scale = (target_height - 0.025) / (top_z - floor_z)
    weights = normalized_weights(source_mesh)
    remap = {old: new for new, old in enumerate(used)}
    vertices = [tuple(transformed_point(source_points[index], floor_z, scale)) for index in used]
    polygons = [tuple(remap[index] for index in polygon.vertices) for polygon in faces]
    data = bpy.data.meshes.new("Zombie")
    data.from_pydata(vertices, [], polygons)
    data.materials.append(skin_material)
    body = bpy.data.objects.new("Zombie", data)
    bpy.context.collection.objects.link(body)
    groups = {name: body.vertex_groups.new(name=name) for name in BONE_NAMES}
    for new_index, old_index in enumerate(used):
        vertex_weights = weights[old_index]
        if not vertex_weights:
            vertex_weights = {"Hips": 1.0}
        for name, value in vertex_weights.items():
            groups[name].add([new_index], value, "REPLACE")
    for polygon in data.polygons:
        polygon.use_smooth = True
    evaluated.to_mesh_clear()

    # MPFB's body is intentionally detailed enough to survive a conservative reduction.
    data.calc_loop_triangles()
    before = len(data.loop_triangles)
    decimate = body.modifiers.new("Production reduction", "DECIMATE")
    decimate.ratio = min(1.0, 12500.0 / before)
    decimate.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    body.data.calc_loop_triangles()
    print("BODY_REDUCTION", before, "->", len(body.data.loop_triangles))
    armature = build_compact_armature(source_armature, floor_z, scale)
    return body, armature, scale


def vertex_weight_map(mesh, vertex):
    names = {group.index: group.name for group in mesh.vertex_groups}
    return {names[item.group]: item.weight for item in vertex.groups if item.group in names}


def polygon_scores(mesh, polygon):
    scores = {name: 0.0 for name in BONE_NAMES}
    for index in polygon.vertices:
        for name, value in vertex_weight_map(mesh, mesh.data.vertices[index]).items():
            scores[name] += value / len(polygon.vertices)
    return scores


def make_shell(body, name, mat, offset, predicate):
    """Copy a weighted region of the reduced body and push it along its own normals."""
    selected = []
    for polygon in body.data.polygons:
        centre = sum((body.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
        scores = polygon_scores(body, polygon)
        if predicate(centre, scores, polygon.index):
            selected.append(polygon)
    assert selected, name
    used = sorted({index for polygon in selected for index in polygon.vertices})
    remap = {old: new for new, old in enumerate(used)}
    vertices = [tuple(body.data.vertices[index].co + body.data.vertices[index].normal * offset)
                for index in used]
    faces = [tuple(remap[index] for index in polygon.vertices) for polygon in selected]
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    shell = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(shell)
    groups = {group.name: shell.vertex_groups.new(name=group.name) for group in body.vertex_groups}
    for new_index, old_index in enumerate(used):
        for group_name, value in vertex_weight_map(body, body.data.vertices[old_index]).items():
            groups[group_name].add([new_index], value, "REPLACE")
    for polygon in data.polygons:
        polygon.use_smooth = True
    return shell


def score(scores, *names):
    return sum(scores.get(name, 0.0) for name in names)


def weighted_primitive(obj, mat, bone):
    obj.data.materials.append(mat)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def ico_part(name, location, scale, mat, bone, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return weighted_primitive(obj, mat, bone)


def box_part(name, location, dimensions, mat, bone, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Worn edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return weighted_primitive(obj, mat, bone)


def make_work_boot(name, foot, mat, bone):
    """A rounded, foot-following work boot with a heel, collar, toe cap and lace bumps."""
    # MPFB's foot bone points toward its heel in this construction space; the model faces -Y.
    forward = (foot.head_local - foot.tail_local).copy()
    forward.z = 0.0
    forward.normalize()
    lateral = Vector((-forward.y, forward.x, 0.0))
    ankle = foot.head_local.copy()
    sole_z = 0.012
    # Back to front.  The raised instep and broad toe avoid the old flat-box silhouette.
    sections = (
        (0.075, 0.078, 0.115),
        (0.025, 0.083, 0.145),
        (-0.060, 0.087, 0.128),
        (-0.130, 0.092, 0.110),
        (-0.200, 0.094, 0.086),
        (-0.265, 0.090, 0.065),
    )
    vertices = []
    for along, half_width, height in sections:
        centre = ankle + forward * along
        # Six points make a softly squared leather cross-section with a curved crown.
        for side, z_fraction in ((-1.0, 0.0), (-1.0, 0.55), (-0.55, 1.0),
                                 (0.55, 1.0), (1.0, 0.55), (1.0, 0.0)):
            point = centre + lateral * (half_width * side)
            point.z = sole_z + height * z_fraction
            vertices.append(tuple(point))
    faces = []
    ring = 6
    faces.append(tuple(reversed(range(ring))))
    for section in range(len(sections) - 1):
        a = section * ring
        b = (section + 1) * ring
        for index in range(ring):
            nxt = (index + 1) % ring
            faces.append((a + index, a + nxt, b + nxt, b + index))
    last = (len(sections) - 1) * ring
    faces.append(tuple(last + index for index in range(ring)))
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    boot = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(boot)
    weighted_primitive(boot, mat, bone)
    pieces = [boot]

    midpoint = ankle + forward * -0.085
    angle = math.atan2(forward.y, forward.x) + math.pi * 0.5
    # A separate rubber sole and block heel make the shape read as a work boot at game distance.
    pieces.append(box_part(f"{name} Sole", midpoint + Vector((0, 0, -0.002)),
                          (0.190, 0.360, 0.024), mat, bone, bevel=0.010,
                          rotation=(0.0, 0.0, angle)))
    heel_centre = ankle + forward * 0.055
    heel_centre.z = 0.022
    pieces.append(box_part(f"{name} Heel", heel_centre, (0.145, 0.085, 0.045),
                          mat, bone, bevel=0.010, rotation=(0.0, 0.0, angle)))
    # Collar rolls and four broad lace bars are intentionally raised enough to survive texturing.
    collar_centre = ankle + forward * 0.035
    collar_centre.z = 0.132
    pieces.append(ico_part(f"{name} Collar", collar_centre, (0.090, 0.073, 0.025),
                          mat, bone, 2))
    toe_centre = ankle + forward * -0.215
    toe_centre.z = 0.075
    pieces.append(ico_part(f"{name} Toe Cap", toe_centre, (0.082, 0.060, 0.035),
                          mat, bone, 2))
    for index, along in enumerate((-0.040, -0.082, -0.124)):
        centre = ankle + forward * along
        centre.z = 0.152 - index * 0.015
        pieces.append(box_part(f"{name} Lace {index}", centre,
                              (0.130, 0.012, 0.009), mat, bone, bevel=0.004,
                              rotation=(0.0, 0.0, angle)))
    return pieces


def make_hat_dome(name, centre, radii, mat, bone, brim=False):
    vertices = []
    faces = []
    rings = 5
    sides = 18
    for ring in range(rings):
        phi = (math.pi * 0.5) * ring / (rings - 1)
        z = centre.z + radii.z * math.cos(phi)
        radius = math.sin(phi)
        row = []
        for side in range(sides):
            angle = 2.0 * math.pi * side / sides
            row.append(len(vertices))
            vertices.append((centre.x + radii.x * radius * math.cos(angle),
                             centre.y + radii.y * radius * math.sin(angle), z))
        if ring:
            previous = list(range(len(vertices) - sides * 2, len(vertices) - sides))
            for side in range(sides):
                nxt = (side + 1) % sides
                faces.append((previous[side], previous[nxt], row[nxt], row[side]))
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    weighted_primitive(obj, mat, bone)
    pieces = [obj]
    if brim:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=max(radii.x, radii.y) * 1.12,
                                            depth=0.018, location=(centre.x, centre.y, centre.z))
        pieces.append(weighted_primitive(bpy.context.object, mat, bone))
    return pieces


def body_bounds(body):
    points = [body.matrix_world @ vertex.co for vertex in body.data.vertices]
    return (Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
            Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))))


def add_clothing_and_details(body, armature, spec, mats):
    parts = [body]
    bones = armature.data.bones
    hips_z = bones["Hips"].head_local.z
    chest_z = bones["Chest"].head_local.z
    neck_z = bones["Neck"].head_local.z
    knee_z = (bones["UpperLeg.L"].tail_local.z + bones["UpperLeg.R"].tail_local.z) * 0.5
    boot_top = max(0.22, bones["LowerLeg.L"].tail_local.z + 0.10)

    def shirt_region(centre, scores, polygon_index):
        torso = score(scores, "Spine", "Chest") > 0.16 and hips_z - 0.055 < centre.z < neck_z + 0.015
        sleeve = False
        if spec["sleeves"] != "none":
            sleeve_score = score(scores, "UpperArm.L", "UpperArm.R")
            lower_score = score(scores, "LowerArm.L", "LowerArm.R")
            if spec["sleeves"] == "long":
                sleeve = sleeve_score + lower_score > 0.28
            else:
                shoulders = (bones["UpperArm.L"].head_local, bones["UpperArm.R"].head_local)
                sleeve = sleeve_score > 0.28 and min((centre - point).length for point in shoulders) < 0.22
        jagged_hem = centre.z > hips_z - 0.045 + 0.018 * math.sin(31.0 * centre.x + polygon_index)
        chest_hole = (centre.y < -0.11 and ((centre.x + 0.105) / 0.045) ** 2
                      + ((centre.z - (chest_z + 0.11)) / 0.070) ** 2 < 1.0)
        ripped_right = centre.x < -0.31 and centre.y < -0.045 and polygon_index % 7 == 0
        return (torso and jagged_hem or sleeve) and not chest_hole and not ripped_right

    parts.append(make_shell(body, "Torn Shirt", mats["shirt"], 0.012, shirt_region))

    def jeans_region(centre, scores, polygon_index):
        leg = score(scores, "Hips", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R") > 0.48
        height_ok = boot_top - 0.01 < centre.z < hips_z + 0.15
        knee_hole = (centre.y < -0.035 and centre.x < 0.0
                     and ((centre.x + 0.10) / 0.07) ** 2 + ((centre.z - knee_z) / 0.075) ** 2 < 1.0)
        torn_cuff = centre.z > boot_top + 0.008 * math.sin(45.0 * centre.x + polygon_index * 0.7)
        return leg and height_ok and torn_cuff and not knee_hole

    parts.append(make_shell(body, "Torn Jeans", mats["jeans"], 0.0075, jeans_region))

    def boot_region(centre, scores, _polygon_index):
        return (score(scores, "Foot.L", "Foot.R") > 0.06
                or score(scores, "LowerLeg.L", "LowerLeg.R") > 0.30 and centre.z < boot_top + 0.040)

    parts.append(make_shell(body, "Boot Leather", mats["boots"], 0.010, boot_region))

    # Built-up work boots follow each foot bone; the underlying close shell fills any ankle gap.
    for side, bone_name in ((1, "Foot.L"), (-1, "Foot.R")):
        foot = bones[bone_name]
        parts.extend(make_work_boot(f"Work Boot {side}", foot, mats["boots"], bone_name))

    lo, hi = body_bounds(body)
    head = bones["Head"]
    head_len = (head.tail_local - head.head_local).length
    eye_z = hi.z - 0.105 * (spec["height"] / 1.78)
    eye_gap = 0.034 * (spec["height"] / 1.78)
    for side in (-1, 1):
        x = side * eye_gap
        eye_band = [vertex.co.y for vertex in body.data.vertices
                    if abs(vertex.co.z - eye_z) < 0.030 and abs(vertex.co.x - x) < 0.024]
        eye_y = min(eye_band) if eye_band else lo.y
        parts.append(ico_part(f"Socket {side}", (x, eye_y - 0.0015, eye_z),
                              (0.022, 0.004, 0.013), mats["shadow"], "Head", 2))
        parts.append(ico_part(f"Eye {side}", (x, eye_y - 0.0045, eye_z),
                              (0.009, 0.003, 0.006), mats["eyes"], "Head", 2))

    # Separate dark geometry reads as open injury after the game adds triplanar skin/cloth textures.
    def chest_wound(centre, _scores, _polygon_index):
        return (centre.y < -0.075 and ((centre.x + 0.10) / 0.060) ** 2
                + ((centre.z - (chest_z + 0.11)) / 0.090) ** 2 < 1.0)

    def cheek_wound(centre, scores, _polygon_index):
        return (score(scores, "Head") > 0.65 and centre.y < -0.08
                and ((centre.x - 0.070) / 0.040) ** 2
                + ((centre.z - (eye_z - 0.055)) / 0.052) ** 2 < 1.0)

    def knee_wound(centre, scores, _polygon_index):
        return (score(scores, "LowerLeg.R", "UpperLeg.R") > 0.60 and centre.y < -0.025
                and abs(centre.z - knee_z) < 0.075)

    parts.append(make_shell(body, "Chest Wound", mats["stain"], 0.0025, chest_wound))
    parts.append(make_shell(body, "Cheek Wound", mats["stain"], 0.0020, cheek_wound))
    parts.append(make_shell(body, "Knee Wound", mats["stain"], 0.0025, knee_wound))

    # A close scalp shell carries the silhouette; a few small clumps break the hairline.
    top = hi.z
    hair_scale = spec["height"] / 1.78
    def scalp_region(centre, scores, polygon_index):
        on_head = score(scores, "Head") > 0.68
        crown = centre.z > top - 0.13 and (centre.y > -0.105 or centre.z > top - 0.055)
        ragged_line = centre.z > top - 0.115 + 0.012 * math.sin(37.0 * centre.x + polygon_index)
        return on_head and crown and ragged_line

    parts.append(make_shell(body, "Scalp Hair", mats["hair"], 0.0045, scalp_region))
    for index, (offset, size) in enumerate((
            ((-0.045, 0.020, -0.035), (0.045, 0.055, 0.020)),
            ((0.035, 0.025, -0.032), (0.042, 0.058, 0.022)),
            ((-0.005, 0.085, -0.070), (0.070, 0.025, 0.045)),
    )):
        parts.append(ico_part(f"Hair Clump {index}",
                              (offset[0] * hair_scale, offset[1] * hair_scale,
                               top + offset[2] * hair_scale),
                              tuple(value * hair_scale for value in size), mats["hair"], "Head", 2))
    if spec["hair"] == "long":
        for side in (-1, 1):
            parts.append(ico_part(f"Long Hair {side}",
                                  (side * 0.090 * hair_scale, 0.055 * hair_scale, top - 0.19 * hair_scale),
                                  (0.045 * hair_scale, 0.050 * hair_scale, 0.16 * hair_scale),
                                  mats["hair"], "Head", 2))
        parts.append(ico_part("Long Hair Back", (0.0, 0.095 * hair_scale, top - 0.20 * hair_scale),
                              (0.110 * hair_scale, 0.038 * hair_scale, 0.17 * hair_scale),
                              mats["hair"], "Head", 2))

    if spec.get("vest"):
        def vest_region(centre, scores, _polygon_index):
            torso = score(scores, "Spine", "Chest") > 0.55 and hips_z + 0.01 < centre.z < neck_z - 0.02
            open_front = centre.y < -0.04 and abs(centre.x) < 0.055
            return torso and not open_front
        parts.append(make_shell(body, "Open Vest", mats["vest"], 0.016, vest_region))

    if spec.get("extra") == "hardhat":
        parts.extend(make_hat_dome("Hard Hat Dome", Vector((0.0, 0.005, top - 0.075)),
                                   Vector((0.145, 0.158, 0.082)), mats["hardhat"], "Head", brim=True))
    elif spec.get("extra") == "cap":
        face_y = min(vertex.co.y for vertex in body.data.vertices if vertex.co.z > top - 0.28)
        parts.extend(make_hat_dome("Cap Crown", Vector((0.0, 0.000, top - 0.058)),
                                   Vector((0.135, 0.145, 0.062)), mats["cap"], "Head", brim=False))
        parts.append(box_part("Cap Bill", (0.0, face_y - 0.045, top - 0.072),
                              (0.14, 0.09, 0.014), mats["cap"], "Head", bevel=0.006,
                              rotation=(math.radians(-7.0), 0.0, 0.0)))
    return parts


def join_and_bind(parts, armature):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    zombie = bpy.context.object
    zombie.name = "Zombie"
    zombie.data.name = "Zombie"
    for name in BONE_NAMES:
        if zombie.vertex_groups.get(name) is None:
            zombie.vertex_groups.new(name=name)
    group_names = {group.index: group.name for group in zombie.vertex_groups}
    for vertex in zombie.data.vertices:
        weighted = sorted(((item.group, item.weight) for item in vertex.groups if item.weight > 1.0e-8),
                          key=lambda item: item[1], reverse=True)
        keep = weighted[:4]
        total = sum(value for _index, value in keep)
        assert total > 1.0e-8, vertex.index
        for index, _value in weighted:
            zombie.vertex_groups[group_names[index]].remove([vertex.index])
        for index, value in keep:
            zombie.vertex_groups[group_names[index]].add([vertex.index], value / total, "REPLACE")
    zombie.data.validate(verbose=True, clean_customdata=False)
    zombie.data.calc_loop_triangles()
    triangles = len(zombie.data.loop_triangles)
    assert triangles < MAX_TRIANGLES, triangles
    materials = {mat.name for mat in zombie.data.materials if mat}
    assert materials <= APPROVED_MATERIALS, materials
    zombie.parent = armature
    zombie.matrix_parent_inverse.identity()
    modifier = zombie.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    modifier.use_bone_envelopes = False
    print("JOINED", triangles, "triangles", sorted(materials))
    return zombie


def import_ual(path, tag):
    before_objects = set(bpy.data.objects)
    before_actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects = [obj for obj in bpy.data.objects if obj not in before_objects]
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    assert len(armatures) == 1, [(obj.name, obj.type) for obj in objects]
    actions = [action for action in bpy.data.actions if action not in before_actions]
    result = {}
    for action in actions:
        original = action.name
        action.name = f"__{tag}_{original}"
        result[original] = action
    armatures[0].name = f"__{tag}_Armature"
    print("UAL", tag, "loaded", len(actions), "actions")
    return {"armature": armatures[0], "actions": result, "objects": objects}


def reset_pose(armature):
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)


def set_scene_frame(value):
    integer = math.floor(value)
    bpy.context.scene.frame_set(integer, subframe=value - integer)


def apply_retarget(source_armature, source_action, source_frame, target_armature):
    """Rest-correct a UAL pose onto the compact rig, stripping planar pelvis motion."""
    source_armature.animation_data_create()
    source_armature.animation_data.action = source_action
    set_scene_frame(source_frame)
    bpy.context.view_layer.update()
    reset_pose(target_armature)
    bpy.context.view_layer.update()
    source_by_lower = {bone.name.lower(): bone for bone in source_armature.data.bones}
    source_pose_by_lower = {bone.name.lower(): bone for bone in source_armature.pose.bones}
    source_pelvis = source_by_lower["pelvis"]
    target_pelvis = target_armature.data.bones["Hips"]
    height_scale = target_pelvis.head_local.z / max(source_pelvis.head_local.z, 1.0e-5)

    for target_name in BONE_NAMES:
        source_name = RETARGET_SOURCE[target_name].lower()
        source_bone = source_by_lower[source_name]
        source_pose = source_pose_by_lower[source_name]
        target_bone = target_armature.data.bones[target_name]
        target_pose = target_armature.pose.bones[target_name]
        source_rotation = source_pose.matrix.to_3x3().normalized()
        source_rest_rotation = source_bone.matrix_local.to_3x3().normalized()
        target_rest_rotation = target_bone.matrix_local.to_3x3().normalized()
        delta_rotation = source_rotation @ source_rest_rotation.inverted()
        desired_rotation = delta_rotation @ target_rest_rotation
        if target_name == "Hips":
            vertical = (source_pose.matrix.translation.z - source_bone.head_local.z) * height_scale
            head = target_bone.head_local + Vector((0.0, 0.0, vertical))
        else:
            parent_bone = target_bone.parent
            parent_pose = target_armature.pose.bones[parent_bone.name]
            relative_head = parent_bone.matrix_local.inverted() @ target_bone.head_local
            head = parent_pose.matrix @ relative_head
        target_pose.matrix = Matrix.Translation(head) @ desired_rotation.to_4x4()
        bpy.context.view_layer.update()
        # UAL rests in a strict T pose while MPFB's game rig rests with bent, lowered arms.
        # Applying the source delta to that A pose lowers the arms twice.  Match the posed
        # anatomical direction explicitly while retaining the target rest roll and bone length.
        source_direction = (source_pose.tail - source_pose.head).normalized()
        aim_pose_bone(target_pose, source_direction)
        bpy.context.view_layer.update()


def rotate_pose_global(pose_bone, axis, angle):
    location, rotation, scale = pose_bone.matrix.decompose()
    adjusted = Quaternion(Vector(axis), angle) @ rotation
    pose_bone.matrix = (Matrix.Translation(location) @ adjusted.to_matrix().to_4x4()
                        @ Matrix.Diagonal((*scale, 1.0)))


def aim_pose_bone(pose_bone, direction):
    location, rotation, scale = pose_bone.matrix.decompose()
    current = (rotation @ Vector((0.0, 1.0, 0.0))).normalized()
    swing = current.rotation_difference(Vector(direction).normalized())
    adjusted = swing @ rotation
    pose_bone.matrix = (Matrix.Translation(location) @ adjusted.to_matrix().to_4x4()
                        @ Matrix.Diagonal((*scale, 1.0)))


def layer_run(target_armature):
    # A small forward hunch keeps Sprint frantic without turning it into a clean athlete run.
    rotate_pose_global(target_armature.pose.bones["Chest"], (1, 0, 0), math.radians(7.0))
    rotate_pose_global(target_armature.pose.bones["UpperArm.L"], (1, 0, 0), math.radians(-8.0))
    rotate_pose_global(target_armature.pose.bones["UpperArm.R"], (1, 0, 0), math.radians(-8.0))
    bpy.context.view_layer.update()


def blend_pose_direction(target_armature, name, desired, strength):
    pose_bone = target_armature.pose.bones[name]
    current = (pose_bone.tail - pose_bone.head).normalized()
    aim_pose_bone(pose_bone, current.lerp(Vector(desired).normalized(), strength).normalized())
    bpy.context.view_layer.update()


def layer_idle(target_armature, fraction):
    """Turn UAL's crouched idle into a planted, loose-limbed zombie sway."""
    bones = target_armature.data.bones
    hips = target_armature.pose.bones["Hips"]
    sway = math.sin(fraction * math.tau)
    bob = math.sin(fraction * math.tau * 2.0)
    rest_hips = bones["Hips"].head_local
    location, rotation, scale = hips.matrix.decompose()
    location.z = rest_hips.z - 0.016 + 0.008 * bob
    location.x = rest_hips.x + 0.012 * sway
    hips.matrix = (Matrix.Translation(location) @ rotation.to_matrix().to_4x4()
                   @ Matrix.Diagonal((*scale, 1.0)))
    bpy.context.view_layer.update()
    # Straighten the source crouch but preserve enough asymmetry to look unwell, not posed.
    for name, strength in (("Hips", 0.84), ("Spine", 0.72), ("Chest", 0.70),
                           ("UpperLeg.L", 0.82), ("LowerLeg.L", 0.84),
                           ("UpperLeg.R", 0.82), ("LowerLeg.R", 0.84),
                           ("Foot.L", 0.75), ("Foot.R", 0.75)):
        rest = bones[name]
        blend_pose_direction(target_armature, name, rest.tail_local - rest.head_local, strength)
    for name, direction in (("UpperArm.L", (0.20, -0.16, -0.97)),
                            ("LowerArm.L", (0.04, -0.20, -0.98)),
                            ("Hand.L", (0.02, -0.12, -0.99)),
                            ("UpperArm.R", (-0.20, -0.16, -0.97)),
                            ("LowerArm.R", (-0.04, -0.20, -0.98)),
                            ("Hand.R", (-0.02, -0.12, -0.99))):
        blend_pose_direction(target_armature, name, direction, 0.82)
    # A little permanent hunch plus slow head lag reads clearly at distance.
    rotate_pose_global(target_armature.pose.bones["Chest"], (1, 0, 0), math.radians(7.0))
    rotate_pose_global(target_armature.pose.bones["Neck"], (0, 0, 1), math.radians(2.5) * sway)
    rotate_pose_global(target_armature.pose.bones["Head"], (0, 0, 1), -math.radians(5.0) * sway)
    bpy.context.view_layer.update()


def apply_scream(source, target_armature, fraction):
    idle = source["actions"]["Zombie_Idle_Loop"]
    start, end = idle.frame_range
    apply_retarget(source["armature"], idle, start + (end - start) * fraction, target_armature)
    layer_idle(target_armature, fraction)
    # Fast inhale, long shaking hold, then a short exhausted drop back toward idle.
    if fraction < 0.18:
        strength = fraction / 0.18
    elif fraction < 0.82:
        strength = 1.0
    else:
        strength = max(0.0, (1.0 - fraction) / 0.18)
    shake = math.sin(fraction * math.pi * 18.0) * math.radians(3.0) * strength
    rotate_pose_global(target_armature.pose.bones["Spine"], (1, 0, 0), -math.radians(10.0) * strength)
    rotate_pose_global(target_armature.pose.bones["Chest"], (1, 0, 0), -math.radians(18.0) * strength + shake)
    rotate_pose_global(target_armature.pose.bones["Neck"], (1, 0, 0), -math.radians(14.0) * strength)
    rotate_pose_global(target_armature.pose.bones["Head"], (1, 0, 0), -math.radians(30.0) * strength - shake)
    if strength > 0.001:
        left_upper = Vector((0.76, -0.55, 0.16 + math.sin(fraction * 50.0) * 0.05))
        right_upper = Vector((-0.76, -0.55, 0.16 - math.sin(fraction * 50.0) * 0.05))
        aim_pose_bone(target_armature.pose.bones["UpperArm.L"], left_upper.lerp(
            (target_armature.pose.bones["UpperArm.L"].tail - target_armature.pose.bones["UpperArm.L"].head).normalized(),
            1.0 - strength))
        aim_pose_bone(target_armature.pose.bones["UpperArm.R"], right_upper.lerp(
            (target_armature.pose.bones["UpperArm.R"].tail - target_armature.pose.bones["UpperArm.R"].head).normalized(),
            1.0 - strength))
        bpy.context.view_layer.update()
        for bone_name, desired in (("LowerArm.L", Vector((0.22, -0.76, 0.38))),
                                   ("LowerArm.R", Vector((-0.22, -0.76, 0.38)))):
            pose_bone = target_armature.pose.bones[bone_name]
            current = (pose_bone.tail - pose_bone.head).normalized()
            aim_pose_bone(pose_bone, current.lerp(desired.normalized(), strength))
    bpy.context.view_layer.update()


def apply_crawl(source, target_armature, fraction):
    action = source["actions"]["Crouch_Fwd_Loop"]
    start, end = action.frame_range
    apply_retarget(source["armature"], action, start + (end - start) * fraction, target_armature)
    hips = target_armature.pose.bones["Hips"]
    hips.location.z -= 0.34
    rotate_pose_global(hips, (1, 0, 0), math.radians(33.0))
    rotate_pose_global(target_armature.pose.bones["Spine"], (1, 0, 0), math.radians(24.0))
    rotate_pose_global(target_armature.pose.bones["Chest"], (1, 0, 0), math.radians(18.0))
    bpy.context.view_layer.update()


def source_for_clip(sources, clip):
    library, action_name = CLIP_SOURCE[clip]
    source = sources[library]
    return source, source["actions"][action_name]


def foot_travel(sources, target_armature, clip):
    source, action = source_for_clip(sources, clip)
    start, end = action.frame_range
    tracks = {"Foot.L": [], "Foot.R": []}
    for index in range(81):
        fraction = index / 80.0
        apply_retarget(source["armature"], action, start + (end - start) * fraction, target_armature)
        for name in tracks:
            tracks[name].append(target_armature.pose.bones[name].matrix.translation.y)
    spans = [max(values) - min(values) for values in tracks.values()]
    return sum(spans) / len(spans)


def key_pose(armature, frame):
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.keyframe_insert("location", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert("scale", frame=frame, group=pose_bone.name)


def bake_action(sources, target_armature, name, duration):
    action = bpy.data.actions.new(name)
    target_armature.animation_data_create()
    target_armature.animation_data.action = action
    samples = max(3, math.ceil(duration * FPS) + 1)
    if name not in {"Scream", "Crawl"}:
        source, source_action = source_for_clip(sources, name)
        source_start, source_end = source_action.frame_range
    for index in range(samples):
        fraction = index / (samples - 1)
        frame = 1.0 + fraction * duration * FPS
        pose_fraction = 0.0 if name in LOOPED and index == samples - 1 else fraction
        if name == "Scream":
            apply_scream(sources[2], target_armature, pose_fraction)
        elif name == "Crawl":
            apply_crawl(sources[1], target_armature, pose_fraction)
        else:
            source_frame = source_start + (source_end - source_start) * pose_fraction
            apply_retarget(source["armature"], source_action, source_frame, target_armature)
            if name == "Idle":
                layer_idle(target_armature, pose_fraction)
            elif name == "Run":
                layer_run(target_armature)
        key_pose(target_armature, frame)
    if hasattr(action, "use_cyclic"):
        action.use_cyclic = name in LOOPED
    for slot in action.slots:
        if not action.layers:
            continue
        bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
        if bag:
            for curve in bag.fcurves:
                for point in curve.keyframe_points:
                    point.interpolation = "LINEAR"
    return action


def action_fcurves(action):
    curves = []
    for slot in action.slots:
        if not action.layers:
            continue
        bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
        if bag:
            curves.extend(bag.fcurves)
    return curves


def baked_foot_speed(armature, action):
    start, end = action.frame_range
    tracks = {"Foot.L": [], "Foot.R": []}
    for index in range(181):
        armature.animation_data.action = action
        set_scene_frame(start + (end - start) * index / 180.0)
        bpy.context.view_layer.update()
        for name in tracks:
            tracks[name].append(armature.pose.bones[name].matrix.translation.y)
    travel = sum(max(values) - min(values) for values in tracks.values()) / len(tracks)
    return 2.0 * travel / ((end - start) / FPS)


def retime_to_speed(armature, action, target_speed):
    measured = baked_foot_speed(armature, action)
    factor = measured / target_speed
    start = action.frame_range[0]
    for curve in action_fcurves(action):
        for point in curve.keyframe_points:
            point.co.x = start + (point.co.x - start) * factor
            point.handle_left.x = start + (point.handle_left.x - start) * factor
            point.handle_right.x = start + (point.handle_right.x - start) * factor
    bpy.context.view_layer.update()
    corrected = baked_foot_speed(armature, action)
    print("RETIME", action.name, f"{measured:.5f}", "->", f"{corrected:.5f}")


def build_animations(armature):
    sources = {
        1: import_ual(UAL1, "UAL1"),
        2: import_ual(UAL2, "UAL2"),
    }
    walk_travel = foot_travel(sources, armature, "Walk")
    run_travel = foot_travel(sources, armature, "Run")
    durations = {
        "Idle": 32.0 / SOURCE_FPS,
        "Walk": 2.0 * walk_travel / 1.0,
        "Run": 2.0 * run_travel / 3.45,
        "Punch": 43.2 / SOURCE_FPS,
        "Crawl": 1.20,
        "Death": 57.6 / SOURCE_FPS,
        "HitReact": 8.0 / SOURCE_FPS,
        "Scream": 1.50,
    }
    actions = {name: bake_action(sources, armature, name, durations[name]) for name in ACTION_NAMES}
    retime_to_speed(armature, actions["Walk"], 1.0)
    retime_to_speed(armature, actions["Run"], 3.45)
    durations["Walk"] = (actions["Walk"].frame_range[1] - actions["Walk"].frame_range[0]) / FPS
    durations["Run"] = (actions["Run"].frame_range[1] - actions["Run"].frame_range[0]) / FPS
    armature.animation_data.action = None
    reset_pose(armature)
    bpy.context.scene.frame_set(0)
    # Remove source geometry, rigs, and the many unused source actions before ACTIONS export.
    source_action_set = {action for source in sources.values() for action in source["actions"].values()}
    for source in sources.values():
        for obj in source["objects"]:
            if obj.name in bpy.data.objects:
                bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(source_action_set):
        if action.name in bpy.data.actions:
            bpy.data.actions.remove(action)
    print("CLIP_DURATIONS", {name: round(value, 4) for name, value in durations.items()})
    print("FOOT_TRAVEL", round(walk_travel, 5), round(run_travel, 5))
    return actions, durations


def output_path(variant):
    name = "zombie.glb" if variant == "default" else f"zombie_{variant}.glb"
    return MODEL_DIR / name


def export_glb(variant, zombie, armature):
    path = output_path(variant)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    zombie.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="EXPORT",
        export_cameras=False, export_lights=False, export_skins=True,
        export_animations=True, export_animation_mode="ACTIONS",
        export_bake_animation=True, export_force_sampling=False,
        export_frame_range=True,
    )
    print("EXPORTED", path)
    return path


def evaluated_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in data.vertices]
    evaluated.to_mesh_clear()
    return points


def action_pose_matrices(armature, action, frame):
    armature.animation_data.action = action
    set_scene_frame(frame)
    bpy.context.view_layer.update()
    return {bone.name: bone.matrix.copy() for bone in armature.pose.bones}


def seam_error(armature, action):
    start, end = action.frame_range
    first = action_pose_matrices(armature, action, start)
    last = action_pose_matrices(armature, action, end)
    return max(abs(first[name][row][column] - last[name][row][column])
               for name in first for row in range(4) for column in range(4))


def measured_speed(armature, action):
    start, end = action.frame_range
    tracks = {"Foot.L": [], "Foot.R": []}
    for index in range(121):
        frame = start + (end - start) * index / 120.0
        armature.animation_data.action = action
        set_scene_frame(frame)
        bpy.context.view_layer.update()
        for name in tracks:
            tracks[name].append(armature.pose.bones[name].matrix.translation.y)
    travel = sum(max(values) - min(values) for values in tracks.values()) / len(tracks)
    duration = (end - start) / FPS
    return 2.0 * travel / duration


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Zombie Preview World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.011, 0.009, 1.0)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.08
    camera_data = bpy.data.cameras.new("Preview Camera")
    camera_data.lens = 58
    camera = bpy.data.objects.new("Preview Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    for name, location, energy, color, size in (
            ("Cold Key", (-1.9, -2.6, 3.2), 430.0, (0.64, 0.78, 1.0), 2.2),
            ("Sick Fill", (2.1, -1.1, 1.5), 180.0, (0.62, 1.0, 0.70), 1.7),
            ("Rim", (0.7, 2.0, 2.7), 520.0, (1.0, 0.46, 0.30), 1.2),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, (0.0, 0.0, 0.95))
    ground_mat = bpy.data.materials.new("Preview Ground")
    ground_mat.diffuse_color = (0.018, 0.022, 0.019, 1.0)
    ground_mat.use_nodes = True
    bsdf = ground_mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = ground_mat.diffuse_color
    bsdf.inputs["Roughness"].default_value = 0.94
    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.0, 0.0, -0.006))
    bpy.context.object.data.materials.append(ground_mat)
    return camera


def render_still(path):
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)


def image_array(path):
    import numpy as np
    image = bpy.data.images.load(str(path), check_existing=False)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((height, width, 4))
    bpy.data.images.remove(image)
    return pixels


def save_array(path, pixels, name):
    height, width, _channels = pixels.shape
    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def half_size(pixels):
    height, width, channels = pixels.shape
    return pixels.reshape(height // 2, 2, width // 2, 2, channels).mean(axis=(1, 3))


def render_previews(variant, armature, actions):
    import numpy as np
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    FRAME_DIR.mkdir(parents=True, exist_ok=True)
    camera = setup_preview()
    idle = actions["Idle"]
    armature.animation_data.action = idle
    set_scene_frame(idle.frame_range[0] + (idle.frame_range[1] - idle.frame_range[0]) * 0.28)
    bpy.context.view_layer.update()
    target = (0.0, 0.0, 0.88)
    camera.location = (0.0, -3.25, 1.02)
    look_at(camera, target)
    render_still(SHOT_DIR / f"zombie_mh_{variant}_front.png")
    camera.location = (2.15, -2.75, 1.12)
    look_at(camera, target)
    render_still(SHOT_DIR / f"zombie_mh_{variant}_three_quarter.png")

    if variant != "default":
        return
    camera.location = (0.0, -3.35, 1.03)
    look_at(camera, target)
    for clip in ("Walk", "Run", "Punch", "Death", "HitReact", "Scream"):
        action = actions[clip]
        armature.animation_data.action = action
        frames = []
        for index, fraction in enumerate((0.0, 0.25, 0.50, 0.75, 1.0)):
            set_scene_frame(action.frame_range[0] + (action.frame_range[1] - action.frame_range[0]) * fraction)
            bpy.context.view_layer.update()
            frame_path = FRAME_DIR / f"{clip.lower()}_{index}.png"
            render_still(frame_path)
            frames.append(half_size(image_array(frame_path)))
        strip = np.concatenate(frames, axis=1)
        strip_path = SHOT_DIR / f"zombie_mh_{clip.lower()}_strip.png"
        save_array(strip_path, strip, f"{clip} strip")
        print("STRIP", strip_path)


def make_contact_sheet():
    import numpy as np
    stand_paths = []
    for variant in VARIANTS:
        stand_paths.extend((SHOT_DIR / f"zombie_mh_{variant}_front.png",
                            SHOT_DIR / f"zombie_mh_{variant}_three_quarter.png"))
    missing = [path for path in stand_paths if not path.exists()]
    strip_paths = [SHOT_DIR / f"zombie_mh_{clip.lower()}_strip.png"
                   for clip in ("Walk", "Run", "Punch", "Death", "HitReact", "Scream")]
    missing.extend(path for path in strip_paths if not path.exists())
    if missing:
        print("CONTACT_SHEET skipped; missing", [str(path) for path in missing])
        return
    standing = [half_size(image_array(path)) for path in stand_paths]
    blank = np.zeros((512, 2560, 4), dtype=np.float32)
    blank[:, :, 3] = 1.0
    rows = []
    for start in (0, 5):
        row = blank.copy()
        for column, pixels in enumerate(standing[start:start + 5]):
            row[:, column * 512:(column + 1) * 512] = pixels
        rows.append(row)
    rows.extend(image_array(path) for path in strip_paths)
    sheet = np.concatenate(rows, axis=0)
    path = SHOT_DIR / "zombie_mh_sheet.png"
    save_array(path, sheet, "Zombie MPFB contact sheet")
    print("CONTACT_SHEET", path)


def validate_reimport(variant, path, render=True):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"
              and not any(collection.name == "glTF_not_exported" for collection in obj.users_collection)]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert len(meshes) == 1 and len(armatures) == 1, (meshes, armatures)
    zombie, armature = meshes[0], armatures[0]
    assert zombie.name == "Zombie" and armature.name == "Armature"
    assert zombie.parent == armature
    assert tuple(armature.data.bones.keys()) == BONE_NAMES, tuple(armature.data.bones.keys())
    materials = sorted(mat.name for mat in zombie.data.materials if mat)
    assert set(materials) <= APPROVED_MATERIALS, materials
    zombie.data.calc_loop_triangles()
    triangles = len(zombie.data.loop_triangles)
    assert triangles < MAX_TRIANGLES, triangles
    actions = {action.name: action for action in bpy.data.actions}
    assert set(actions) == set(ACTION_NAMES), sorted(actions)
    armature.animation_data_create()
    armature.animation_data.action = None
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    points = evaluated_points(zombie)
    lo = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    hi = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    assert abs(lo.z) < 0.03, lo
    assert 1.50 < hi.z - lo.z < 1.95, (lo, hi)
    head = armature.data.bones["Head"]
    head_base = head.head_local.z
    head_height = (head.head_local.z + head.tail_local.z) * 0.5
    armature.data.pose_position = "POSE"
    lengths = {name: (actions[name].frame_range[1] - actions[name].frame_range[0]) / FPS
               for name in ACTION_NAMES}
    seams = {name: seam_error(armature, actions[name]) for name in LOOPED}
    assert max(seams.values()) < 0.002, seams
    walk_speed = measured_speed(armature, actions["Walk"])
    run_speed = measured_speed(armature, actions["Run"])
    assert abs(walk_speed - 1.0) < 0.025, walk_speed
    assert abs(run_speed - 3.45) < 0.06, run_speed
    print("VALIDATION", variant)
    print("  bounds", f"({lo.x:.4f},{lo.y:.4f},{lo.z:.4f})..({hi.x:.4f},{hi.y:.4f},{hi.z:.4f})")
    print("  triangles", triangles)
    print("  materials", materials)
    print("  bone_count", len(armature.data.bones), "bones", list(armature.data.bones.keys()))
    print("  animations", {name: {"seconds": round(lengths[name], 4), "loop": name in LOOPED}
                            for name in ACTION_NAMES})
    print("  seamless_loop_error", {name: round(value, 7) for name, value in seams.items()})
    print("  foot_speed", {"Walk": round(walk_speed, 4), "Run": round(run_speed, 4)})
    print("  head", {"base": round(head_base, 4), "centre": round(head_height, 4)})
    if render:
        render_previews(variant, armature, actions)
    return {
        "variant": variant, "bounds": (lo, hi), "triangles": triangles,
        "materials": materials, "bones": len(armature.data.bones), "lengths": lengths,
        "walk_speed": walk_speed, "run_speed": run_speed, "head_base": head_base,
        "head_height": head_height,
    }


def build_variant(variant):
    spec = VARIANTS[variant]
    clean_scene(remove_actions=True)
    # kit.material caches datablock handles; validation deliberately replaces the .blend state.
    material.__globals__["_materials"].clear()
    bpy.context.scene.render.fps = FPS
    mats = build_materials(spec)
    HumanService = enable_mpfb()
    macro = {**spec["macro"], "race": {"asian": 0.33, "caucasian": 0.34, "african": 0.33}}
    human = HumanService.create_human(
        mask_helpers=False, detailed_helpers=False, extra_vertex_groups=False,
        feet_on_ground=False, scale=0.1, macro_detail_dict=macro,
    )
    source_armature = HumanService.add_builtin_rig(human, "game_engine", import_weights=True)
    assert source_armature is not None
    body, armature, _scale = build_body(human, source_armature, spec["height"], mats["skin"])
    width = float(spec.get("width", 1.0))
    if abs(width - 1.0) > 1.0e-6:
        for vertex in body.data.vertices:
            vertex.co.x *= width
        bpy.context.view_layer.objects.active = armature
        armature.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        for bone in armature.data.edit_bones:
            bone.head.x *= width
            bone.tail.x *= width
        bpy.ops.object.mode_set(mode="OBJECT")
        bpy.context.view_layer.update()
    parts = add_clothing_and_details(body, armature, spec, mats)
    zombie = join_and_bind(parts, armature)
    # MPFB is finished before UAL import/baking; remove its source objects and handlers.
    bpy.data.objects.remove(human, do_unlink=True)
    bpy.data.objects.remove(source_armature, do_unlink=True)
    addon_utils.disable("bl_ext.blender_org.mpfb", default_set=False)
    build_animations(armature)
    path = export_glb(variant, zombie, armature)
    return validate_reimport(variant, path, render=True)


def main():
    assert UAL1.is_file() and UAL2.is_file(), f"UAL sources not found under {UAL_DIR}"
    requested = _arg("variant", "all")
    assert requested == "all" or requested in VARIANTS, f"unknown variant {requested!r}"
    variants = list(VARIANTS) if requested == "all" else [requested]
    results = []
    for variant in variants:
        print("BUILD_VARIANT", variant)
        results.append(build_variant(variant))
    if requested == "all":
        make_contact_sheet()
    print("VALIDATION_SUMMARY")
    for result in results:
        lo, hi = result["bounds"]
        print(" ", result["variant"],
              f"bounds=({lo.x:.3f},{lo.y:.3f},{lo.z:.3f})..({hi.x:.3f},{hi.y:.3f},{hi.z:.3f})",
              f"triangles={result['triangles']}", f"bones={result['bones']}",
              f"walk={result['walk_speed']:.3f}", f"run={result['run_speed']:.3f}",
              f"head={result['head_height']:.3f}")


if __name__ == "__main__":
    main()
