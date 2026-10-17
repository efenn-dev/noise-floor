"""Build Noise Floor's first-person arms from Davlet's Modular FPS Arms Pack 06 (paid, royalty-free licence).

Emmitt bought the pack on Superhive (2026-10-16). Its files are local-only under C:/projects/assets-src/fps-arms
(never in git, like the UAL motion capture; FPS06_DIR overrides the folder); only the exported arms are
committed. Variant 02a: the jacket sleeves (FPS06_Clothing_Base) and Gloves06 v01, skinned to Epic's UE5 skeleton.

Run, after tools/art/fp_arm_fps06_textures.py has prepared the textures:
    blender.exe -b --factory-startup --python tools/art/fp_arm_fps06.py

Each side (the game's right arm is the pack's _r bones) is cut from the pack's meshes, and every vertex is moved
from the pack's rest pose (arms bent in front of an Unreal camera) to the game's contract (see fp_arm_mpfb.py) by
a blend of rigid per-bone transforms: the hand by fp_arm_mpfb's palm alignment, each finger into its grip round
the 34 mm handle, the forearm onto the Forearm bone keeping the hand's roll, and the upper arm swung straight on
past the elbow so the sleeve runs off toward the shoulder. Weights go onto the 17-bone contract (Forearm, Hand,
three bones a digit). The pack's own UVs and textures stay: materials "FP Glove" and "FP Sleeve", which
Hands.LOOKS leaves as made. Every measurement is taken from the re-imported GLB.
"""

import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fp_arm_mpfb as base  # noqa: E402  (palm alignment, grip chains, the 17-bone rig, poses, preview kit)

MODEL_DIR = base.MODEL_DIR
SHOT_DIR = base.SHOT_DIR
PACK = Path(os.environ.get("FPS06_DIR", "C:/projects/assets-src/fps-arms"))
FBX = PACK / "extracted" / "fbx" / "FPS06_FBX" / "FPS06_UE5" / "FPS06_Arms_Full_UE5_02a.fbx"
PREPARED = PACK / "prepared"
## The prepared textures are copied here once, shared by both arms; the GLBs point at them (export_keep_originals)
## so Godot imports each picture once, with mipmaps and compression, instead of unpacking a copy per arm.
TEXTURE_DIR = base.ROOT / "assets" / "textures" / "fp_arms"
TEXTURES = ("glove_base", "glove_normal_left", "glove_normal_right", "glove_rm", "sleeve_base", "sleeve_normal",
            "sleeve_rm")
SLEEVE_MESH = "FPS06_Clothing_Base_UE5_01_Full_01"
GLOVE_MESH = {1: "GL06_v01r_UE5", -1: "GL06_v01l_UE5"}
MATERIAL_NAMES = ["FP Glove", "FP Sleeve"]
TRIANGLE_LIMIT = 32000
## Godot-space nudge of the palm from fp_arm_mpfb's grip (the glove is thicker than a bare MakeHuman hand).
PALM_OFFSET = Vector((float(os.environ.get('PALM_X', 0.0)), float(os.environ.get('PALM_Y', 0.0)), float(os.environ.get('PALM_Z', 0.0))))
SKIN_BONE = {"Upper": "Forearm"}  # the straightened upper arm rides the forearm bone


def palm_hand_transform(source_armature, side):
    """fp_arm_mpfb.hand_transform with the wrist target moved by PALM_OFFSET (x mirrored per side)."""
    transform, rotation, wrist_g = _original_hand_transform(source_armature, side)
    offset = Vector((side * PALM_OFFSET.x, PALM_OFFSET.y, PALM_OFFSET.z))
    return Matrix.Translation(base.g2b(offset)) @ transform, rotation, wrist_g + offset


_original_hand_transform = base.hand_transform
base.hand_transform = palm_hand_transform


## Where the four fingers' joints sit round the handle (its 17 mm radius plus half a gloved finger).
R_WRAP = float(os.environ.get("R_WRAP", 0.030))


