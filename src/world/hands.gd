class_name Hands
extends RefCounted
## V12 (Sprint 4, Emmitt: "work on the animations"): first-person hands. A gloved hand and sleeved forearm
## are attached to each held weapon as children, so they follow every swing and kick. V13 prefers the new
## rigged arms, keeps the old static hands as a fallback, and lets reload/inspect poses temporarily move a
## hand away from its grip. Model convention: the hand grips a handle along its local +Y through the origin,
## the forearm runs back toward +Z, the right hand's back faces +X.

const ARM_MODELS := {"right": "res://assets/models/fp_arm_right.glb", "left": "res://assets/models/fp_arm_left.glb"}
const MODELS := {"right": "res://assets/models/fp_hand_right.glb", "left": "res://assets/models/fp_hand_left.glb"}
const LOOKS := {
	"materials": {
		"Arm Glove": {"texture": "leather_boot", "tile_m": 0.08, "tint": Color(0.78, 0.58, 0.4), "metallic": 0.0, "roughness": 0.8},
		"Arm Sleeve": {"texture": "cloth_cotton", "tile_m": 0.1, "tint": Color(0.3, 0.27, 0.22), "metallic": 0.0, "roughness": 0.95},
		# V22: the bare-wrist band is an open ring that showed as a peach scroll from some angles; it's the
		# jacket's cuff now, so the sleeve meets the glove.
		"Arm Skin": {"texture": "cloth_cotton", "tile_m": 0.1, "tint": Color(0.26, 0.23, 0.19), "metallic": 0.0, "roughness": 0.95},
	},
	# V37: the bought arms (tools/art/fp_arm_fps06.py) bring their own textured glove and jacket sleeve.
	"untextured": ["FP Glove", "FP Sleeve"],
}
## Materials drawn from both sides: a pose can turn a sleeve's open end or a glove's cuff toward you.
const DOUBLE_SIDED := ["Arm Sleeve", "Arm Skin", "FP Sleeve", "FP Glove"]
## Where each hand goes on each weapon: [position, rotation in degrees] in the weapon model's own space.
## Melee models: grip at the origin, pointing up +Y (tools/art/melee_common.py). Gun grips are Codex's
## measured anchors (pistol grip (0, -0.024, 0.071), rifle grip (-0.02, -0.009, 0.18)).
const MELEE := {
	"pipe": {"right": [Vector3.ZERO, Vector3.ZERO]},
	"bat": {"right": [Vector3.ZERO, Vector3.ZERO], "left": [Vector3(0, -0.07, 0), Vector3(0, 0, 0)]},
	"axe": {"right": [Vector3(0, 0.02, 0), Vector3.ZERO], "left": [Vector3(0, -0.07, 0), Vector3.ZERO]},  # left hand at the end of the handle, like a real axe grip
	"machete": {"right": [Vector3.ZERO, Vector3.ZERO]},
	"knife": {"right": [Vector3.ZERO, Vector3.ZERO]},
}
const GUNS := {
	"pistol": {"right": [Vector3(0, -0.024, 0.071), Vector3(-15, 0, 0)],
			"left": [Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0)]},
	"hunting_rifle": {"right": [Vector3(-0.02, -0.03, 0.18), Vector3(-15, 0, 0)],
			"left": [Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0)]},
	# V30: measured after kit.finish() centred and exported the authored GLBs. The right hand is on the
	# trigger grip; the left hand is centred on the pump / crossbow foregrip.
	"shotgun": {"right": [Vector3(0.0, -0.025, 0.28), Vector3(-15, 0, 0)],
			"left": [Vector3(0.0, -0.015, -0.23), Vector3(90, 0, 0)]},
	"crossbow": {"right": [Vector3(0.0, -0.020, 0.18), Vector3(-15, 0, 0)],
			"left": [Vector3(0.0, 0.0, -0.18), Vector3(90, 0, 0)]},
}

## V30 throwables sit across the right palm with the forearm leaving the lower-right of the view.
const THROWABLES := {
	"pipe_bomb": {"right": [Vector3(0.0, -0.04, 0.0), Vector3(0, 0, 78)]},
	"bottle": {"right": [Vector3(0.0, -0.10, 0.0), Vector3(0, 0, 12)]},
}


