class_name Melee
extends Node3D
## Left-click (outside build mode) swings the melee weapon in your hands. A hit above a zombie's shoulders
## is a head hit.
## V11 (Sprint 4, Emmitt: "work on the attack animations"): each weapon has its own model (tools/art/
## pipe|bat|axe|machete|knife.py) and each kind of weapon its own swing (weapons.json "style"): a wind-up,
## the strike, a recovery, quicker with the weapon's skill. Whether a swing hits is still decided at the
## click (so the rules and tests are unchanged); what you see and hear of the hit (blood, the marker, the
## shake, the crunch) waits for the strike moment of the animation.

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
var feel: ViewFeel  # V3: bob, sway, hit marker, impact puffs (null in tests that build Melee alone)
var hold_at := -1.0  # V11: >= 0 freezes the swing at that fraction (--swing-at, for screenshots)
var hold_inspect_at := -1.0  # V13: >= 0 freezes inspection there (--inspect-at)
var hold_block := false  # V15: --block holds the guard for screenshots

## Weapon id (weapons.json) -> model. Fists have none.
const MODELS := {"pipe": "res://assets/models/pipe.glb", "bat": "res://assets/models/bat.glb",
		"axe": "res://assets/models/axe.glb", "machete": "res://assets/models/machete.glb",
		"knife": "res://assets/models/knife.glb"}
const PLACEHOLDER_LENGTH := {"pipe": 0.6, "bat": 0.85, "axe": 0.75, "machete": 0.6, "knife": 0.3}
const STYLE_BY_WEAPON := {"pipe": "diagonal", "bat": "side", "axe": "overhead", "machete": "slash",
		"knife": "stab", "fists": "punch"}