def wrap_chain(side, root, lengths, hand_dir):
    """A finger closed round the handle: the three joint bends (every one curling forward, so the engine's
    pose maths finds one curl axis; see Hands.finger_rest) that best keep the joints on the R_WRAP circle round
    the handle's axis without any of the finger's bone line going inside it. Searched in 2-degree steps."""
    def turn(direction, degrees):
        a = math.radians(side * degrees)
        return Vector((direction.x * math.cos(a) + direction.z * math.sin(a), 0.0,
                       -direction.x * math.sin(a) + direction.z * math.cos(a)))

    def radius(point):
        return math.hypot(point.x, point.z)

    def clear(start, end):
        return all(radius(start.lerp(end, t)) >= R_WRAP - 0.0005 for t in (0.25, 0.5, 0.75, 1.0))

    flat = Vector((hand_dir.x, 0.0, hand_dir.z)).normalized()
    start = Vector((root.x, 0.0, root.z))
    best = None
    for b1 in range(4, 100, 2):
        d1 = turn(flat, b1)
        p1 = start + d1 * lengths[0]
        if not clear(start, p1):
            continue
        for b2 in range(4, 110, 2):
            d2 = turn(d1, b2)
            p2 = p1 + d2 * lengths[1]
            if not clear(p1, p2):
                continue
            for b3 in range(4, 110, 2):
                d3 = turn(d2, b3)
                p3 = p2 + d3 * lengths[2]
                if not clear(p2, p3):
                    continue
                cost = ((radius(p2) - R_WRAP) ** 2 + (radius(p3) - R_WRAP) ** 2 + 0.5 * (radius(p1) - R_WRAP) ** 2
                        + 1.0e-8 * (b2 - b3) ** 2)
                if best is None or cost < best[0]:
                    best = (cost, (b1, b2, b3), [start, p1, p2, p3])
    assert best is not None, ("no grip clears the handle", root, lengths)
    return [Vector((point.x, root.y, point.z)) for point in best[2]], best[1]


def wrapped_rest_definition(source_armature, side):
    """fp_arm_mpfb.make_rest_definition with the fingers wrapped by wrap_chain (the thumb keeps its directions)."""
    suffix = base.source_side(side)
    source_bones = source_armature.data.bones
    hand_xform, hand_rotation, wrist_g = base.hand_transform(source_armature, side)
    definition = {"Forearm": (Vector((side * 0.070, -0.104, 0.424)), wrist_g, None)}
    source_hand = source_bones[f"hand_{suffix}"]
    definition["Hand"] = (base.b2g(hand_xform @ source_hand.head_local), base.b2g(hand_xform @ source_hand.tail_local),
                          "Forearm")
    chains = {}
    for digit in ("Thumb", *base.FINGERS):
        source_chain = [source_bones[base.source_name(digit, 1, suffix)].head_local.copy()]
        for index in range(1, 4):
            source_chain.append(source_bones[base.source_name(digit, index, suffix)].tail_local.copy())
        lengths = [(source_chain[index + 1] - source_chain[index]).length for index in range(3)]
        root = base.b2g(hand_xform @ source_chain[0])
        if digit == "Thumb":
            chain = base.target_chain(root, lengths, base.grip_directions(side, digit))
        else:
            hand_dir = (definition["Hand"][1] - definition["Hand"][0]).normalized()
            chain, bends = wrap_chain(side, root, lengths, hand_dir)
            print("GRIP", "right" if side > 0 else "left", digit, "bends", bends)
        chains[digit] = chain
        parent = "Hand"
        for index in range(3):
            name = base.output_name(digit, index + 1)
            definition[name] = (chain[index], chain[index + 1], parent)
            parent = name
    assert tuple(definition) == base.BONE_NAMES
    return definition, chains, hand_xform, hand_rotation


base.make_rest_definition = wrapped_rest_definition


def import_pack():
    """The pack's FBX with bones and vertices baked to metres, every object at identity."""
    base.clean_scene(remove_actions=True)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.images):
        bpy.data.images.remove(block)
    assert FBX.is_file(), f"FPS Arms Pack 06 not found at {FBX}"
    bpy.ops.import_scene.fbx(filepath=str(FBX))
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    meshes = {obj.name: obj for obj in bpy.context.scene.objects if obj.type == "MESH"}
    probe_bone = armature.matrix_world @ armature.data.bones["hand_r"].head_local
    probe_vertex = {name: obj.matrix_world @ obj.data.vertices[0].co for name, obj in meshes.items()}
    # Centimetres under a 0.01-scaled armature: unparent (keeping where they are), then bake every transform.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes.values():
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(meshes.values()))
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    assert (armature.data.bones["hand_r"].head_local - probe_bone).length < 1.0e-4
    for name, obj in meshes.items():
        assert (obj.data.vertices[0].co - probe_vertex[name]).length < 1.0e-4, name
    fix_bone_ends(armature)
    return armature, meshes


