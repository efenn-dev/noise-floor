class_name CarBody
extends VehicleBody3D
## A town car (data/vehicles.json; model assets/models/<type>.glb from tools/art/<type>.py). Godot's
## VehicleBody3D does the physics; the rules (fuel, damage, engine noise) live in the sim's Vehicles,
## which this reports to every physics step while you drive. Parked cars are frozen so zombies can't
## shove them around; wrecks never move.
## VehicleBody3D drives toward +Z, but game models face -Z, so the model is turned round inside the
## body and the sim's yaw is the body's yaw minus half a turn.

const WHEEL_REST := 0.15
const LOOK_YAW := deg_to_rad(110.0)
const LOOK_PITCH := deg_to_rad(60.0)
const RAM_SPEED := 2.5  # m/s: slower bumps don't hurt anyone

var sim: SimWorld
var id := ""
var stats: Dictionary
var size: Vector3
var camera: Camera3D
var driven := false
## Tests (and screenshots) drive from code: set use_device_input = false and fill the wish_* fields.
var use_device_input := true
var wish_throttle := 0.0  # -1 reverse/brake .. 1 forward
var wish_steer := 0.0     # -1 right .. 1 left
var wish_handbrake := false
var mouse_sensitivity := 0.003

var _model: Node3D
var _head: Node3D
var _lights: Array[SpotLight3D] = []
var _hit_cooldown: Dictionary = {}  # zombie id -> seconds until it can be hit again
var _obstacle: NavigationObstacle3D


func setup(p_sim: SimWorld, p_id: String, tint: Color) -> void:
	sim = p_sim
	id = p_id
	var car: Dictionary = sim.vehicles.cars[id]
	stats = sim.vehicles.stats(id)
	size = Vector3(stats["size"][0], stats["size"][1], stats["size"][2])
	set_meta("car_id", id)
	set_meta("container_id", id)  # the interactor treats the back of the car as the trunk
	collision_layer = Layers.WORLD
	collision_mask = Layers.WORLD | Layers.BUILT | Layers.ZOMBIE
	mass = float(stats["mass"])
	can_sleep = false  # a sleeping body ignores the throttle
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	_add_shape()
	_add_model(String(car["type"]), tint, String(car["wreck"]) != "")
	_add_camera()
	_add_lights()
	_add_obstacle()
	place_from_sim()


## Puts the body where the sim says the car is (start of game, after loading a save).
func place_from_sim() -> void:
	var car: Dictionary = sim.vehicles.cars[id]
	position = car["pos"]
	rotation = Vector3(0, float(car["yaw"]) + PI, 0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## The car's facing in the game's convention (front = -Z), as the sim stores it.
func sim_yaw() -> float:
	return wrapf(rotation.y - PI, -PI, PI)


## Forward speed in m/s (negative when reversing).
func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func drive(on: bool) -> void:
	driven = on
	freeze = not on
	camera.current = on
	_head.rotation = Vector3.ZERO
	engine_force = 0.0
	brake = 0.0 if on else float(stats["brake_force"])
	steering = 0.0
	wish_throttle = 0.0
	wish_steer = 0.0
	wish_handbrake = false
	if not on:
		_set_lights(false)


func _physics_process(delta: float) -> void:
	for zid: int in _hit_cooldown.keys():
		_hit_cooldown[zid] -= delta
		if _hit_cooldown[zid] <= 0.0:
			_hit_cooldown.erase(zid)
	if not driven:
		return
	if use_device_input:
		wish_throttle = Input.get_axis("move_back", "move_forward")
		wish_steer = Input.get_axis("move_right", "move_left")
		wish_handbrake = Input.is_action_pressed("jump")
	var running := sim.vehicles.is_running(id)
	var throttle := wish_throttle if running else 0.0
	var fwd := forward_speed()
	var top := float(stats["max_speed"])
	var steer_to := wish_steer * deg_to_rad(float(stats["max_steer_deg"])) * lerpf(1.0, 0.35, clampf(absf(fwd) / top, 0.0, 1.0))
	steering = move_toward(steering, steer_to, delta * 2.0)
	if (throttle < -0.1 and fwd > 1.0) or (throttle > 0.1 and fwd < -1.0):
		engine_force = 0.0  # pressing against the roll means brake
		brake = float(stats["brake_force"])
	else:
		brake = 0.0
		var limit := top if throttle >= 0.0 else top * 0.3
		engine_force = throttle * float(stats["engine_force"]) if absf(fwd) < limit else 0.0
	if wish_handbrake:
		engine_force = 0.0
		brake = float(stats["brake_force"]) * 1.5
	if not running and absf(throttle) < 0.1:
		brake = maxf(brake, float(stats["brake_force"]) * 0.05)  # out of gas: it rolls to a stop
	sim.car_moved(global_position, sim_yaw(), linear_velocity.length())
	_set_lights(bool(sim.vehicles.cars[id]["lights"]))


func _unhandled_input(event: InputEvent) -> void:
	if not driven or not use_device_input:
		return
	if event is InputEventMouseMotion and InputSetup.captured():
		_head.rotation.y = clampf(_head.rotation.y - event.relative.x * mouse_sensitivity, -LOOK_YAW, LOOK_YAW)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * mouse_sensitivity, -LOOK_PITCH, LOOK_PITCH)
	elif event.is_action_pressed("flashlight"):
		toggle_lights()
		get_viewport().set_input_as_handled()


func toggle_lights() -> void:
	var car: Dictionary = sim.vehicles.cars[id]
	car["lights"] = not car["lights"]
	SoundView.play_at(self, "click", camera.global_position, -6.0)