const INSPECT_TIME := 2.4
const BLOCK_RAISE_TIME := 0.18
const BLOCK_JOLT_TIME := 0.12
const BLOCK_SWAY_MULT := 0.25
## V15: camera-space guards. Long weapons cross the body; blades turn their edge toward the threat;
## fists bring both hands high. Rotations are degrees here and converted by block_pose().
const BLOCK_POSES := {
	"pipe": [Vector3(0.02, -0.06, -0.42), Vector3(0, 8, 88)],
	"bat": [Vector3(0.02, -0.08, -0.44), Vector3(4, 5, 82)],
	"axe": [Vector3(0.01, -0.05, -0.43), Vector3(-2, 5, 86)],
	"machete": [Vector3(0.03, -0.08, -0.39), Vector3(-18, 4, 62)],
	"knife": [Vector3(0.08, -0.08, -0.35), Vector3(-34, 5, 48)],
	"fists": [Vector3(0.17, -0.08, -0.34), Vector3(-5, 0, 8)],
}
const FIST_LEFT_REST := [Vector3(-0.21, -0.21, -0.5), Vector3(-15, 0, -10)]
const FIST_LEFT_BLOCK := [Vector3(-0.17, -0.09, -0.35), Vector3(-5, 0, -8)]
## Weapon materials by name, drawn with the gun and cloth photos (Shooter._gun_material does the work).
const WEAPON_LOOKS := {
	"materials": {
		"Weapon Metal": {"texture": "gun_metal", "tile_m": 0.2, "tint": Color(0.72, 0.66, 0.6), "metallic": 0.5, "roughness": 0.6},
		"Weapon Wood": {"texture": "gun_wood", "tile_m": 0.25, "tint": Color(1.0, 0.9, 0.78)},
		"Weapon Grip": {"texture": "cloth_cotton", "tile_m": 0.08, "tint": Color(0.36, 0.34, 0.31), "metallic": 0.0, "roughness": 0.95},
		"Weapon Edge": {"texture": "gun_metal", "tile_m": 0.1, "tint": Color(1.0, 1.0, 1.0), "metallic": 0.8, "roughness": 0.25},
	},
	"untextured": [],
}
## The weapon points up its local +Y from the grip at the origin, its striking side toward -Z.
## Each style: total seconds at the weapon's own swing speed, the strike moment (0-1), and keyframes of
## [t, position, rotation in degrees] in camera space; t = 0 and t = 1 are the resting pose.
const STYLES := {
	"diagonal": {"time": 0.32, "strike": 0.48, "keys": [
		[0.0, Vector3(0.3, -0.34, -0.5), Vector3(-58, 0, 28)],
		[0.34, Vector3(0.42, -0.12, -0.42), Vector3(15, 10, -35)],
		[0.52, Vector3(-0.06, -0.4, -0.7), Vector3(-95, 0, 50)],
		[1.0, Vector3(0.3, -0.34, -0.5), Vector3(-58, 0, 28)]]},
	"side": {"time": 0.36, "strike": 0.5, "keys": [
		[0.0, Vector3(0.32, -0.36, -0.5), Vector3(-55, 0, 25)],
		[0.34, Vector3(0.55, -0.22, -0.32), Vector3(-15, 55, -70)],
		[0.54, Vector3(-0.3, -0.24, -0.66), Vector3(-15, -45, -80)],
		[1.0, Vector3(0.32, -0.36, -0.5), Vector3(-55, 0, 25)]]},
	"overhead": {"time": 0.45, "strike": 0.55, "keys": [
		[0.0, Vector3(0.28, -0.38, -0.5), Vector3(-52, 0, 22)],
		[0.38, Vector3(0.18, 0.12, -0.34), Vector3(40, 0, -5)],
		[0.58, Vector3(0.06, -0.48, -0.68), Vector3(-105, 0, 5)],
		[1.0, Vector3(0.28, -0.38, -0.5), Vector3(-52, 0, 22)]]},
	"slash": {"time": 0.26, "strike": 0.45, "keys": [
		[0.0, Vector3(0.3, -0.33, -0.48), Vector3(-55, 0, 25)],
		[0.3, Vector3(0.4, -0.18, -0.42), Vector3(5, 15, -45)],
		[0.5, Vector3(-0.14, -0.34, -0.68), Vector3(-85, -10, 65)],
		[1.0, Vector3(0.3, -0.33, -0.48), Vector3(-55, 0, 25)]]},
	"stab": {"time": 0.22, "strike": 0.45, "keys": [
		[0.0, Vector3(0.24, -0.3, -0.45), Vector3(-80, 0, -10)],
		[0.3, Vector3(0.26, -0.28, -0.34), Vector3(-85, 0, -5)],
		[0.48, Vector3(0.14, -0.24, -0.68), Vector3(-90, 0, 0)],
		[1.0, Vector3(0.24, -0.3, -0.45), Vector3(-80, 0, -10)]]},
	# V12: bare fists: the right fist's pivot jabs forward from a raised guard (the left fist holds the guard).
	"punch": {"time": 0.24, "strike": 0.42, "keys": [
		[0.0, Vector3(0.2, -0.19, -0.45), Vector3(-15, 0, 10)],
		[0.18, Vector3(0.22, -0.18, -0.39), Vector3(-10, 0, 12)],
		[0.42, Vector3(0.07, -0.12, -0.76), Vector3(-25, 0, 0)],
		[1.0, Vector3(0.2, -0.19, -0.45), Vector3(-15, 0, 10)]]},
}

var _models: Dictionary = {}  # weapon id -> Node3D under the camera
var _fists: Node3D  # V12: bare hands in a guard; "R" (the jabbing fist's pivot) and "L"
var _swing := 1.0  # 0 -> 1 over one swing animation
var _swing_time := 0.32
var _style := "diagonal"
var _pending: Array = []  # V11: hit feedback waiting for the strike: {at: seconds left, ...}
var _message_time := 0.0
var _inspect_elapsed := -1.0
var _inspect_weapon := ""
var _block_held := false
var _block_weight := 0.0
var _block_jolt := 0.0
var _seen_blocks: Array = []


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude
	for id: String in MODELS:
		var node: Node3D
		if ResourceLoader.exists(MODELS[id]):
			node = (load(MODELS[id]) as PackedScene).instantiate() as Node3D
			apply_weapon_materials(node)
		else:  # placeholder until the model exists: a plain rod of the right length, grip at the origin
			var m := MeshInstance3D.new()
			var rod := CylinderMesh.new()
			rod.top_radius = 0.022
			rod.bottom_radius = 0.022
			rod.height = PLACEHOLDER_LENGTH[id]
			m.mesh = rod
			m.position.y = rod.height * 0.35
			node = Node3D.new()
			node.add_child(m)
		node.name = "Weapon_" + id
		node.visible = false
		var rest: Array = pose_at(String(sim.data.weapons.get(id, {}).get("style", "diagonal")), 0.0)
		Hands.attach(node, id, Hands.MELEE, Basis.from_euler(rest[1]))  # V12: gloved hands on the grip, so they swing with it
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no flashlight shadow across the view
		camera.add_child(node)
		_models[id] = node
	_fists = make_fists()
	camera.add_child(_fists)
	_pose(1.0)


