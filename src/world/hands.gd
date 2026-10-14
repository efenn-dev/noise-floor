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
	},
	"untextured": ["Arm Skin"],
}
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
}


## Which way each forearm should leave the screen with the weapon at rest, in camera space: down and back,
## the right arm toward the bottom-right corner, the left toward the bottom-left.
const ARM_DIR := {"right": Vector3(0.35, -0.75, 0.55), "left": Vector3(-0.45, -0.75, 0.5)}
const FOREARM := Vector3(0.0, -0.2588, 0.9659)  # the model's forearm direction: +Z, 15 degrees down
## A real grip holds a handle at a slant across the palm, not square to the forearm: the hand is tipped this
## much about its own X, which also swings the forearm back toward you.
const WRIST_TILT := deg_to_rad(25.0)


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


## One hand: prefer the V13 rigged arm, then the V12 static hand, else a placeholder; shadows stay off.
static func make(side: String) -> Node3D:
	var node: Node3D
	if ResourceLoader.exists(ARM_MODELS[side]):
		node = (load(ARM_MODELS[side]) as PackedScene).instantiate() as Node3D
		apply_materials(node)
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
			if source == null or not LOOKS["materials"].has(source.resource_name):
				continue
			var m: Dictionary = LOOKS["materials"][source.resource_name]
			var mat := Shooter._gun_material(source, String(m["texture"]), float(m["tile_m"]), m.get("tint", Color.WHITE), m)
			if source.resource_name == "Arm Sleeve" and mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
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
