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

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
## Tests set this so a shot goes straight down the middle of the cone.
var no_spread := false
## --aim (screenshots) and tests: hold the scope zoom without a right click.
var hold_aim := false
var base_fov := 75.0
var _aim_held := false

var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}  # base -> Node3D
var feel: ViewFeel  # V3: carries the kick to the camera, shake, hit marker, impact puffs (null when built alone)
var _flash: OmniLight3D
var _flash_time := 0.0
var _kick := 0.0  # radians the camera is tipped up right now
var _message_time := 0.0

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("aim") and not event.is_echo():
		_aim_held = event.is_pressed() and InputSetup.captured()  # a release always lets go
	if not InputSetup.captured() or builder.active:
		return
	if event.is_action_pressed("attack") and sim.guns.in_hand():
		fire()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var base: String = sim.gear.gun().get("base", "")
	var show := sim.guns.in_hand() and not builder.active and not sim.player.dead
	for b: String in _models:
		var node: Node3D = _models[b]
		node.visible = show and b == base
		if node.visible:
			var raise := clampf(sim.guns.raising / maxf(0.01, float(sim.guns.stats()["handling"])), 0.0, 1.0)
			var reload := 1.0 if sim.guns.reloading > 0.0 else 0.0
			node.position = HOLD[b] + Vector3(0.0, -0.25 * raise - 0.12 * reload, 0.06 * _kick * 10.0)
			node.rotation = Vector3(_kick * 2.0 - deg_to_rad(25.0) * reload, 0.0, deg_to_rad(20.0) * reload)
			if feel != null and not aiming():  # V3: bob and sway (held steady while scoped)
				node.position += feel.hold_position_offset()
				node.rotation += feel.hold_rotation_offset()
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


func _say(text: String) -> void:
	last_message = text
	_message_time = 1.0