func _set_lights(on: bool) -> void:
	for l in _lights:
		l.visible = on


## Running a zombie over: it takes damage by speed (the sim decides), the car takes a dent.
func _on_body_entered(body: Node) -> void:
	if not driven or not body is ZombieBody:
		return
	var z := body as ZombieBody
	if z.brain == null or _hit_cooldown.has(z.brain.id):
		return
	var speed := linear_velocity.length()
	if speed < RAM_SPEED:
		return
	_hit_cooldown[z.brain.id] = 0.6
	sim.car_hits_zombie(z.brain.id, speed)
	SoundView.play_at(self, "hit_body", z.global_position, 2.0, randf_range(0.8, 0.95))


# --- Building the car ----------------------------------------------------------

func _add_shape() -> void:
	var clearance := size.y * 0.3  # the wheels hang below the body box
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y - clearance, size.z)
	shape.shape = box
	shape.position.y = clearance / 2.0
	add_child(shape)


func _add_model(type: String, tint: Color, wreck: bool) -> void:
	var path := "res://assets/models/%s.glb" % type
	_model = (load(path) as PackedScene).instantiate() as Node3D if ResourceLoader.exists(path) else _placeholder()
	_model.rotation.y = PI  # face the body's +Z, the way VehicleBody3D drives
	add_child(_model)
	var paint := _paint_material(tint * (0.7 if wreck else 1.0))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.1, 0.12, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.4
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s)
			var mat_name := mat.resource_name if mat != null else ""
			if mat_name == "Car Paint":
				mesh.set_surface_override_material(s, paint)
			elif mat_name == "Car Glass":
				mesh.set_surface_override_material(s, glass)
	var flat_done := false
	for w: MeshInstance3D in _model.find_children("Wheel_*", "MeshInstance3D", true, false):
		var at: Vector3 = _model.transform * w.position  # in the body's space
		var wheel := VehicleWheel3D.new()
		wheel.position = at + Vector3(0, WHEEL_REST, 0)  # the suspension mounts above the wheel centre
		wheel.wheel_radius = w.get_aabb().size.y / 2.0
		wheel.wheel_rest_length = WHEEL_REST
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 45.0
		wheel.wheel_friction_slip = 2.5
		wheel.use_as_steering = at.z > 0.0  # front wheels steer
		wheel.use_as_traction = at.z < 0.0  # rear-wheel drive
		add_child(wheel)
		w.get_parent().remove_child(w)
		w.owner = null
		wheel.add_child(w)  # spins and steers with the wheel
		w.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		if wreck and not flat_done:
			w.position.y -= 0.12  # a flat tyre
			flat_done = true
	if wreck:
		_model.rotation.z = 0.03


## A plain box car with four wheels, for when the model hasn't been made (cloud sessions).
func _placeholder() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size * Vector3(1.0, 0.7, 1.0)
	body.mesh = box
	body.position.y = size.y * 0.15
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Car Paint"
	box.material = mat
	root.add_child(body)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.name = "Wheel_%s%s" % ["F" if z < 0 else "R", "L" if x < 0 else "R"]
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.33
			cyl.bottom_radius = 0.33
			cyl.height = 0.25
			w.mesh = cyl
			w.rotation.z = PI / 2.0
			w.position = Vector3(x * (size.x / 2.0 - 0.2), -size.y / 2.0 + 0.33, z * (size.z / 2.0 - 0.8))
			root.add_child(w)
	return root


## Worn car paint, mapped to the car itself (object-space triplanar) so it doesn't slide as the car moves.
func _paint_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.55
	mat.metallic = 0.3
	if ResourceLoader.exists("res://assets/textures/car_paint_albedo.jpg"):
		mat.albedo_texture = load("res://assets/textures/car_paint_albedo.jpg")
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/car_paint_normal.jpg")
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3.ONE * 0.5
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


func _add_camera() -> void:
	var seat: Array = stats["seat"]  # in model space: front -Z, driver on the -X side, height above the ground
	var at := Vector3(-float(seat[0]), float(seat[1]) - size.y / 2.0, -float(seat[2]))
	var pivot := Node3D.new()
	pivot.position = at
	pivot.rotation.y = PI  # cameras look down -Z; the body's front is +Z
	add_child(pivot)
	_head = Node3D.new()
	pivot.add_child(_head)
	pivot.rotation.x = deg_to_rad(-6.0)  # eyes on the road, not the roof
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	_head.add_child(camera)


func _add_lights() -> void:
	for x in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.position = Vector3(x * (size.x / 2.0 - 0.3), -size.y / 2.0 + 0.7, size.z / 2.0 - 0.05)
		l.rotation = Vector3(deg_to_rad(-6.0), PI, 0.0)  # point forward (+Z) and a little down
		l.spot_range = 35.0
		l.spot_angle = 28.0
		l.light_energy = 6.0
		l.light_color = Color(1.0, 0.95, 0.82)
		l.light_volumetric_fog_energy = 1.0
		l.visible = false
		add_child(l)
		_lights.append(l)


## Lets the navmesh treat the car as solid when it's rebaked (after you park), so zombies walk round it.
func _add_obstacle() -> void:
	_obstacle = NavigationObstacle3D.new()
	var hx := size.x / 2.0 + 0.2
	var hz := size.z / 2.0 + 0.2
	_obstacle.vertices = PackedVector3Array([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)])
	_obstacle.height = size.y
	_obstacle.position.y = -size.y / 2.0
	_obstacle.affect_navigation_mesh = true
	_obstacle.carve_navigation_mesh = true
	add_child(_obstacle)