## V12: two gloved fists in a raised guard. The right fist sits in a pivot ("R") that the punch style moves;
## the left ("L") holds still. Each fist is rolled so its forearm runs off the bottom of the screen.
static func make_fists() -> Node3D:
	var root := Node3D.new()
	root.name = "Fists"
	root.visible = false
	var guard := {"R": [Vector3(0.2, -0.19, -0.45), Vector3(-15, 0, 10), "right"],
			"L": [Vector3(-0.21, -0.21, -0.5), Vector3(-15, 0, -10), "left"]}
	for pivot_name: String in guard:
		var g: Array = guard[pivot_name]
		var pivot := Node3D.new()
		pivot.name = pivot_name
		pivot.position = g[0]
		pivot.rotation = Vector3(deg_to_rad(g[1].x), deg_to_rad(g[1].y), deg_to_rad(g[1].z))
		var hand := Hands.make(g[2])
		hand.name = "Hand_R" if g[2] == "right" else "Hand_L"
		var base := Basis(Vector3.RIGHT, deg_to_rad(8.0))  # upright, like a boxing guard: the back of the fist toward you
		hand.set_meta("base", base)
		hand.set_meta("side", g[2])
		hand.basis = Hands.hand_basis(base, Hands.best_roll(base, pivot.basis, Hands.ARM_DIR[g[2]].normalized()))
		pivot.add_child(hand)
		Hands.set_pose(hand, "Fist")
		root.add_child(pivot)
	return root


## Textures a weapon model's materials by name (WEAPON_LOOKS), like the guns'.
static func apply_weapon_materials(node: Node3D) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null or not WEAPON_LOOKS["materials"].has(source.resource_name):
				continue
			var m: Dictionary = WEAPON_LOOKS["materials"][source.resource_name]
			mesh.set_surface_override_material(i, Shooter._gun_material(source, String(m["texture"]), float(m["tile_m"]),
					m.get("tint", Color.WHITE), m))


## The weapon id (weapons.json) in your hands, "" bare-handed.
func weapon_id() -> String:
	if not sim.gear.equipped.has("weapon"):
		return ""
	return String(sim.gear.base_of(sim.gear.equipped["weapon"])["weapon"])


## The swing style of the weapon in your hands.
func style() -> String:
	var id := weapon_id()
	var w: Dictionary = sim.data.weapons.get(id if id != "" else "fists", {})
	var s := String(w.get("style", "diagonal"))
	return s if STYLES.has(s) else "diagonal"


## Seconds one swing animation takes: the style's, sped up by the weapon's skill like the swing itself.
func swing_seconds() -> float:
	var id := weapon_id()
	var base_cd := float(sim.data.weapons.get(id if id != "" else "fists", {}).get("cooldown", 0.7))
	var k := sim.swing_cooldown() / maxf(0.01, base_cd)
	return float(STYLES[style()]["time"]) * k


## [position, rotation in radians] of a style's keyframes at fraction t (smooth between keys).
static func pose_at(style_id: String, t: float) -> Array:
	var keys: Array = STYLES[style_id]["keys"]
	var tt := clampf(t, 0.0, 1.0)
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if tt <= float(b[0]) or i == keys.size() - 1:
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var u := smoothstep(0.0, 1.0, clampf((tt - float(a[0])) / span, 0.0, 1.0))
			var rot: Vector3 = (a[2] as Vector3).lerp(b[2], u)
			return [(a[1] as Vector3).lerp(b[1], u), Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))]
	return [keys[0][1], keys[0][2]]


