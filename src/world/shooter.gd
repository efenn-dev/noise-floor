class_name Shooter
extends Node3D
## M14: the gun in your hands. Left-click (outside build mode, gun in hand: Q) fires: the sim uses a round
## and makes the noise (SimWorld.fire), then this raycasts from the camera inside a cone as wide as the
## sim's spread (Gunplay.spread_deg: accuracy, scope, recoil, Firearms), and if it meets a zombie that's a hit
## (SimWorld.shoot_zombie; P2: the ray is the only roll). Right click (hold) with a scope zooms the camera. A hit above the shoulders is a headshot. Shows the gun model
## held in view, a brief muzzle light and a recoil kick on the camera. Sounds come from SoundView, which plays
## the shot's noise event.

const MODELS := {"pistol": "res://assets/models/pistol.glb", "hunting_rifle": "res://assets/models/hunting_rifle.glb"}
## Handheld models are authored with these stable names. Gun Rubber deliberately reuses the fine polymer
## grain (there is no separate rubber photo). V2 review: the models' own colours are near black, which hid
## the texture, so each material's colour is its photo times `tint` (gun steel reads as dark grey steel).
## Any new material name must be mapped or explicitly listed here so test_textured_looks.gd catches it.
const GUN_LOOKS := {
	"materials": {
		"Gun Metal": {"texture": "gun_metal", "tile_m": 0.15, "tint": Color(0.8, 0.8, 0.84), "metallic": 0.5, "roughness": 0.5},
		"Gun Wood": {"texture": "gun_wood", "tile_m": 0.15, "tint": Color(1.0, 0.95, 0.9)},
		"Gun Polymer": {"texture": "gun_polymer", "tile_m": 0.15, "tint": Color(0.85, 0.85, 0.85)},
		"Gun Rubber": {"texture": "gun_polymer", "tile_m": 0.15, "tint": Color(0.5, 0.5, 0.5)},
	},
	"untextured": [],
}
## Where each gun sits in view (camera space): resting at the lower right, pointing ahead.
const HOLD := {"pistol": Vector3(0.2, -0.2, -0.42), "hunting_rifle": Vector3(0.18, -0.2, -0.5)}
const FLASH_TIME := 0.06
const KICK_DEG := {"pistol": 2.0, "hunting_rifle": 5.0}
const KICK_BACK := 12.0  # how fast the kick comes back down, per second
const AIM_FOV := 35.0  # P2: right click (hold) with a scope zooms the camera to this field of view
const ZOOM_SPEED := 400.0  # degrees of field of view a second, zooming in or out
const INSPECT_TIME := 2.4
## V13: this is a measured-looking guess. Tune it to the rig's actual HoldMag palm centre once the arm
## asset lands; the prop remains a child of Hand_L so every wrist correction carries it with the hand.
const MAG_IN_HAND := Transform3D(Basis.IDENTITY, Vector3(0.012, 0.018, -0.012))