## Which way each forearm should leave the screen with the weapon at rest, in camera space: down and back,
## the right arm toward the bottom-right corner, the left toward the bottom-left.
const ARM_DIR := {"right": Vector3(0.35, -0.75, 0.55), "left": Vector3(-0.45, -0.75, 0.5)}
const FOREARM := Vector3(0.0, -0.2588, 0.9659)  # the model's forearm direction: +Z, 15 degrees down
## A real grip holds a handle at a slant across the palm, not square to the forearm: the hand is tipped this
## much about its own X, which also swings the forearm back toward you.
const WRIST_TILT := deg_to_rad(25.0)
## V22: where each shoulder is, in camera space (below and beside the eye, a little behind it), and how far a hand
## must move off its grip before its forearm swings fully toward that shoulder.
const SHOULDER := {"right": Vector3(0.22, -0.38, 0.12), "left": Vector3(-0.22, -0.38, 0.12)}
const FREE_AT := 0.06


## The hand's basis in the weapon: the config's alignment, the roll about the handle, then the wrist's slant.
static func hand_basis(base: Basis, roll: float) -> Basis:
	return base * Basis(Vector3.UP, roll) * Basis(Vector3.RIGHT, WRIST_TILT)


## Adds the hands a weapon needs as children named Hand_R / Hand_L. `table` is MELEE or GUNS. Each hand is
## rolled about its grip axis so that, with the weapon in its resting pose (`rest`, camera space), the forearm
## runs off toward the bottom corner of the screen instead of up past the camera.
static func attach(weapon: Node3D, id: String, table: Dictionary, rest: Basis = Basis()) -> void:
	var cfg: Dictionary = table.get(id, {})
	for side: String in ["right", "left"]:
		if not cfg.has(side):
			continue
		var hand := make(side)
		hand.name = "Hand_R" if side == "right" else "Hand_L"
		var pr: Array = cfg[side]
		var r: Vector3 = pr[1]
		var base := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
		hand.set_meta("base", base)
		hand.set_meta("grip_base", base)
		hand.set_meta("grip_position", pr[0])
		hand.set_meta("side", side)
		hand.transform = Transform3D(hand_basis(base, best_roll(base, rest, ARM_DIR[side].normalized())), pr[0])
		weapon.add_child(hand)
		set_pose(hand, "Grip")


## The roll about the hand's grip axis (radians) that points its forearm closest to `dir` (camera space), with
## the weapon's basis in camera space `rest`. Exact (the best angle of a vector spun about one axis), so the
## hands turn smoothly when this runs every frame.
static func best_roll(base: Basis, rest: Basis, dir: Vector3) -> float:
	var v := Basis(Vector3.RIGHT, WRIST_TILT) * FOREARM  # the forearm before the roll
	var d := ((rest * base).inverse() * dir)  # the wanted direction, in the hand's unrolled frame
	var a := d.x * v.x + d.z * v.z
	var b := d.x * v.z - d.z * v.x
	return atan2(b, a)


## V12: re-aims every hand under `holder` (Hand_R / Hand_L made by attach) for the holder's current basis in
## camera space, so the forearms keep running off the bottom of the screen through a whole swing instead of
## sticking out wherever the weapon points. Melee and Shooter call it each frame after posing the weapon.
static func reaim(holder: Node3D, cam_basis: Basis) -> void:
	for hand_name: String in ["Hand_R", "Hand_L"]:
		var hand := holder.get_node_or_null(hand_name) as Node3D
		if hand == null or not hand.has_meta("base"):
			continue
		var base: Basis = hand.get_meta("grip_base", hand.get_meta("base"))
		var position: Vector3 = hand.get_meta("grip_position", hand.position)
		if hand.has_meta("target_base"):
			var weight: float = clampf(float(hand.get_meta("target_weight", 1.0)), 0.0, 1.0)
			var target_base: Basis = hand.get_meta("target_base")
			var target_position: Vector3 = hand.get_meta("target_position")
			base = base.slerp(target_base, weight)
			position = position.lerp(target_position, weight)
		var side: String = hand.get_meta("side")
		hand.position = position
		hand.basis = hand_basis(base, best_roll(base, cam_basis, ARM_DIR[side].normalized()))
		var free := 0.0
		if hand.has_meta("target_base"):
			free = clampf(float(hand.get_meta("target_weight", 1.0)) * position.distance_to(hand.get_meta("grip_position", position))
					/ FREE_AT, 0.0, 1.0)
		if free > 0.0:
			_point_at_shoulder(hand, holder, cam_basis, side, free)