## V13: pure inspection pose in camera space. Every melee weapon starts and ends at its own exact rest;
## between them it comes closer, shows both sides, then tips so the player can look along the blade/head.
static func inspect_pose(weapon_id: String, p: float) -> Dictionary:
	var style_id: String = STYLE_BY_WEAPON.get(weapon_id if weapon_id != "" else "fists", "diagonal")
	var rest: Array = pose_at(style_id, 0.0)
	var keys := [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.20, Vector3(-0.05, 0.08, 0.11), Vector3(-12, 50, -12)],
		[0.48, Vector3(0.035, 0.10, 0.14), Vector3(8, -62, 38)],
		[0.74, Vector3(-0.015, 0.10, 0.09), Vector3(-30, 8, 12)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]
	var offset := _inspect_offset(keys, p)
	return {"position": (rest[0] as Vector3) + offset[0], "rotation": (rest[1] as Vector3) + offset[1]}


## V15: pure full guard pose for the held weapon ("" means fists).
static func block_pose(weapon_id: String) -> Dictionary:
	var id := weapon_id if weapon_id != "" else "fists"
	var p: Array = BLOCK_POSES[id]
	return {"position": p[0] as Vector3, "rotation": Shooter._radians(p[1] as Vector3)}


static func _inspect_offset(keys: Array, p: float) -> Array:
	var tt := clampf(p, 0.0, 1.0)
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if tt <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var u := smoothstep(0.0, 1.0, clampf((tt - float(a[0])) / span, 0.0, 1.0))
			var pos: Vector3 = (a[1] as Vector3).lerp(b[1], u)
			var degrees: Vector3 = (a[2] as Vector3).lerp(b[2], u)
			return [pos, Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))]
	return [Vector3.ZERO, Vector3.ZERO]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("aim") and not event.is_echo():
		_block_held = event.is_pressed() and InputSetup.captured() and sim.ready_throw == ""
		if _block_held and not sim.guns.in_hand():
			cancel_inspect()
	if event.is_action_pressed("attack") and InputSetup.captured() and not builder.active and not sim.guns.in_hand() \
			and sim.ready_throw == "":
		swing()


func _process(delta: float) -> void:
	var id := weapon_id()
	var show := not builder.active and not sim.player.dead and id != "" and not sim.guns.in_hand() \
			and sim.ready_throw == ""  # M14/V30: not while a gun or throwable is out
	if _inspect_elapsed >= 0.0 and (builder.active or sim.player.dead or sim.guns.in_hand() or id != _inspect_weapon):
		cancel_inspect()
	var inspect_p := -1.0
	if _inspect_elapsed >= 0.0:
		_inspect_elapsed = minf(INSPECT_TIME, _inspect_elapsed + delta)
		inspect_p = _inspect_elapsed / INSPECT_TIME
		if _inspect_elapsed >= INSPECT_TIME:
			_inspect_elapsed = -1.0
	if hold_inspect_at >= 0.0:
		inspect_p = hold_inspect_at
	_block_weight = move_toward(_block_weight, 1.0 if blocking() else 0.0, delta / BLOCK_RAISE_TIME)
	_note_block_feedback()
	_block_jolt = maxf(0.0, _block_jolt - delta)
	if _fists != null:  # V12: bare-handed, the fists show
		_fists.visible = not builder.active and not sim.player.dead and id == "" and not sim.guns.in_hand() \
				and sim.ready_throw == ""
	for w: String in _models:
		_models[w].visible = show and w == id
	_swing = hold_at if hold_at >= 0.0 else minf(1.0, _swing + delta / maxf(0.05, _swing_time))
	_pose(_swing, inspect_p)
	for p: Dictionary in _pending:
		p["at"] -= delta
	while not _pending.is_empty() and _pending[0]["at"] <= 0.0:
		_land(_pending.pop_front())
	_message_time -= delta
	if _message_time <= 0.0:
		last_message = ""


