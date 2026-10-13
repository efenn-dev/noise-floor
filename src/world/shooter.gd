class_name Shooter
extends Node3D
## M14: the gun in your hands. Left-click (outside build mode, gun in hand: Q) fires: the sim uses a round
## and makes the noise (SimWorld.fire), then this raycasts from the camera inside a cone as wide as the
## sim's spread (Gunplay.spread_deg: accuracy, recoil, Firearms), and if it meets a zombie the sim decides
## the hit (SimWorld.shoot_zombie, by distance). A hit above the shoulders is a headshot. Shows the gun model
## held in view, a brief muzzle light and a recoil kick on the camera. Sounds come from SoundView, which plays
## the shot's noise event.

const MODELS := {"pistol": "res://assets/models/pistol.glb", "hunting_rifle": "res://assets/models/hunting_rifle.glb"}
## Where each gun sits in view (camera space): resting at the lower right, pointing ahead.
const HOLD := {"pistol": Vector3(0.2, -0.2, -0.42), "hunting_rifle": Vector3(0.18, -0.2, -0.5)}
const FLASH_TIME := 0.06
const KICK_DEG := {"pistol": 2.0, "hunting_rifle": 5.0}
const KICK_BACK := 12.0  # how fast the kick comes back down, per second

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var exclude: Array[RID] = []
var last_message := ""
## Tests set this so a shot goes straight down the middle of the cone.
var no_spread := false

var _rng := RandomNumberGenerator.new()
var _models: Dictionary = {}  # base -> Node3D
var _flash: OmniLight3D
var _flash_time := 0.0
var _kick := 0.0  # radians the camera is tipped up right now
var _message_time := 0.0


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController, p_exclude: Array[RID]) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	exclude = p_exclude
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


func _unhandled_input(event: InputEvent) -> void:
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
	_flash_time -= delta
	_flash.light_energy = 6.0 if _flash_time > 0.0 else 0.0
	camera.rotation.x = _kick  # the head holds the look; the camera only carries the kick
	_kick = maxf(0.0, _kick - KICK_BACK * delta * maxf(_kick, 0.02))
	_message_time -= delta
	if _message_time <= 0.0:
		last_message = ""


## Fires if the sim lets it. Returns the id of the zombie the ray met (hit or not), -1 for none, -2 if no shot.
func fire() -> int:
	var why := sim.fire()
	if why != "":
		_say(why)
		return -2
	var base: String = sim.gear.gun()["base"]
	_flash_time = FLASH_TIME
	_kick = minf(deg_to_rad(12.0), _kick + deg_to_rad(KICK_DEG.get(base, 2.0)))
	var from := camera.global_position
	var dir := -camera.global_basis.z
	if not no_spread:
		dir = _in_cone(dir, deg_to_rad(sim.guns.spread_deg()))
	var to := from + dir * float(sim.data.guns["ray_range"])
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.BUILT | Layers.ZOMBIE, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] == null or not hit["collider"].has_meta("zombie_id"):
		_say("Missed")
		return -1
	var body: Node3D = hit["collider"]
	var id: int = body.get_meta("zombie_id")
	var head: bool = hit["position"].y > body.global_position.y + ZombieBody.HEAD_Y
	var r := sim.shoot_zombie(id, head, from.distance_to(hit["position"]))
	_say("Killed it" if r["killed"] else (("Headshot!" if head else "Hit") if r["hit"] else "Missed"))
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