## V22: a hand that has let go of the weapon (reaching for a magazine, racking the slide, loading rounds) turns
## so its forearm runs back toward that side's shoulder, below and beside the eye, the way a real arm hangs;
## otherwise a keyframed hand near the camera could point its sleeve straight at you. `amount` 0-1 blends it in
## as the hand leaves the grip, so a hand on the grip keeps its exact hold.
static func _point_at_shoulder(hand: Node3D, holder: Node3D, cam_basis: Basis, side: String, amount: float) -> void:
	var hand_cam := holder.position + cam_basis * hand.position
	var shoulder: Vector3 = SHOULDER[side]
	var want := (shoulder - hand_cam).normalized()
	var now := (cam_basis * hand.basis * FOREARM).normalized()
	if now.dot(want) > 0.9999:
		return
	var turn := Basis(Quaternion.IDENTITY.slerp(Quaternion(now, want), amount))
	hand.basis = (cam_basis.inverse() * turn * cam_basis * hand.basis).orthonormalized()


## V13: an absolute target in the holder's space. reaim() blends from the authored grip, then rolls the
## forearm toward the bottom of the screen as before. Rotation is in radians, like Node3D.rotation.
static func set_target(hand: Node3D, position: Vector3, rotation: Vector3, weight: float = 1.0) -> void:
	if hand == null:
		return
	hand.set_meta("target_position", position)
	hand.set_meta("target_base", Basis.from_euler(rotation))
	hand.set_meta("target_weight", clampf(weight, 0.0, 1.0))


static func clear_target(hand: Node3D) -> void:
	if hand == null:
		return
	for key: StringName in [&"target_position", &"target_base", &"target_weight"]:
		if hand.has_meta(key):
			hand.remove_meta(key)


## V13: cross-fades a rigged arm to one of its single-pose animations. Static hands and placeholders have
## no AnimationPlayer, so this deliberately does nothing for them.
static func set_pose(hand: Node3D, pose: String, blend: float = 0.12) -> void:
	if hand == null:
		return
	var players := hand.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	if player == null or not player.has_animation(pose):
		return
	if player.current_animation != pose or not player.is_playing():
		player.play(pose, blend)


## V22 (Emmitt: "fix the hands in the engine"): the finger poses are built here from the rig's own rest pose
## instead of using the animations baked in Blender (every Blender pass bent some finger the wrong way once it
## reached Godot). The rest pose is the grip round a 34 mm handle; each pose gives, per finger, how bent each
## joint should be (degrees between a bone and the one before it: knuckle, middle, tip), and each joint is
## turned about that finger's own curl axis, measured from the rest bones, by the difference.
const FINGERS := {
	"Thumb": ["Thumb1", "Thumb2", "Thumb3"], "Index": ["Index1", "Index2", "Index3"],
	"Middle": ["Middle1", "Middle2", "Middle3"], "Ring": ["Ring1", "Ring2", "Ring3"],
	"Pinky": ["Pinky1", "Pinky2", "Pinky3"],
}
## Bends per pose; "*" is every finger but the thumb unless the finger is listed. "Grip" is the rest pose.
const POSE_BENDS := {
	"Grip": {},
	"Fist": {"*": [100.0, 110.0, 70.0], "Thumb": [24.0, 28.0, 12.0]},  # V37: tuned on the bought arms (tools/art/hand_poses.gd)
	"Open": {"*": [14.0, 18.0, 10.0], "Thumb": [16.0, 8.0, 4.0]},
	"Flat": {"*": [2.0, 2.0, 2.0], "Thumb": [8.0, 2.0, 0.0]},
	"Pinch": {"Index": [38.0, 48.0, 30.0], "Middle": [46.0, 58.0, 36.0], "Ring": [54.0, 66.0, 40.0],
			"Pinky": [60.0, 70.0, 44.0], "Thumb": [34.0, 32.0, 26.0]},
	"HoldMag": {"*": [44.0, 34.0, 38.0], "Index": [20.0, 18.0, 12.0], "Thumb": [26.0, 23.0, 4.0]},
}
const SKELETON_PATH := "Armature/Skeleton3D"
## The jacket sleeve: one tapered tube on the Forearm bone from over the glove's cuff, up the forearm and on
## past the elbow toward the shoulder, so the arm always runs off the screen and reads as one sleeve.
## V31: the model's own sleeve runs straight down the bone, but its hand and cuff sit about 8 cm to one side of
## that line, so on a long gun's fore-end the sleeve showed as a separate pipe beside the wrist. The tube is
## centred on the cuff now (measured from the mesh) and the model's own sleeve is hidden.
const SLEEVE_EXTENSION := {"wrist_gap": 0.0, "past_elbow": 0.45, "wrist_radius": 0.042, "shoulder_radius": 0.066}
static var _pose_libraries: Dictionary = {}  # side -> AnimationLibrary, built once
static var _cuff_centres: Dictionary = {}  # side -> Vector3, measured once
static var _hidden: StandardMaterial3D