## Swings if ready. Returns the id of the zombie hit, -1 for a miss, -2 if the swing wasn't ready.
func swing() -> int:
	if blocking():
		return -2
	cancel_inspect()  # V13: an attack returns to the combat pose immediately
	if not sim.swing():
		return -2
	_style = style()
	_swing_time = swing_seconds()
	_swing = 0.0
	var strike_in := _swing_time * float(STYLES[_style]["strike"])
	SoundView.play_at(self, "swing", camera.global_position, -8.0, randf_range(0.9, 1.1))
	var from := camera.global_position
	var to := from - camera.global_basis.z * float(sim.weapon_stats()["range"])
	# V33: the swing finds the zone it lands in; one that touches a body but slips between zones still hits.
	var hit := ZombieHitboxes.cast(get_world_3d().direct_space_state, from, to, exclude, true)
	if hit.is_empty() or int(hit["zombie_id"]) < 0:
		if not hit.is_empty():  # V3: a swing into a wall puffs dust and jars the view (at the strike)
			var fx := "dust"
			var col: Object = hit["collider"]
			if col != null and col.has_meta("piece_key"):  # W2: windows shatter, town doors splinter
				var mat := sim.piece_material(col.get_meta("piece_key"))
				if sim.player_hit_piece(col.get_meta("piece_key"), sim.melee_damage(), sim.gear.weapon_class()) != "":
					fx = "glass" if mat == "glass" else "wood"
			_pending.append({"at": strike_in, "kind": "wall", "fx": fx, "pos": hit["position"], "normal": hit["normal"]})
		return -1
	var id: int = hit["zombie_id"]
	var zone: String = hit["zone"]
	var head := zone == "head"
	var killed := sim.hit_zombie(id, zone)
	last_message = "Killed it" if killed else Shooter.ZONE_WORDS.get(zone, "Hit")
	_message_time = 1.0
	_pending.append({"at": strike_in, "kind": "zombie", "pos": hit["position"], "normal": hit["normal"],
			"killed": killed, "head": head})
	return id


## What you see and hear of a hit, at the strike moment of the swing.
func _land(p: Dictionary) -> void:
	if p["kind"] == "wall":
		if feel != null:
			feel.impact(p["pos"], p["normal"], p.get("fx", "dust"))
			feel.add_trauma(ViewFeel.TRAUMA_MELEE_WALL)
		return
	if feel != null:
		feel.impact(p["pos"], p["normal"], "blood_head" if p["head"] else "blood")
		feel.hit_zombie(p["killed"], p["head"])
		feel.add_trauma(ViewFeel.TRAUMA_MELEE_HIT)
	if p["head"]:
		SoundView.play_at(self, "headshot", p["pos"], -4.0, randf_range(0.9, 1.1))  # V7: a head hit reads


