"""Build and export Noise Floor's rigid-skinned low-poly zombie.

Run with Blender 5.1:
    blender.exe -b --factory-startup --python tools/art/zombie.py

Unlike the static prop scripts, this deliberately does not use kit.finish().
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kit import box, cylinder, material, reset  # noqa: E402


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "zombie.glb"
FPS = 30
EXPECTED_ACTIONS = ("Idle", "Walk", "Punch", "HitReact", "Death")


def deg(value):
    return math.radians(value)


def cone(name, radius1, radius2, depth, location, mat, vertices=10, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def ico(name, radius, location, scale, mat, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def segment(name, start, end, r1, r2, mat, vertices=10):
    """Create a tapered faceted segment whose local Z follows start -> end."""
    a, b = Vector(start), Vector(end)
    direction = b - a
    obj = cone(name, r1, r2, direction.length, (a + b) * 0.5, mat, vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.rotation_mode = "XYZ"
    return obj


def weighted(obj, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


def build_materials():
    # Muted values keep the silhouette believable in the town's overcast lighting.
    return {
        "skin": material("Zombie Skin", (0.28, 0.31, 0.25), 0.0, 0.90),
        "shirt": material("Shirt", (0.43, 0.44, 0.42), 0.0, 0.91),
        "jeans": material("Jeans", (0.12, 0.16, 0.19), 0.0, 0.94),
        "boots": material("Boots", (0.055, 0.045, 0.038), 0.0, 0.88),
        "hair": material("Hair", (0.035, 0.030, 0.027), 0.0, 0.96),
        "eyes": material("Eyes", (0.10, 0.012, 0.006), 0.0, 0.82),
        "stain": material("Stain", (0.065, 0.010, 0.008), 0.0, 0.93),
    }


BONES = {
    "Hips": ((0.00, 0.00, 0.88), (0.00, 0.00, 1.00), None),
    "Spine": ((0.00, 0.00, 0.98), (0.00, 0.00, 1.22), "Hips"),
    "Chest": ((0.00, 0.00, 1.20), (0.00, -0.025, 1.43), "Spine"),
    "Neck": ((0.00, -0.025, 1.42), (0.00, -0.045, 1.52), "Chest"),
    "Head": ((0.00, -0.045, 1.50), (0.00, -0.075, 1.72), "Neck"),
    "UpperArm.L": ((-0.215, -0.015, 1.38), (-0.245, -0.18, 1.14), "Chest"),
    "LowerArm.L": ((-0.245, -0.18, 1.14), (-0.225, -0.405, 0.98), "UpperArm.L"),
    "Hand.L": ((-0.225, -0.405, 0.98), (-0.215, -0.535, 0.91), "LowerArm.L"),
    "UpperArm.R": ((0.215, -0.010, 1.32), (0.250, -0.17, 1.08), "Chest"),
    "LowerArm.R": ((0.250, -0.17, 1.08), (0.230, -0.420, 0.94), "UpperArm.R"),
    "Hand.R": ((0.230, -0.420, 0.94), (0.220, -0.555, 0.88), "LowerArm.R"),
    "UpperLeg.L": ((-0.105, 0.00, 0.93), (-0.105, 0.015, 0.56), "Hips"),
    "LowerLeg.L": ((-0.105, 0.015, 0.56), (-0.105, -0.005, 0.14), "UpperLeg.L"),
    "Foot.L": ((-0.105, -0.005, 0.14), (-0.105, -0.18, 0.07), "LowerLeg.L"),
    "UpperLeg.R": ((0.105, 0.00, 0.93), (0.105, -0.01, 0.56), "Hips"),
    "LowerLeg.R": ((0.105, -0.01, 0.56), (0.105, 0.010, 0.14), "UpperLeg.R"),
    "Foot.R": ((0.105, 0.010, 0.14), (0.105, -0.17, 0.07), "LowerLeg.R"),
}


def build_armature():
    data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = {}
    for name, (head, tail, _parent) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = True
        edit[name] = bone
    for name, (_head, _tail, parent) in BONES.items():
        if parent:
            edit[name].parent = edit[parent]
            edit[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.show_in_front = True
    return arm


def build_character(m):
    parts = []

    def add(obj, bone):
        parts.append(weighted(obj, bone))
        return obj

    # Worn boots and square toes, feet exactly on Z=0.
    for side, x in (("L", -0.105), ("R", 0.105)):
        add(box(f"Boot_{side}", (0.17, 0.31, 0.135), (x, -0.095, 0.0675), m["boots"], 0.018), f"Foot.{side}")
        add(box(f"BootToe_{side}", (0.175, 0.17, 0.095), (x, -0.225, 0.050), m["boots"], 0.022), f"Foot.{side}")
        add(box(f"BootCuff_{side}", (0.18, 0.15, 0.105), (x, -0.01, 0.145), m["boots"], 0.015), f"LowerLeg.{side}")

    # Jeans are uneven and slightly loose, with angular knee masses and faded patches.
    add(segment("Shin_L", (-0.105, 0.005, 0.15), (-0.105, 0.015, 0.55), 0.086, 0.095, m["jeans"], 10), "LowerLeg.L")
    add(segment("Shin_R", (0.105, 0.010, 0.15), (0.105, -0.01, 0.55), 0.086, 0.096, m["jeans"], 10), "LowerLeg.R")
    add(ico("Knee_L", 1, (-0.105, 0.005, 0.565), (0.098, 0.087, 0.105), m["jeans"], 2), "UpperLeg.L")
    add(ico("Knee_R", 1, (0.105, -0.010, 0.565), (0.098, 0.087, 0.105), m["jeans"], 2), "UpperLeg.R")
    add(segment("Thigh_L", (-0.105, 0.008, 0.58), (-0.105, 0.00, 0.94), 0.115, 0.135, m["jeans"], 10), "UpperLeg.L")
    add(segment("Thigh_R", (0.105, -0.006, 0.58), (0.105, 0.00, 0.94), 0.115, 0.135, m["jeans"], 10), "UpperLeg.R")
    add(box("Left_Knee_Fade", (0.115, 0.012, 0.115), (-0.105, -0.087, 0.57), m["shirt"], 0.008), "UpperLeg.L")
    add(box("Right_Jeans_Tear", (0.095, 0.014, 0.055), (0.105, -0.090, 0.49), m["skin"], 0.006, rotation=(0, 0, deg(-8))), "LowerLeg.R")

    # Pelvis, shirt body, collar and an untucked, torn hem.
    add(box("Pelvis", (0.315, 0.215, 0.22), (0.0, 0.0, 0.94), m["jeans"], 0.035), "Hips")
    add(box("ShirtWaist", (0.385, 0.235, 0.27), (0.0, -0.008, 1.085), m["shirt"], 0.035, rotation=(deg(2), 0, deg(-1))), "Spine")
    add(box("ShirtChest", (0.455, 0.255, 0.285), (0.0, -0.025, 1.315), m["shirt"], 0.042, rotation=(deg(4), 0, deg(-1))), "Chest")
    add(box("Hem_Left", (0.18, 0.235, 0.12), (-0.095, -0.012, 0.965), m["shirt"], 0.018, rotation=(deg(-2), deg(3), deg(-4))), "Spine")
    add(box("Hem_Right", (0.15, 0.235, 0.16), (0.105, -0.014, 0.945), m["shirt"], 0.018, rotation=(deg(3), deg(-2), deg(5))), "Spine")
    add(box("Open_Collar", (0.12, 0.018, 0.10), (0.0, -0.158, 1.405), m["skin"], 0.008, rotation=(deg(-6), 0, 0)), "Chest")
    add(box("Chest_Stain", (0.090, 0.014, 0.105), (-0.095, -0.164, 1.30), m["stain"], 0.009, rotation=(deg(-3), 0, deg(-14))), "Chest")
    add(box("Chest_Stain_Smear", (0.050, 0.015, 0.060), (-0.142, -0.164, 1.245), m["stain"], 0.007, rotation=(deg(-3), 0, deg(11))), "Chest")
    add(box("Hem_Stain", (0.105, 0.014, 0.07), (0.12, -0.143, 0.97), m["stain"], 0.007, rotation=(deg(-2), 0, deg(8))), "Spine")
    add(box("Pocket", (0.105, 0.018, 0.10), (0.105, -0.163, 1.34), m["shirt"], 0.009, rotation=(deg(-4), 0, deg(2))), "Chest")

    # One shoulder hangs lower. Sleeves stop above exposed, sickly forearms.
    add(ico("Shoulder_L", 1, (-0.215, -0.02, 1.375), (0.070, 0.105, 0.105), m["shirt"], 2), "UpperArm.L")
    add(ico("Shoulder_R", 1, (0.215, -0.015, 1.315), (0.070, 0.105, 0.105), m["shirt"], 2), "UpperArm.R")
    add(segment("Sleeve_L", (-0.215, -0.02, 1.37), (-0.242, -0.13, 1.21), 0.075, 0.068, m["shirt"], 10), "UpperArm.L")
    add(segment("Sleeve_R", (0.215, -0.015, 1.31), (0.245, -0.125, 1.15), 0.075, 0.068, m["shirt"], 10), "UpperArm.R")
    add(segment("UpperArmSkin_L", (-0.242, -0.13, 1.21), (-0.245, -0.18, 1.14), 0.061, 0.060, m["skin"], 9), "UpperArm.L")
    add(segment("UpperArmSkin_R", (0.245, -0.125, 1.15), (0.250, -0.17, 1.08), 0.061, 0.060, m["skin"], 9), "UpperArm.R")
    add(ico("Elbow_L", 1, (-0.245, -0.18, 1.14), (0.066, 0.066, 0.070), m["skin"], 1), "LowerArm.L")
    add(ico("Elbow_R", 1, (0.250, -0.17, 1.08), (0.066, 0.066, 0.070), m["skin"], 1), "LowerArm.R")
    add(segment("Forearm_L", (-0.245, -0.18, 1.14), (-0.225, -0.405, 0.98), 0.063, 0.050, m["skin"], 9), "LowerArm.L")
    add(segment("Forearm_R", (0.250, -0.17, 1.08), (0.230, -0.420, 0.94), 0.063, 0.050, m["skin"], 9), "LowerArm.R")
    add(box("Sleeve_Stain", (0.07, 0.014, 0.095), (-0.248, -0.145, 1.19), m["stain"], 0.006, rotation=(deg(28), 0, 0)), "UpperArm.L")

    # Blocky hands with short separated fingers, restrained rather than claw-like.
    for side, x, y, z in (("L", -0.215, -0.485, 0.94), ("R", 0.220, -0.500, 0.905)):
        bone = f"Hand.{side}"
        add(box(f"Palm_{side}", (0.105, 0.145, 0.075), (x, y, z), m["skin"], 0.018, rotation=(deg(10), 0, 0)), bone)
        for index, dx in enumerate((-0.034, 0.0, 0.034)):
            add(box(f"Finger_{side}_{index}", (0.025, 0.105, 0.025), (x + dx, y - 0.105, z - 0.005 - abs(dx) * 0.3), m["skin"], 0.008, rotation=(deg(8 + index * 3), 0, 0)), bone)

    # Neck and human-sized head (roughly 1/7.5 total height), pitched slightly forward.
    add(cylinder("Neck", 0.078, 0.13, (0.0, -0.035, 1.475), m["skin"], 10, rotation=(deg(8), 0, 0), bevel=0.008), "Neck")
    add(ico("Skull", 1, (0.0, -0.067, 1.640), (0.168, 0.145, 0.140), m["skin"], 2), "Head")
    add(box("Jaw", (0.245, 0.205, 0.115), (0.0, -0.086, 1.558), m["skin"], 0.028, rotation=(deg(2), 0, deg(-2))), "Head")
    add(box("Nose", (0.055, 0.075, 0.075), (-0.005, -0.217, 1.635), m["skin"], 0.012, rotation=(deg(7), 0, deg(-3))), "Head")
    add(ico("Ear_L", 1, (-0.166, -0.055, 1.65), (0.030, 0.023, 0.050), m["skin"], 1), "Head")
    add(ico("Ear_R", 1, (0.166, -0.055, 1.64), (0.030, 0.023, 0.050), m["skin"], 1), "Head")
    # Narrow shadowed sockets and tiny dull red points avoid cartoon eyes.
    for side, x, z in (("L", -0.061, 1.675), ("R", 0.061, 1.666)):
        add(box(f"Socket_{side}", (0.072, 0.016, 0.045), (x, -0.205, z), m["hair"], 0.010, rotation=(deg(-5), 0, deg(-3 if side == "L" else 4))), "Head")
        add(ico(f"Eye_{side}", 1, (x, -0.216, z), (0.012, 0.008, 0.010), m["eyes"], 1), "Head")
    add(box("Mouth_Shadow", (0.115, 0.014, 0.023), (0.008, -0.195, 1.575), m["hair"], 0.005, rotation=(deg(3), 0, deg(-5))), "Head")
    add(box("Cheek_Stain", (0.052, 0.012, 0.062), (0.105, -0.191, 1.60), m["stain"], 0.006, rotation=(deg(4), 0, deg(-18))), "Head")

    # Asymmetric low-poly hair clumps, all dark and close to the skull.
    add(box("Hair_Crown", (0.205, 0.210, 0.060), (-0.025, -0.035, 1.750), m["hair"], 0.018, rotation=(deg(-3), deg(2), deg(-5))), "Head")
    add(box("Hair_Tuft", (0.085, 0.135, 0.060), (0.080, -0.085, 1.755), m["hair"], 0.015, rotation=(deg(11), deg(-8), deg(13))), "Head")
    add(box("Hair_Left", (0.095, 0.195, 0.11), (-0.125, -0.030, 1.715), m["hair"], 0.018, rotation=(deg(4), deg(-6), deg(-8))), "Head")
    add(box("Hair_Right", (0.075, 0.18, 0.095), (0.130, -0.020, 1.720), m["hair"], 0.016, rotation=(deg(-5), deg(8), deg(10))), "Head")
    add(box("Hair_Back", (0.245, 0.050, 0.125), (0.0, 0.065, 1.685), m["hair"], 0.014, rotation=(deg(-4), 0, deg(2))), "Head")

    # Join while preserving the deliberately one-bone-per-part vertex groups.
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    zombie = bpy.context.object
    zombie.name = "Zombie"
    zombie.data.name = "Zombie"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in zombie.data.polygons:
        poly.use_smooth = False
    return zombie


def bind(zombie, armature):
    zombie.parent = armature
    zombie.matrix_parent_inverse.identity()
    mod = zombie.modifiers.new("Armature", "ARMATURE")
    mod.object = armature
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False
    assert set(zombie.vertex_groups.keys()) == set(BONES.keys())
    for vertex in zombie.data.vertices:
        assert len(vertex.groups) == 1 and abs(vertex.groups[0].weight - 1.0) < 1e-6


def reset_pose(armature):
    for pb in armature.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def make_action(armature, name, keyed_poses):
    action = bpy.data.actions.new(name)
    armature.animation_data.action = action
    for frame, pose in keyed_poses:
        bpy.context.scene.frame_set(frame)
        reset_pose(armature)
        for bone_name, values in pose.items():
            pb = armature.pose.bones[bone_name]
            if "rot" in values:
                pb.rotation_euler = tuple(deg(v) for v in values["rot"])
            if "loc" in values:
                pb.location = values["loc"]
        for pb in armature.pose.bones:
            pb.keyframe_insert("location", frame=frame, group=pb.name)
            pb.keyframe_insert("rotation_euler", frame=frame, group=pb.name)
            pb.keyframe_insert("scale", frame=frame, group=pb.name)
    # Linear keys keep the angular, machine-family aesthetic and predictable loops.
    for slot in action.slots:
        bag = action.layers[0].strips[0].channelbag(slot, ensure=False)
        if bag:
            for fcurve in bag.fcurves:
                for point in fcurve.keyframe_points:
                    point.interpolation = "LINEAR"
    return action


def build_animations(armature):
    armature.animation_data_create()
    idle_a = {
        "Hips": {"rot": (2, 0, -2)}, "Spine": {"rot": (5, 0, 2)}, "Chest": {"rot": (6, 0, -2)},
        "Neck": {"rot": (7, 0, 3)}, "Head": {"rot": (6, -3, -5)},
        "UpperArm.L": {"rot": (4, 0, -3)}, "UpperArm.R": {"rot": (-3, 0, 3)},
    }
    idle_b = {
        "Hips": {"rot": (2, 0, 2), "loc": (0, 0.008, 0)}, "Spine": {"rot": (4, 0, -3)}, "Chest": {"rot": (7, 0, 3)},
        "Neck": {"rot": (4, 2, -4)}, "Head": {"rot": (9, 4, 5)},
        "UpperArm.L": {"rot": (-2, 0, 4)}, "LowerArm.L": {"rot": (2, 0, -2)},
        "UpperArm.R": {"rot": (3, 0, -4)}, "LowerArm.R": {"rot": (-2, 0, 2)},
    }
    make_action(armature, "Idle", [(1, idle_a), (20, idle_b), (39, idle_a), (58, idle_b), (76, idle_a)])

    walk_1 = {
        "Hips": {"rot": (3, 0, -4), "loc": (0, -0.015, 0)}, "Spine": {"rot": (7, 0, 5)}, "Chest": {"rot": (8, 0, -4)},
        "Head": {"rot": (4, 2, 4)}, "UpperLeg.L": {"rot": (-40, 0, 1)}, "LowerLeg.L": {"rot": (17, 0, 0)},
        "UpperLeg.R": {"rot": (34, 0, -1)}, "LowerLeg.R": {"rot": (-3, 0, 0)},
        "UpperArm.L": {"rot": (7, 0, -5)}, "LowerArm.L": {"rot": (-4, 0, 3)},
        "UpperArm.R": {"rot": (-5, 0, 4)}, "LowerArm.R": {"rot": (3, 0, -2)},
    }
    walk_2 = {
        "Hips": {"rot": (2, 0, 4), "loc": (0, 0.012, 0)}, "Spine": {"rot": (8, 0, -5)}, "Chest": {"rot": (7, 0, 4)},
        "Head": {"rot": (8, -2, -5)}, "UpperLeg.L": {"rot": (38, 0, 1)}, "LowerLeg.L": {"rot": (-2, 0, 0)},
        "UpperLeg.R": {"rot": (-30, 0, -1)}, "LowerLeg.R": {"rot": (8, 0, 0)},
        "UpperArm.L": {"rot": (-5, 0, 5)}, "LowerArm.L": {"rot": (3, 0, -2)},
        "UpperArm.R": {"rot": (7, 0, -4)}, "LowerArm.R": {"rot": (-4, 0, 3)},
    }
    make_action(armature, "Walk", [(1, walk_1), (11, {}), (21, walk_2), (31, {}), (40, walk_1)])

    punch_ready = {"Hips": {"rot": (3, 0, -2)}, "Spine": {"rot": (7, 0, 2)}, "Chest": {"rot": (8, 0, -2)}, "Head": {"rot": (6, 0, 3)}}
    punch_back = {
        "Hips": {"rot": (-3, 0, 5)}, "Spine": {"rot": (0, 0, -7)}, "Chest": {"rot": (1, 0, 7)},
        "UpperArm.L": {"rot": (-24, -4, 8)}, "LowerArm.L": {"rot": (-18, 0, 4)},
        "UpperArm.R": {"rot": (-18, 5, -9)}, "LowerArm.R": {"rot": (-13, 0, -3)},
    }
    punch_hit = {
        "Hips": {"rot": (11, 0, -4), "loc": (0, -0.02, 0.055)}, "Spine": {"rot": (17, 0, 5)}, "Chest": {"rot": (18, 0, -4)},
        "Neck": {"rot": (-6, 0, 0)}, "Head": {"rot": (-10, 4, 5)},
        "UpperArm.L": {"rot": (32, -7, -13)}, "LowerArm.L": {"rot": (30, 0, -9)}, "Hand.L": {"rot": (17, 0, 8)},
        "UpperArm.R": {"rot": (38, 8, 11)}, "LowerArm.R": {"rot": (27, 0, 8)}, "Hand.R": {"rot": (14, 0, -7)},
    }
    make_action(armature, "Punch", [(1, punch_ready), (8, punch_back), (17, punch_hit), (24, punch_hit), (34, punch_ready)])

    hit_rest = {"Hips": {"rot": (2, 0, 0)}, "Spine": {"rot": (6, 0, 0)}, "Chest": {"rot": (7, 0, 0)}, "Head": {"rot": (7, 0, 0)}}
    hit_back = {
        "Hips": {"rot": (-12, 0, 3), "loc": (0, 0.015, -0.045)}, "Spine": {"rot": (-22, 0, -5)}, "Chest": {"rot": (-18, 0, 5)},
        "Neck": {"rot": (18, 0, 0)}, "Head": {"rot": (27, -5, -7)},
        "UpperArm.L": {"rot": (-28, 0, -18)}, "LowerArm.L": {"rot": (-16, 0, 8)},
        "UpperArm.R": {"rot": (-31, 0, 18)}, "LowerArm.R": {"rot": (-12, 0, -8)},
    }
    make_action(armature, "HitReact", [(1, hit_rest), (6, hit_back), (10, hit_back), (15, hit_rest)])

    death_start = {"Hips": {"rot": (2, 0, 0)}, "Spine": {"rot": (7, 0, 0)}, "Chest": {"rot": (8, 0, 0)}, "Head": {"rot": (7, 0, 0)}}
    death_knees = {
        "Hips": {"rot": (12, 0, 5), "loc": (0, -0.22, 0.05)}, "Spine": {"rot": (20, 0, -8)}, "Chest": {"rot": (18, 0, 6)},
        "UpperLeg.L": {"rot": (-27, 0, -4)}, "LowerLeg.L": {"rot": (54, 0, 0)},
        "UpperLeg.R": {"rot": (-18, 0, 5)}, "LowerLeg.R": {"rot": (48, 0, 0)},
        "UpperArm.L": {"rot": (22, 0, -20)}, "UpperArm.R": {"rot": (18, 0, 22)},
    }
    death_fall = {
        "Hips": {"rot": (58, 0, 7), "loc": (0, -0.38, 0.20)}, "Spine": {"rot": (18, 0, -5)}, "Chest": {"rot": (14, 0, 4)},
        "Neck": {"rot": (-12, 0, 0)}, "Head": {"rot": (-16, 5, -7)},
        "UpperLeg.L": {"rot": (-20, 0, -3)}, "LowerLeg.L": {"rot": (45, 0, 0)},
        "UpperLeg.R": {"rot": (-12, 0, 4)}, "LowerLeg.R": {"rot": (38, 0, 0)},
        "UpperArm.L": {"rot": (36, 0, -28)}, "UpperArm.R": {"rot": (31, 0, 26)},
    }
    death_flat = {
        "Hips": {"rot": (90, 0, 4), "loc": (0, -0.58, 0.32)}, "Spine": {"rot": (4, 0, -2)}, "Chest": {"rot": (3, 0, 2)},
        "Neck": {"rot": (-8, 0, 0)}, "Head": {"rot": (-10, 3, -4)},
        "UpperLeg.L": {"rot": (-5, 0, -2)}, "LowerLeg.L": {"rot": (9, 0, 0)},
        "UpperLeg.R": {"rot": (2, 0, 3)}, "LowerLeg.R": {"rot": (5, 0, 0)},
        "UpperArm.L": {"rot": (23, 0, -38)}, "LowerArm.L": {"rot": (8, 0, -15)},
        "UpperArm.R": {"rot": (18, 0, 34)}, "LowerArm.R": {"rot": (5, 0, 12)},
    }
    make_action(armature, "Death", [(1, death_start), (11, death_knees), (24, death_fall), (36, death_flat), (40, death_flat)])
    armature.animation_data.action = None
    bpy.context.scene.frame_set(0)
    reset_pose(armature)


def triangle_count(mesh_obj):
    mesh_obj.data.calc_loop_triangles()
    return len(mesh_obj.data.loop_triangles)


def deformed_bounds(mesh_obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh_obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return min(p.z for p in points), max(p.z for p in points)


def export(zombie, armature):
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    zombie.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(OUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=True,
        export_force_sampling=True,
        export_frame_range=True,
    )


def verify_reimport():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(OUT))
    scene = bpy.context.scene
    zombie = bpy.data.objects.get("Zombie")
    armature = bpy.data.objects.get("Armature")
    assert zombie and zombie.type == "MESH"
    assert armature and armature.type == "ARMATURE"
    # The importer creates an icosphere bone-display helper in its explicitly
    # non-exported collection; it is not a node or mesh contained in the GLB.
    imported_nodes = [obj for obj in scene.objects if not any(c.name == "glTF_not_exported" for c in obj.users_collection)]
    assert [obj.name for obj in imported_nodes if obj.type == "MESH"] == ["Zombie"]
    assert not [obj for obj in scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    assert set(armature.data.bones.keys()) == set(BONES.keys())
    assert zombie.parent == armature
    assert all(abs(value - 1.0) < 1e-6 for value in (*zombie.scale, *armature.scale))
    expected_materials = {"Zombie Skin", "Shirt", "Jeans", "Boots", "Hair", "Eyes", "Stain"}
    assert {mat.name for mat in zombie.data.materials} == expected_materials
    actions = {a.name: a for a in bpy.data.actions if a.name in EXPECTED_ACTIONS}
    assert {a.name for a in bpy.data.actions} == set(EXPECTED_ACTIONS), sorted(a.name for a in bpy.data.actions)
    ranges = {name: tuple(round(v, 3) for v in actions[name].frame_range) for name in EXPECTED_ACTIONS}
    expected_ranges = {"Idle": (1.0, 76.0), "Walk": (1.0, 40.0), "Punch": (1.0, 34.0), "HitReact": (1.0, 15.0), "Death": (1.0, 40.0)}
    assert ranges == expected_ranges, ranges
    armature.animation_data_create()
    armature.animation_data.action = None
    armature.data.pose_position = "REST"
    scene.frame_set(0)
    bpy.context.view_layer.update()
    low, high = deformed_bounds(zombie)
    rest_height = high - low
    tris = triangle_count(zombie)
    armature.data.pose_position = "POSE"
    armature.animation_data.action = actions["Death"]
    scene.frame_set(round(actions["Death"].frame_range[1]))
    bpy.context.view_layer.update()
    _death_low, death_high = deformed_bounds(zombie)
    assert 1500 <= tris <= 4000, tris
    assert 1.75 <= rest_height <= 1.82, rest_height
    assert death_high < 0.5, death_high
    print("CHECK_ACTIONS", " ".join(f"{name}:{ranges[name][0]:g}-{ranges[name][1]:g}" for name in EXPECTED_ACTIONS))
    print("CHECK_TRIANGLES", tris)
    print("CHECK_REST_HEIGHT", f"{rest_height:.3f}")
    print("CHECK_DEATH_LAST_HIGHEST", f"{death_high:.3f}")


def main():
    reset()
    bpy.context.scene.render.fps = FPS
    mats = build_materials()
    armature = build_armature()
    zombie = build_character(mats)
    bind(zombie, armature)
    build_animations(armature)
    assert armature.scale == Vector((1, 1, 1)) and zombie.scale == Vector((1, 1, 1))
    export(zombie, armature)
    verify_reimport()


if __name__ == "__main__":
    main()