## How bent each joint of `bones` is in the rest pose (degrees between a bone and its parent), and the finger's
## curl axis in skeleton space (the sum of the joints' bend axes, so a nearly straight joint doesn't decide it).
static func finger_rest(sk: Skeleton3D, bones: Array) -> Dictionary:
	var dirs: Array[Vector3] = []
	var parent := sk.get_bone_parent(sk.find_bone(bones[0]))
	dirs.append(sk.get_bone_global_rest(parent).basis.y.normalized())
	for b: String in bones:
		dirs.append(sk.get_bone_global_rest(sk.find_bone(b)).basis.y.normalized())
	var axis := Vector3.ZERO
	var bends: Array[float] = []
	for j in bones.size():
		axis += dirs[j].cross(dirs[j + 1])
		bends.append(rad_to_deg(dirs[j].angle_to(dirs[j + 1])))
	return {"axis": axis.normalized() if axis.length() > 0.0001 else Vector3.UP, "bends": bends}


## The local rotation that bends `bone` by `delta_deg` about the skeleton-space `axis`, starting from its rest.
static func bent_rotation(sk: Skeleton3D, bone: int, axis: Vector3, delta_deg: float) -> Quaternion:
	var rest_global := sk.get_bone_global_rest(bone).basis.orthonormalized()
	var local_axis := (rest_global.inverse() * axis).normalized()
	var rest_local := sk.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	return rest_local * Quaternion(local_axis, deg_to_rad(delta_deg))


## The six hand poses as one-key animations on this rig (every finger bone keyed in each, so cross-fades blend
## cleanly). Built from `sk`'s rest pose.
static func build_pose_library(sk: Skeleton3D) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var rests := {}
	for finger: String in FINGERS:
		rests[finger] = finger_rest(sk, FINGERS[finger])
	for pose: String in POSE_BENDS:
		var spec: Dictionary = POSE_BENDS[pose]
		var anim := Animation.new()
		anim.length = 0.1
		for finger: String in FINGERS:
			var bones: Array = FINGERS[finger]
			var rest: Dictionary = rests[finger]
			var want: Array = spec.get(finger, spec.get("*", []) if finger != "Thumb" else [])
			for j in bones.size():
				var bone := sk.find_bone(bones[j])
				var delta := 0.0 if want.is_empty() else float(want[j]) - float(rest["bends"][j])
				var track := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(track, NodePath("%s:%s" % [SKELETON_PATH, bones[j]]))
				anim.rotation_track_insert_key(track, 0.0, bent_rotation(sk, bone, rest["axis"], delta))
		lib.add_animation(pose, anim)
	return lib