## The weapon's place in view: the style's pose at swing fraction t, plus bob and sway.
func _pose(t: float, inspect_p: float = -1.0) -> void:
	var id := weapon_id()
	if id == "" and _fists != null:  # V12: the right fist jabs; both bob and sway
		var fist := _fists.get_node("R") as Node3D
		var left := _fists.get_node("L") as Node3D
		if inspect_p >= 0.0:
			var inspect := inspect_pose("fists", inspect_p)
			fist.position = inspect["position"]
			fist.rotation = inspect["rotation"]
		else:
			var fp: Array = pose_at("punch", t)
			fist.position = fp[0]
			fist.rotation = fp[1]
		if _block_weight > 0.0:
			var guard: Dictionary = block_pose("")
			fist.position = fist.position.lerp(guard["position"] as Vector3, _block_weight)
			fist.rotation = fist.rotation.lerp(guard["rotation"] as Vector3, _block_weight)
		var left_rest_rotation := Shooter._radians(FIST_LEFT_REST[1] as Vector3)
		var left_block_rotation := Shooter._radians(FIST_LEFT_BLOCK[1] as Vector3)
		left.position = (FIST_LEFT_REST[0] as Vector3).lerp(FIST_LEFT_BLOCK[0] as Vector3, _block_weight)
		left.rotation = left_rest_rotation.lerp(left_block_rotation, _block_weight)
		Hands.reaim(fist, fist.basis)
		Hands.reaim(left, left.basis)
		var move_scale := lerpf(1.0, BLOCK_SWAY_MULT, _block_weight)
		_fists.position = feel.hold_position_offset() * move_scale if feel != null else Vector3.ZERO
		_fists.rotation = feel.hold_rotation_offset() * move_scale if feel != null else Vector3.ZERO
		_fists.position.z += 0.045 * _block_jolt / BLOCK_JOLT_TIME
		return
	if id == "" or not _models.has(id):
		return
	var node: Node3D = _models[id]
	if inspect_p >= 0.0:
		var inspect := inspect_pose(id, inspect_p)
		node.position = inspect["position"]
		node.rotation = inspect["rotation"]
	else:
		var pr: Array = pose_at(_style if _swing < 1.0 and hold_at < 0.0 else style(), t)
		node.position = pr[0]
		node.rotation = pr[1]
	if _block_weight > 0.0:
		var guard: Dictionary = block_pose(id)
		node.position = node.position.lerp(guard["position"] as Vector3, _block_weight)
		node.rotation = node.rotation.lerp(guard["rotation"] as Vector3, _block_weight)
	if feel != null:  # V3: the weapon bobs with your steps and lags the mouse
		var move_scale := lerpf(1.0, BLOCK_SWAY_MULT, _block_weight)
		node.position += feel.hold_position_offset() * move_scale
		node.rotation += feel.hold_rotation_offset() * move_scale
	node.position.z += 0.045 * _block_jolt / BLOCK_JOLT_TIME
	Hands.reaim(node, node.basis)  # V12: forearms keep running off the bottom of the screen through the swing


## V15: right click guards with melee or fists. A running swing finishes before a guard can come up.
func blocking() -> bool:
	return (_block_held or hold_block) and not sim.guns.in_hand() and not builder.active and not sim.player.dead \
			and not sim.player.asleep and _swing >= 1.0 and not is_inspecting()


## A successful sim block emits one "block" noise. That same event drives the thud, camera bump and hands.
func _note_block_feedback() -> void:
	for event: Dictionary in sim.noise.recent:
		if event.get("kind", "") != "block" or _seen_event(_seen_blocks, event):
			continue
		_block_jolt = BLOCK_JOLT_TIME
		if feel != null:
			feel.add_trauma(ViewFeel.TRAUMA_BLOCK)
	_seen_blocks = sim.noise.recent.duplicate()


static func _seen_event(events: Array, event: Dictionary) -> bool:
	for other: Dictionary in events:
		if is_same(other, event):
			return true
	return false


func is_inspecting() -> bool:
	return _inspect_elapsed >= 0.0 or hold_inspect_at >= 0.0


func start_inspect() -> bool:
	if sim.guns.in_hand() or builder.active or sim.player.dead or _swing < 1.0:
		return false
	_inspect_elapsed = 0.0
	_inspect_weapon = weapon_id()
	if _inspect_weapon == "":
		last_message = "Fists"
	else:
		var weapon_node: Node3D = _models.get(_inspect_weapon) as Node3D
		if is_inside_tree():  # tests build Shooter/Melee alone, with no camera
			var sound_pos := weapon_node.global_position if weapon_node != null else camera.global_position
			SoundView.play_at(self, "blade_handle", sound_pos, -3.0, randf_range(0.95, 1.05))  # V16: handling only, no sim noise
		var piece: Dictionary = sim.gear.equipped["weapon"]
		last_message = "%s · %s" % [piece["name"], sim.gear.condition_text(piece)]
	_message_time = INSPECT_TIME
	return true


func cancel_inspect() -> void:
	var was_inspecting := _inspect_elapsed >= 0.0
	_inspect_elapsed = -1.0
	if was_inspecting:
		last_message = ""
		_message_time = 0.0