def fix_bone_ends(armature):
    """FBX keeps where each bone starts; Blender guesses its end. Point every arm and finger bone at the next joint."""
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    bones = armature.data.edit_bones
    for bone in bones:
        bone.use_connect = False
    for s in ("l", "r"):
        def head(name):
            return bones[f"{name}_{s}"].head.copy()
        bones[f"upperarm_{s}"].tail = head("lowerarm")
        bones[f"lowerarm_{s}"].tail = head("hand")
        bones[f"hand_{s}"].tail = head("middle_01")
        for digit in ("thumb", "index", "middle", "ring", "pinky"):
            for index in (1, 2):
                bones[f"{digit}_0{index}_{s}"].tail = head(f"{digit}_0{index + 1}")
            last = bones[f"{digit}_03_{s}"]
            last.tail = last.head + (last.head - bones[f"{digit}_02_{s}"].head) * 0.85
    bpy.ops.object.mode_set(mode="OBJECT")


def transform_key(group_name, suffix):
    """Which rigid transform carries a vertex weighted to this pack bone (None: not this arm)."""
    if not group_name.endswith("_" + suffix):
        return None
    name = group_name[:-2]
    if name.startswith("clavicle"):
        return "Clavicle"
    if name.startswith(("upperarm", "u_biceps", "u_triceps")):
        return "Upper"
    if name.startswith(("lowerarm", "u_elbow")):
        return "Forearm"
    if name in ("hand", "u_hand_correct", "u_weapon") or name.endswith("metacarpal"):
        return "Hand"
    parts = name.split("_")
    if len(parts) == 2 and parts[0].capitalize() in ("Thumb", *base.FINGERS) and parts[1] in ("01", "02", "03"):
        return f"{parts[0].capitalize()}{int(parts[1])}"
    return None


def side_rig(source_armature, side):
    """The game armature for one side, and each transform from the pack's rest to the game's grip rest."""
    bpy.ops.object.select_all(action="DESELECT")  # build_armature's edit mode must hold only the new rig
    armature, definition, chains, transforms = base.build_armature(source_armature, side)
    if side > 0:
        hand_dir = (definition["Hand"][1] - definition["Hand"][0]).normalized()
        for digit, chain in chains.items():
            dirs = [hand_dir] + [(chain[i + 1] - chain[i]).normalized() for i in range(3)]
            signed = [math.degrees(math.atan2(dirs[j].cross(dirs[j + 1]).y, dirs[j].dot(dirs[j + 1]))) for j in range(3)]
            off = [round(math.degrees(math.asin(max(-1.0, min(1.0, d.y)))), 1) for d in dirs]
            print("CHAIN", digit, [f"r={math.hypot(p.x, p.z):.3f}" for p in chain], "bend_about_y", [round(b, 1) for b in signed], "dir_y_tilt", off)
    s = base.source_side(side)
    bones = source_armature.data.bones
    shoulder = bones[f"upperarm_{s}"].head_local
    elbow = bones[f"lowerarm_{s}"].head_local
    wrist = bones[f"hand_{s}"].head_local
    forearm_bone = armature.data.bones["Forearm"]
    hand_rotation = transforms["Hand"].to_3x3()
    source_dir = (wrist - elbow).normalized()
    target_dir = (forearm_bone.tail_local - forearm_bone.head_local).normalized()
    # The forearm keeps the roll the hand was given (a plain swing would twist the sleeve at the wrist).
    swing = (hand_rotation @ source_dir).rotation_difference(target_dir).to_matrix()
    forearm = (Matrix.Translation(forearm_bone.tail_local) @ (swing @ hand_rotation).to_4x4()
               @ Matrix.Translation(-wrist))
    assert (forearm @ wrist - forearm_bone.tail_local).length < 1.0e-5
    straighten = (elbow - shoulder).normalized().rotation_difference(source_dir).to_matrix().to_4x4()
    transforms["Forearm"] = forearm
    transforms["Upper"] = forearm @ Matrix.Translation(elbow) @ straighten @ Matrix.Translation(-elbow)
    return armature, definition, transforms