## Swaps the rig's baked poses for the engine-built ones and adds the sleeve extension. Does nothing to a model
## without the V13 skeleton (the V12 static hands, the placeholder).
static func _prepare_rig(node: Node3D, side: String) -> void:
	var sk := node.get_node_or_null(SKELETON_PATH) as Skeleton3D
	var player := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if sk == null or player == null or sk.find_bone("Forearm") < 0:
		return
	if not _pose_libraries.has(side):
		_pose_libraries[side] = build_pose_library(sk)
	for lib_name: StringName in player.get_animation_library_list():
		player.remove_animation_library(lib_name)
	player.add_animation_library("", _pose_libraries[side])
	if _sleeve_material(node) == null:
		return  # V37: an arm with its own sleeve on to the shoulder (the bought arms) needs no extension
	var attach := BoneAttachment3D.new()
	attach.name = "SleeveExtension"
	attach.bone_name = "Forearm"
	sk.add_child(attach)
	if not _cuff_centres.has(side):
		_cuff_centres[side] = cuff_centre(node, sk)
	var cuff: Vector3 = _cuff_centres[side]
	var tube := MeshInstance3D.new()
	# The Forearm bone runs +Y from the elbow end (its head) to the wrist; the Hand bone starts at the wrist.
	var forearm_len := sk.get_bone_rest(sk.find_bone("Hand")).origin.length()
	var wrist_end := forearm_len - float(SLEEVE_EXTENSION["wrist_gap"])
	var shoulder_end := -float(SLEEVE_EXTENSION["past_elbow"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = SLEEVE_EXTENSION["wrist_radius"]  # the cylinder's top (+Y) is the wrist end
	mesh.bottom_radius = SLEEVE_EXTENSION["shoulder_radius"]
	mesh.height = wrist_end - shoulder_end
	mesh.radial_segments = 24
	mesh.rings = 3
	tube.mesh = mesh
	tube.position = Vector3(cuff.x, (wrist_end + shoulder_end) / 2.0, cuff.z)
	tube.material_override = _sleeve_material(node)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attach.add_child(tube)
	_hide_model_sleeve(node)


## V31: the middle of the glove's cuff ("Arm Skin") across the Forearm bone, in that bone's space (y is 0). The
## arm is skinned in its rest pose, so the mesh's own vertices give it. Zero if the model has no cuff.
static func cuff_centre(node: Node3D, sk: Skeleton3D) -> Vector3:
	var to_bone := sk.get_bone_global_rest(sk.find_bone("Forearm")).affine_inverse()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			if source == null or source.resource_name != "Arm Skin":
				continue
			var sum := Vector3.ZERO
			var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v in verts:
				sum += to_bone * (mesh.transform * v)
			if verts.size() > 0:
				return Vector3(sum.x / verts.size(), 0.0, sum.z / verts.size())
	return Vector3.ZERO


## V31: the model's own sleeve runs down the bone, off to one side of the hand; the extension replaces it.
static func _hide_model_sleeve(node: Node3D) -> void:
	if _hidden == null:
		_hidden = StandardMaterial3D.new()
		_hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_hidden.albedo_color = Color(0, 0, 0, 0)
		_hidden.resource_name = "Arm Sleeve (hidden)"
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			if source != null and source.resource_name == "Arm Sleeve":
				mesh.set_surface_override_material(i, _hidden)


## The arm's own (already textured) sleeve material, so the extension matches it.
static func _sleeve_material(node: Node3D) -> Material:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i)
			if source != null and source.resource_name == "Arm Sleeve":
				var over := mesh.get_surface_override_material(i)
				return over if over != null else source
	return null


## One hand: prefer the V13 rigged arm, then the V12 static hand, else a placeholder; shadows stay off.
static func make(side: String) -> Node3D:
	var node: Node3D
	if ResourceLoader.exists(ARM_MODELS[side]):
		node = (load(ARM_MODELS[side]) as PackedScene).instantiate() as Node3D
		apply_materials(node)
		_prepare_rig(node, side)  # V22: engine-built finger poses and the sleeve on to the shoulder
	elif ResourceLoader.exists(MODELS[side]):
		node = (load(MODELS[side]) as PackedScene).instantiate() as Node3D
		apply_materials(node)
	else:
		node = _placeholder(side)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func apply_materials(node: Node3D) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null:
				continue
			if not LOOKS["materials"].has(source.resource_name):
				if source.resource_name in DOUBLE_SIDED and source.cull_mode != BaseMaterial3D.CULL_DISABLED:
					var own := source.duplicate() as StandardMaterial3D  # V37: the model's own textures, both sides
					own.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh.set_surface_override_material(i, own)
				continue
			var m: Dictionary = LOOKS["materials"][source.resource_name]
			var mat := Shooter._gun_material(source, String(m["texture"]), float(m["tile_m"]), m.get("tint", Color.WHITE), m)
			if source.resource_name in DOUBLE_SIDED and mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
				mat = mat.duplicate() as StandardMaterial3D
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # V16: when a pose turns the open end of the sleeve toward you, you see cloth, not a hole
			mesh.set_surface_override_material(i, mat)


## A fist and a forearm out of boxes, following the model convention.
static func _placeholder(side: String) -> Node3D:
	var root := Node3D.new()
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.32, 0.22, 0.14)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.16, 0.15, 0.13)
	var sx := 1.0 if side == "right" else -1.0
	var fist := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.08, 0.09, 0.075)
	fist.mesh = fb
	fist.position = Vector3(0.012 * sx, 0, 0.005)
	fist.material_override = glove
	root.add_child(fist)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.075, 0.075, 0.34)
	arm.mesh = ab
	arm.material_override = sleeve
	var tilt := deg_to_rad(15.0)
	arm.rotation.x = tilt  # leaves the hand toward +Z and a little down
	arm.position = Vector3(0.01 * sx, -sin(tilt) * 0.2, cos(tilt) * 0.2)
	root.add_child(arm)
	return root