## [time, gun position offset, gun rotation degrees, left-hand position in gun space,
## left-hand rotation degrees, rig pose, magazine state]. State changes at its key; transforms smoothstep.
const PISTOL_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
	[0.10, Vector3(0.055, 0.05, 0.03), Vector3(-10, 8, 16), Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Open", "in_gun"],
	[0.18, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.08, -0.15, 0.08), Vector3(-20, -15, -8), "Open", "dropping"],
	[0.30, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.16, -0.48, 0.12), Vector3(-30, 5, -12), "Open", "none"],
	[0.42, Vector3(0.08, 0.08, 0.045), Vector3(-16, 12, 24), Vector3(-0.16, -0.42, 0.08), Vector3(-8, -12, 5), "HoldMag", "in_hand"],
	[0.56, Vector3(0.07, 0.06, 0.03), Vector3(-14, 10, 20), Vector3(-0.045, -0.12, 0.07), Vector3(-12, -22, 2), "HoldMag", "in_hand"],
	[0.64, Vector3(0.07, 0.09, 0.015), Vector3(-18, 10, 20), Vector3(-0.03, -0.035, 0.065), Vector3(-15, -30, 0), "HoldMag", "in_gun"],
	[0.74, Vector3(0.055, 0.06, 0.02), Vector3(-12, 7, 16), Vector3(-0.035, 0.015, -0.03), Vector3(72, -10, -18), "Flat", "in_gun"],
	[0.82, Vector3(0.055, 0.06, 0.10), Vector3(-15, 7, 16), Vector3(-0.035, 0.015, -0.03), Vector3(72, -10, -18), "Flat", "in_gun"],
	[0.90, Vector3(0.03, 0.03, 0.02), Vector3(-6, 3, 8), Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.03, -0.04, 0.065), Vector3(-15, -30, 0), "Grip", "in_gun"],
]
const RIFLE_RELOAD_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
	[0.12, Vector3(0.03, 0.06, 0.02), Vector3(-4, 4, 10), Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Open", "in_gun"],
	[0.24, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.15, -0.48, -0.05), Vector3(30, 5, -15), "Open", "in_gun"],
	[0.34, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.14, -0.38, -0.05), Vector3(15, 10, -8), "Pinch", "in_gun"],
	[0.42, Vector3(0.04, 0.075, 0.03), Vector3(-5, 5, 12), Vector3(-0.04, 0.015, 0.02), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.47, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.51, Vector3(0.04, 0.065, 0.035), Vector3(-4, 5, 12), Vector3(-0.05, 0.005, 0.04), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.56, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.60, Vector3(0.04, 0.065, 0.035), Vector3(-4, 5, 12), Vector3(-0.05, 0.005, 0.04), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.65, Vector3(0.04, 0.09, 0.03), Vector3(-7, 5, 12), Vector3(-0.03, 0.035, 0.015), Vector3(18, -8, -20), "Pinch", "in_gun"],
	[0.72, Vector3(0.04, 0.065, 0.09), Vector3(-5, 5, 12), Vector3(0.035, 0.02, 0.11), Vector3(35, -15, -25), "Pinch", "in_gun"],
	[0.80, Vector3(0.04, 0.065, -0.03), Vector3(-5, 5, 12), Vector3(0.035, 0.02, 0.11), Vector3(35, -15, -25), "Pinch", "in_gun"],
	[0.90, Vector3(0.02, 0.03, 0.0), Vector3(-2, 2, 5), Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
	[1.0, Vector3.ZERO, Vector3.ZERO, Vector3(-0.02, -0.035, -0.17), Vector3(90, 0, 0), "Grip", "in_gun"],
]

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
## Tests set this so a shot goes straight down the middle of the cone.
var no_spread := false
## --aim (screenshots) and tests: hold the scope zoom without a right click.
var hold_aim := false
var hold_reload_at := -1.0  # V13: --reload-at freezes the visible choreography without touching the sim
var hold_inspect_at := -1.0  # V13: --inspect-at does the same for inspection
var base_fov := 75.0
var _aim_held := false

var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}  # base -> Node3D
var feel: ViewFeel  # V3: carries the kick to the camera, shake, hit marker, impact puffs (null when built alone)
var _flash: OmniLight3D
var _flash_time := 0.0
var _kick := 0.0  # radians the camera is tipped up right now
var _message_time := 0.0
var _last_reloading := 0.0
var _reload_total := 0.0
var _inspect_elapsed := -1.0
var _inspect_uid := -1
var _mag_in_hand: Dictionary = {}  # gun base -> the prop parented to Hand_L
var _drop_mag: MeshInstance3D