def cut_part(source, side, transforms, mat):
    """One side's share of a pack mesh, moved to the grip rest and weighted to the game's bones (UVs kept)."""
    s = base.source_side(side)
    names = {group.index: group.name for group in source.vertex_groups}
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = f"{source.name}_{'R' if side > 0 else 'L'}"
    bpy.context.collection.objects.link(obj)
    obj.modifiers.clear()
    keep = []
    skins = []
    for vertex in obj.data.vertices:
        shape = {}
        clavicle = 0.0
        for item in vertex.groups:
            key = transform_key(names[item.group], s)
            if key is None or item.weight <= 0.0:
                continue
            if key == "Clavicle":
                clavicle += item.weight
            else:
                shape[key] = shape.get(key, 0.0) + item.weight
        total = sum(shape.values())
        keep.append(total >= 0.5 and clavicle < 0.3)
        skin = {}
        if total > 1.0e-8:
            point = Vector()
            for key, weight in shape.items():
                point += (transforms[key] @ vertex.co) * (weight / total)
                bone = SKIN_BONE.get(key, key)
                skin[bone] = skin.get(bone, 0.0) + weight / total
            vertex.co = point
        strongest = sorted(skin.items(), key=lambda item: item[1], reverse=True)[:4]
        top = sum(weight for _bone, weight in strongest)
        skins.append({bone: weight / top for bone, weight in strongest} if top > 0.0 else {})
    obj.vertex_groups.clear()
    groups = {name: obj.vertex_groups.new(name=name) for name in base.BONE_NAMES}
    for index, skin in enumerate(skins):
        for bone, weight in skin.items():
            groups[bone].add([index], min(0.999999, weight), "REPLACE")
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    mesh.verts.ensure_lookup_table()
    drop = [face for face in mesh.faces if not all(keep[vert.index] for vert in face.verts)]
    bmesh.ops.delete(mesh, geom=drop, context="FACES")
    bmesh.ops.delete(mesh, geom=[vert for vert in mesh.verts if not vert.link_faces], context="VERTS")
    mesh.to_mesh(obj.data)
    mesh.free()
    assert obj.data.polygons, f"nothing of {source.name} on side {side}"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.mesh.customdata_custom_splitnormals_clear()  # the pack's normals were for its own pose
    obj.data.shade_smooth()
    return obj