## Guns with the same authored material share one object-space material across every place they are shown.
static var _material_cache: Dictionary = {}


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude
	base_fov = camera.fov
	_rng.randomize()
	for base: String in MODELS:
		var node: Node3D
		if ResourceLoader.exists(MODELS[base]):
			node = (load(MODELS[base]) as PackedScene).instantiate() as Node3D
		else:  # placeholder until the model exists
			var m := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.05, 0.12, 0.25 if base == "pistol" else 0.9)
			m.mesh = box
			node = m
		node.name = "Gun_" + base
		node.position = HOLD[base]
		node.visible = false
		Hands.attach(node, base, Hands.GUNS)  # V12: hands on the grip and under the barrel
		var left := node.get_node_or_null("Hand_L") as Node3D
		if base == "pistol" and left != null:
			var mag := _make_magazine()
			mag.name = "MagazineInHand"
			mag.transform = MAG_IN_HAND
			mag.visible = false
			left.add_child(mag)
			_mag_in_hand[base] = mag
		apply_textured_materials(node)
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		camera.add_child(node)
		_models[base] = node
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0.2, -0.15, -0.9)
	camera.add_child(_flash)


## Apply the named gun surfaces to any instance (hands now; reusable if a 3-D workbench preview is added).
## Object-space triplanar keeps the grain attached to the moving weapon.
static func apply_textured_materials(node: Node3D) -> void:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for child: Node in meshes:
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not GUN_LOOKS["materials"].has(source.resource_name):
				continue
			var mapping: Dictionary = GUN_LOOKS["materials"][source.resource_name]
			mesh.set_surface_override_material(surface, _gun_material(source, String(mapping["texture"]),
					float(mapping["tile_m"]), mapping.get("tint", Color.WHITE), mapping))


## V2 review: a fully metallic surface takes its colour from reflections, and a dim sky left the pistol black,
## so a mapping may set its own "metallic" and "roughness" (gun steel is satin, not mirror).
static func _gun_material(source: StandardMaterial3D, texture: String, tile_m: float, tint: Color = Color.WHITE,
		mapping: Dictionary = {}) -> StandardMaterial3D:
	var key := "%s|%s|%.3f|%s|%.3f|%.3f" % [source.resource_name, texture, tile_m,
			tint.to_html(), source.metallic, source.roughness]
	if not _material_cache.has(key):
		var mat := source.duplicate() as StandardMaterial3D
		mat.resource_name = source.resource_name
		mat.albedo_color = tint
		mat.metallic = float(mapping.get("metallic", source.metallic))
		mat.roughness = float(mapping.get("roughness", source.roughness))
		mat.albedo_texture = load("res://assets/textures/%s_albedo.jpg" % texture)
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/%s_normal.jpg" % texture)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3.ONE / tile_m
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = mat
	return _material_cache[key]