def make_material(name, base_color, normal, rm):
    """Principled BSDF on the prepared textures, wired the way the glTF exporter maps them."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]

    def image(path, colour_space):
        assert path.is_file(), f"run tools/art/fp_arm_fps06_textures.py first ({path} missing)"
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(path), check_existing=True)
        node.image.colorspace_settings.name = colour_space
        return node

    links.new(image(base_color, "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    links.new(image(normal, "Non-Color").outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(image(rm, "Non-Color").outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def finish(parts, armature):
    """One mesh, FPArm, skinned to the game armature at the origin."""
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    mesh = bpy.context.object
    mesh.name = "FPArm"
    mesh.data.name = "FPArm"
    assert sorted(slot.material.name for slot in mesh.material_slots) == MATERIAL_NAMES
    mesh.parent = armature
    mesh.matrix_parent_inverse.identity()
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    modifier.use_bone_envelopes = False
    return mesh


def export_arm(side, mesh, armature):
    piece_id = "fp_arm_right" if side > 0 else "fp_arm_left"
    output = MODEL_DIR / f"{piece_id}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_materials="EXPORT", export_image_format="AUTO",
        export_keep_originals=True,
        export_cameras=False, export_lights=False, export_skins=True,
        export_animations=True, export_animation_mode="ACTIONS",
        export_bake_animation=True, export_force_sampling=False, export_frame_range=True,
    )
    return piece_id, output


def copy_textures():
    import shutil
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for name in TEXTURES:
        source = PREPARED / f"{name}.jpg"
        assert source.is_file(), f"run tools/art/fp_arm_fps06_textures.py first ({source} missing)"
        shutil.copyfile(source, TEXTURE_DIR / f"{name}.jpg")


def build_side(side):
    source_armature, meshes = import_pack()
    bpy.context.scene.render.fps = base.FPS
    which = "right" if side > 0 else "left"
    glove = make_material("FP Glove", TEXTURE_DIR / "glove_base.jpg", TEXTURE_DIR / f"glove_normal_{which}.jpg",
                          TEXTURE_DIR / "glove_rm.jpg")
    sleeve = make_material("FP Sleeve", TEXTURE_DIR / "sleeve_base.jpg", TEXTURE_DIR / "sleeve_normal.jpg",
                           TEXTURE_DIR / "sleeve_rm.jpg")
    armature, _definition, transforms = side_rig(source_armature, side)
    parts = [cut_part(meshes[GLOVE_MESH[side]], side, transforms, glove),
             cut_part(meshes[SLEEVE_MESH], side, transforms, sleeve)]
    for obj in [source_armature, *meshes.values()]:
        bpy.data.objects.remove(obj, do_unlink=True)
    mesh = finish(parts, armature)
    base.make_actions(armature, side)
    result = export_arm(side, mesh, armature)
    print("EXPORTED", result[1], f"{result[1].stat().st_size // 1024} KB")
    return result


def validate(piece_id, output, side, render=False):
    """Re-import the GLB and measure it: rig, poses, materials, the grip's clearance and the sleeve's reach."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = base.FPS
    bpy.ops.import_scene.gltf(filepath=str(output))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"
              and not any(collection.name == "glTF_not_exported" for collection in obj.users_collection)]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    assert len(meshes) == 1 and len(armatures) == 1, (meshes, armatures)
    mesh, armature = meshes[0], armatures[0]
    assert mesh.name == "FPArm" and armature.name == "Armature" and mesh.parent == armature
    materials = sorted(mat.name for mat in mesh.data.materials if mat)
    assert materials == MATERIAL_NAMES, materials
    mesh.data.calc_loop_triangles()
    triangles = len(mesh.data.loop_triangles)
    assert triangles < TRIANGLE_LIMIT, triangles
    bones = armature.data.bones
    assert tuple(bones.keys()) == base.BONE_NAMES, tuple(bones.keys())
    actions = sorted(action.name for action in bpy.data.actions)
    assert actions == sorted(base.ACTION_NAMES), actions
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    points = base.evaluated_points(mesh)
    glove = next(index for index, mat in enumerate(mesh.data.materials) if mat.name == "FP Glove")
    sleeve = next(index for index, mat in enumerate(mesh.data.materials) if mat.name == "FP Sleeve")
    glove_ids = {i for polygon in mesh.data.polygons if polygon.material_index == glove for i in polygon.vertices}
    sleeve_ids = {i for polygon in mesh.data.polygons if polygon.material_index == sleeve for i in polygon.vertices}
    handle = [points[i] for i in glove_ids if abs(points[i].y) < 0.040]
    clearance = min(math.hypot(point.x, point.z) for point in handle)
    inside = sum(math.hypot(point.x, point.z) < 0.017 for point in handle)
    wrist = base.b2g(bones["Hand"].head_local)
    back = (base.b2g(bones["Forearm"].head_local) - wrist).normalized()
    reach = max((points[i] - wrist).dot(back) for i in sleeve_ids)
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    print("VALIDATION", piece_id)
    print("  bounds_godot", f"({lo.x:.3f},{lo.y:.3f},{lo.z:.3f})..({hi.x:.3f},{hi.y:.3f},{hi.z:.3f})")
    print("  triangles", triangles, "materials", materials, "animations", actions)
    print("  handle_clearance", f"{clearance:.4f}", "glove_vertices_inside_handle", inside)
    names = {group.index: group.name for group in mesh.vertex_groups}
    by_bone = {}
    for i in glove_ids:
        if abs(points[i].y) < 0.040 and math.hypot(points[i].x, points[i].z) < 0.017:
            groups = mesh.data.vertices[i].groups
            bone = names[max(groups, key=lambda item: item.weight).group] if len(groups) else "?"
            by_bone[bone] = by_bone.get(bone, 0) + 1
    print("  inside_by_bone", dict(sorted(by_bone.items())))
    print("  sleeve_reach_behind_wrist", f"{reach:.3f}")
    assert reach > 0.45, reach
    if render:
        render_previews(side, armature)
    return {"bounds": (lo, hi), "triangles": triangles}


def render_previews(side, armature):
    """Grip round a handle from the player's eye, and from the palm side."""
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    camera = base.setup_preview()
    armature.data.pose_position = "POSE"
    handle = base.add_preview_prop("Grip", side)
    for name, location, target, angle in (
        ("first_person", (0.20, 0.30, 0.55), (0.0, 0.0, 0.0), 70.0),
        ("back", (0.26, -0.03, -0.30), (0.02, 0.0, 0.03), 48.0),
        ("palm", (-0.24, -0.06, -0.28), (0.0, 0.0, 0.03), 48.0),
        ("down_the_handle", (0.0, 0.42, 0.001), (0.0, 0.0, 0.0), 30.0),
    ):
        camera.data.angle_y = math.radians(angle)
        camera.location = base.g2b(location)
        base.look_at(camera, target)
        scene.render.filepath = str(SHOT_DIR / f"fp_arm_fps06_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)
    bpy.data.objects.remove(handle, do_unlink=True)


def main():
    copy_textures()
    right = build_side(1)
    left = build_side(-1)
    validate(*left, -1)
    validate(*right, 1, render=True)


if __name__ == "__main__":
    main()