## V13: pure reload choreography. Position/rotation are offsets from HOLD; the left-hand transform is
## absolute in the gun model's space. Unknown future guns retain the old centred dip.
static func reload_pose(gun_id: String, p: float) -> Dictionary:
	if gun_id == "pistol":
		return _sample_hand_pose(PISTOL_RELOAD_KEYS, p)
	if gun_id == "hunting_rifle":
		return _sample_hand_pose(RIFLE_RELOAD_KEYS, p)
	var rest := _left_rest(gun_id)
	var keys := [
		[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		[0.5, Vector3(0.0, -0.12, 0.0), Vector3(-25, 0, 20), rest[0], rest[1], "Grip", "in_gun"],
		[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
	]
	return _sample_hand_pose(keys, p)


## V13: pure two-sided inspection. A pistol's left hand lets go; a rifle stays held between both hands.
static func inspect_pose(gun_id: String, p: float) -> Dictionary:
	var rest := _left_rest(gun_id)
	var keys: Array
	if gun_id == "pistol":
		keys = [
			[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
			[0.16, Vector3(-0.01, 0.05, 0.10), Vector3(-6, 22, -5), Vector3(-0.17, -0.24, 0.05), Vector3(12, -12, -20), "Open", "in_gun"],
			[0.38, Vector3(-0.04, 0.04, 0.14), Vector3(-8, 48, -10), Vector3(-0.20, -0.28, 0.08), Vector3(15, -5, -25), "Open", "in_gun"],
			[0.58, Vector3(0.02, 0.04, 0.13), Vector3(-5, -40, 35), Vector3(-0.18, -0.27, 0.10), Vector3(8, 12, -18), "Open", "in_gun"],
			[0.78, Vector3(0.01, 0.06, 0.10), Vector3(-32, 5, 15), Vector3(-0.14, -0.22, 0.08), Vector3(4, -8, -12), "Open", "in_gun"],
			[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		]
	else:
		keys = [
			[0.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
			[0.22, Vector3(-0.035, 0.045, 0.10), Vector3(-5, 28, 8), rest[0], rest[1], "Grip", "in_gun"],
			[0.50, Vector3(0.025, 0.05, 0.12), Vector3(-3, -30, -13), rest[0], rest[1], "Grip", "in_gun"],
			[0.76, Vector3(0.0, 0.055, 0.08), Vector3(-18, 0, 5), rest[0], rest[1], "Grip", "in_gun"],
			[1.0, Vector3.ZERO, Vector3.ZERO, rest[0], rest[1], "Grip", "in_gun"],
		]
	return _sample_hand_pose(keys, p)


static func _sample_hand_pose(keys: Array, p: float) -> Dictionary:
	var tt := clampf(p, 0.0, 1.0)
	var state: Array = keys[0]
	for key: Array in keys:
		if float(key[0]) <= tt:
			state = key
	var a: Array = keys[0]
	var b: Array = keys[keys.size() - 1]
	for i in range(1, keys.size()):
		b = keys[i]
		if tt <= float(b[0]):
			a = keys[i - 1]
			break
	var span := maxf(0.0001, float(b[0]) - float(a[0]))
	var u := smoothstep(0.0, 1.0, clampf((tt - float(a[0])) / span, 0.0, 1.0))
	var rotation_deg: Vector3 = (a[2] as Vector3).lerp(b[2], u)
	var left_rotation_deg: Vector3 = (a[4] as Vector3).lerp(b[4], u)
	return {
		"position": (a[1] as Vector3).lerp(b[1], u),
		"rotation": _radians(rotation_deg),
		"left_position": (a[3] as Vector3).lerp(b[3], u),
		"left_rotation": _radians(left_rotation_deg),
		"left_pose": String(state[5]),
		"magazine": String(state[6]),
		"magazine_state": String(state[6]),
	}


static func _left_rest(gun_id: String) -> Array:
	var cfg: Dictionary = Hands.GUNS.get(gun_id, {})
	if not cfg.has("left"):
		return [Vector3.ZERO, Vector3.ZERO]
	var pr: Array = cfg["left"]
	return [pr[0], pr[1]]


static func _radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))


static func _rest_pose(gun_id: String) -> Dictionary:
	var rest := _left_rest(gun_id)
	return {"position": Vector3.ZERO, "rotation": Vector3.ZERO, "left_position": rest[0],
			"left_rotation": _radians(rest[1]), "left_pose": "Grip", "magazine": "in_gun",
			"magazine_state": "in_gun"}


func _apply_left_hand(node: Node3D, pose: Dictionary) -> void:
	var left := node.get_node_or_null("Hand_L") as Node3D
	if left == null:
		return
	Hands.set_target(left, pose["left_position"], pose["left_rotation"])
	Hands.set_pose(left, pose["left_pose"])


static func _make_magazine() -> MeshInstance3D:
	var mag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.12, 0.03)
	mag.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.075, 0.08, 0.09)
	material.metallic = 0.55
	material.roughness = 0.5
	mag.material_override = material
	mag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mag


func _update_magazines(node: Node3D, gun_id: String, pose: Dictionary, reload_p: float) -> void:
	var state: String = pose["magazine"]
	if _mag_in_hand.has(gun_id):
		(_mag_in_hand[gun_id] as MeshInstance3D).visible = state == "in_hand"
	if gun_id != "pistol" or state != "dropping":
		_free_drop_mag()
		return
	if _drop_mag == null:
		_drop_mag = _make_magazine()
		_drop_mag.name = "DroppingMagazine"
		camera.add_child(_drop_mag)
	var fall := smoothstep(0.0, 1.0, clampf((reload_p - 0.18) / 0.12, 0.0, 1.0))
	_drop_mag.transform = node.transform * Transform3D(Basis(), Vector3(0.0, -0.08, 0.07))
	_drop_mag.position += Vector3(0.02 * fall, -0.42 * fall, 0.04 * fall)
	_drop_mag.rotation += Vector3(fall * 1.8, 0.0, fall * 0.7)


func _free_drop_mag() -> void:
	if _drop_mag != null:
		_drop_mag.queue_free()
		_drop_mag = null


func is_inspecting() -> bool:
	return _inspect_elapsed >= 0.0 or hold_inspect_at >= 0.0


func start_inspect() -> bool:
	if not sim.guns.in_hand() or builder.active or sim.player.dead or sim.guns.reloading > 0.0 \
			or sim.guns.raising > 0.0 or aiming():
		return false
	_inspect_elapsed = 0.0
	_inspect_uid = int(sim.gear.gun().get("uid", -1))
	var gun := sim.gear.gun()
	_say("%s%s · %d/%d rounds" % [gun["name"], sim.guns.weapon_condition_text(true), int(gun["loaded"]),
			int(sim.guns.stats()["magazine"])], INSPECT_TIME)
	return true


func cancel_inspect() -> void:
	var was_inspecting := _inspect_elapsed >= 0.0
	_inspect_elapsed = -1.0
	if was_inspecting:
		last_message = ""
		_message_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("aim") and not event.is_echo():
		_aim_held = event.is_pressed() and InputSetup.captured()  # a release always lets go
		if aiming():
			cancel_inspect()
	if not InputSetup.captured() or builder.active:
		return
	if event.is_action_pressed("attack") and sim.guns.in_hand():
		fire()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var base: String = sim.gear.gun().get("base", "")
	var show := sim.guns.in_hand() and not builder.active and not sim.player.dead
	var remaining := sim.guns.reloading
	if remaining > 0.0 and (_last_reloading <= 0.0 or remaining > _last_reloading + 0.001):
		# The parent advances the fixed sim tick before this presentation node. Capture the reload's full
		# skilled duration, not the already-ticked first visible value, and never recalculate it mid-reload.
		_reload_total = maxf(remaining, sim.guns.reload_time())
		cancel_inspect()
	_last_reloading = remaining
	if _inspect_elapsed >= 0.0 and (not show or aiming() or int(sim.gear.gun().get("uid", -1)) != _inspect_uid):
		cancel_inspect()
	var inspect_p := -1.0
	if _inspect_elapsed >= 0.0:
		_inspect_elapsed = minf(INSPECT_TIME, _inspect_elapsed + delta)
		inspect_p = _inspect_elapsed / INSPECT_TIME
		if _inspect_elapsed >= INSPECT_TIME:
			_inspect_elapsed = -1.0
	if hold_inspect_at >= 0.0:
		inspect_p = hold_inspect_at
	var reload_p := hold_reload_at
	if remaining > 0.0:
		reload_p = 1.0 - remaining / maxf(0.001, _reload_total)
	for b: String in _models:
		var node: Node3D = _models[b]
		node.visible = show and b == base
		if node.visible:
			var raise := clampf(sim.guns.raising / maxf(0.01, float(sim.guns.stats()["handling"])), 0.0, 1.0)
			var pose := _rest_pose(b)
			if reload_p >= 0.0:
				pose = reload_pose(b, reload_p)
			elif inspect_p >= 0.0:
				pose = inspect_pose(b, inspect_p)
			node.position = HOLD[b] + pose["position"] + Vector3(0.0, -0.25 * raise, 0.06 * _kick * 10.0)
			node.rotation = pose["rotation"] + Vector3(_kick * 2.0, 0.0, 0.0)
			if feel != null and not aiming():  # V3: bob and sway (held steady while scoped)
				node.position += feel.hold_position_offset()
				node.rotation += feel.hold_rotation_offset()
			_apply_left_hand(node, pose)
			_update_magazines(node, b, pose, reload_p)
			Hands.reaim(node, node.basis)  # V12: through the kick and the reload too
	if reload_p < 0.0:
		_free_drop_mag()
	_flash_time -= delta
	_flash.light_energy = 6.0 if _flash_time > 0.0 else 0.0
	if feel != null:
		feel.kick = _kick  # V3: ViewFeel adds shake and bob and applies it to the camera
	else:
		camera.rotation.x = _kick  # the head holds the look; the camera only carries the kick
	camera.fov = move_toward(camera.fov, AIM_FOV if aiming() else base_fov, ZOOM_SPEED * delta)
	_kick = maxf(0.0, _kick - KICK_BACK * delta * maxf(_kick, 0.02))
	_message_time -= delta
	if _message_time <= 0.0:
		last_message = ""


## True while the scope zoom is on: right click held (or --aim) with a scoped gun in hand, on foot, alive.
## Without a scope right click does nothing. The scope's tighter cone is always on (Gunplay.sight_mult).
func aiming() -> bool:
	return (_aim_held or hold_aim) and sim.guns.scoped() and not builder.active and not sim.player.dead


## Fires if the sim lets it. Returns the id of the zombie the ray met (hit or not), -1 for none, -2 if no shot.
func fire() -> int:
	cancel_inspect()  # V13: pulling the trigger snaps the weapon straight back to its firing hold
	var why := sim.fire()
	if why != "":
		_say(why)
		return -2
	var base: String = sim.gear.gun()["base"]
	_flash_time = FLASH_TIME
	_kick = minf(deg_to_rad(12.0), _kick + deg_to_rad(KICK_DEG.get(base, 2.0)))
	if feel != null:
		feel.fired(base)
	var from := camera.global_position
	var dir := -camera.global_basis.z
	if not no_spread:
		dir = _in_cone(dir, deg_to_rad(sim.guns.spread_deg()))
	var to := from + dir * float(sim.data.guns["ray_range"])
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.BUILT | Layers.ZOMBIE, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] == null or not hit["collider"].has_meta("zombie_id"):
		_say("Missed")
		var fx := "dust"
		if not hit.is_empty() and hit["collider"] != null and hit["collider"].has_meta("piece_key"):  # W2: glass and town doors
			var key: String = hit["collider"].get_meta("piece_key")
			var mat := sim.piece_material(key)
			if sim.player_hit_piece(key, float(sim.guns.stats().get("damage", 30.0)), "bullet") != "":
				fx = "glass" if mat == "glass" else "wood"
		if not hit.is_empty() and feel != null:
			feel.impact(hit["position"], hit["normal"], fx)  # V3: the round kicks up dust where it lands
		return -1
	var body: Node3D = hit["collider"]
	var id: int = body.get_meta("zombie_id")
	var head: bool = hit["position"].y > body.global_position.y + ZombieBody.HEAD_Y
	var r := sim.shoot_zombie(id, head)
	_say("Killed it" if r["killed"] else (("Headshot!" if head else "Hit") if r["hit"] else "Missed"))
	if feel != null and r["hit"]:
		feel.impact(hit["position"], hit["normal"], "blood_head" if head else "blood")
		feel.hit_zombie(r["killed"], head)
	if r["hit"] and head:
		SoundView.play_at(self, "headshot", hit["position"], -2.0, randf_range(0.9, 1.1))  # V7: a headshot reads
	return id


## A random direction within `half_angle` radians of `dir` (uniform over the cone's disc).
func _in_cone(dir: Vector3, half_angle: float) -> Vector3:
	if half_angle <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var r := tan(half_angle) * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	return (dir + side * cos(a) * r + up * sin(a) * r).normalized()


func _say(text: String, seconds: float = 1.0) -> void:
	last_message = text
	_message_time = seconds
