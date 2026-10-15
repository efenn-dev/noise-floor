class_name Thrower
extends Node3D
## V30: presentation/input for sim-owned throwables and bolts. SimWorld owns charge velocity, trajectory,
## bounces, fuse, blast and hits; this node mirrors those dictionaries and draws the same predicted arc.

const MODELS := {
	"pipe_bomb": "res://assets/models/pipe_bomb.glb",
	"bottle": "res://assets/models/bottle.glb",
}
const HOLD := {
	"pipe_bomb": Vector3(0.22, -0.24, -0.43),
	"bottle": Vector3(0.23, -0.27, -0.46),
}
const MAX_CHARGE_TIME := 1.15
const DEFAULT_PREVIEW_CHARGE := 0.65

var sim: SimWorld
var camera: Camera3D
var builder: BuildController
var feel: ViewFeel
var hold_preview := false
var _models: Dictionary = {}
var _flying: Dictionary = {}  # sim projectile id -> view node
var _pickups: Dictionary = {}  # container id -> StaticBody3D
var _arc: MeshInstance3D
var _charging := false
var _charge_time := 0.0
var _seen_events: Dictionary = {}


func setup(p_sim: SimWorld, p_camera: Camera3D, p_builder: BuildController) -> void:
	sim = p_sim
	camera = p_camera
	builder = p_builder
	for item: String in MODELS:
		var node := _model(item)
		node.name = "Held_" + item
		node.position = HOLD[item]
		node.visible = false
		Hands.attach(node, item, Hands.THROWABLES)
		camera.add_child(node)
		_models[item] = node
	_arc = MeshInstance3D.new()
	_arc.name = "ThrowArcPreview"
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc)


func ready(item: String) -> String:
	var message := sim.ready_throwable(item)
	if sim.ready_throw != "":
		hold_preview = true
	return message


func cancel() -> void:
	_charging = false
	_charge_time = 0.0
	hold_preview = false
	sim.cancel_throwable()


func charge() -> float:
	return clampf(_charge_time / MAX_CHARGE_TIME, 0.0, 1.0) if _charging else DEFAULT_PREVIEW_CHARGE


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or sim.ready_throw == "" or builder.active or not InputSetup.captured():
		return
	if event.is_action_pressed("aim"):
		cancel()
		sim.add_message("Throw cancelled", 1.5)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("attack"):
		_charging = true
		_charge_time = 0.0
		hold_preview = true
		get_viewport().set_input_as_handled()
	elif event.is_action_released("attack") and _charging:
		throw_now()
		get_viewport().set_input_as_handled()


func throw_now() -> void:
	if sim.ready_throw == "":
		return
	var direction := -camera.global_basis.z
	var origin := camera.global_position + direction * 0.42 + Vector3.DOWN * 0.12
	var message := sim.throw_ready_item(origin, SimWorld.throw_velocity(direction, charge()))
	if message != "":
		sim.add_message(message, 2.0)
	_charging = false
	_charge_time = 0.0
	hold_preview = false


func _process(delta: float) -> void:
	if sim == null:
		return
	if _charging:
		_charge_time = minf(MAX_CHARGE_TIME, _charge_time + delta)
	var show := sim.ready_throw != "" and not builder.active and not sim.player.dead
	for item: String in _models:
		var node: Node3D = _models[item]
		node.visible = show and sim.ready_throw == item
		if node.visible:
			var windup := smoothstep(0.0, 1.0, charge())
			node.position = HOLD[item] + Vector3(0.06, -0.03, 0.08) * windup
			node.rotation_degrees = Vector3(-12.0 * windup, 10.0 * windup, 5.0 * windup)
			Hands.reaim(node, node.basis)
	_draw_arc(show and (_charging or hold_preview))
	_sync_projectiles()
	_sync_pickups()
	_play_events()


func _draw_arc(visible_now: bool) -> void:
	_arc.visible = visible_now
	if not visible_now:
		return
	var direction := -camera.global_basis.z
	var origin := camera.global_position + direction * 0.42 + Vector3.DOWN * 0.12
	var points := SimWorld.predict_throw_arc(origin, SimWorld.throw_velocity(direction, charge()))
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.72, 0.22, 0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for point: Vector3 in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_arc.mesh = mesh


func _sync_projectiles() -> void:
	var live := {}
	for bolt: Dictionary in sim.projectiles:
		var id := int(bolt["id"])
		live[id] = true
		if not _flying.has(id):
			_flying[id] = _bolt_model()
			add_child(_flying[id])
		var node: Node3D = _flying[id]
		node.global_position = bolt["pos"]
		var velocity: Vector3 = bolt["velocity"]
		if velocity.length() > 0.05:
			node.look_at(node.global_position + velocity, Vector3.UP)
	for body: Dictionary in sim.thrown:
		var id := int(body["id"])
		live[id] = true
		if not _flying.has(id):
			_flying[id] = _model(str(body["item"]))
			add_child(_flying[id])
		var node: Node3D = _flying[id]
		node.global_position = body["pos"]
		node.rotate_x(0.18)
		node.rotate_z(0.11)
	for id: int in _flying.keys():
		if not live.has(id):
			(_flying[id] as Node).queue_free()
			_flying.erase(id)


func _sync_pickups() -> void:
	for container_id: String in sim.projectile_pickups:
		if not sim.loot.containers.has(container_id) or _pickups.has(container_id):
			continue
		var body := StaticBody3D.new()
		body.name = "RecoveredBolt"
		body.collision_layer = Layers.BAG
		body.collision_mask = 0
		body.set_meta("container_id", container_id)
		body.position = sim.projectile_pickups[container_id]
		body.add_child(_bolt_model())
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.12, 0.12, 0.55)
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		_pickups[container_id] = body
	for container_id: String in _pickups.keys():
		if not sim.loot.containers.has(container_id) or sim.loot.inventory(container_id).count("bolt") <= 0:
			(_pickups[container_id] as Node).queue_free()
			_pickups.erase(container_id)


func _play_events() -> void:
	for event: Dictionary in sim.projectile_events:
		var key := "%s:%d:%s" % [event["type"], int(event.get("tick", 0)), event["pos"]]
		if _seen_events.has(key):
			continue
		_seen_events[key] = true
		var pos: Vector3 = event["pos"]
		match String(event["type"]):
			"bottle_break":
				ImpactFx.spawn(self, pos, Vector3.UP, "glass")
			"bolt_hit":
				ImpactFx.spawn(self, pos, Vector3.UP, "blood")
			"bolt_land", "bounce":
				ImpactFx.spawn(self, pos, Vector3.UP, "dust")
			"explosion":
				ImpactFx.spawn(self, pos, Vector3.UP, "dust")
				ImpactFx.spawn(self, pos, Vector3.UP, "wood")
				if feel != null:
					feel.add_trauma(clampf(0.85 * (1.0 - camera.global_position.distance_to(pos) / 28.0), 0.0, 0.85))
				_flash(pos)


func _flash(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.18)
	light.light_energy = 18.0
	light.omni_range = 8.0
	add_child(light)
	light.global_position = pos
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.18)
	tween.tween_callback(light.queue_free)


func _model(item: String) -> Node3D:
	var path := String(MODELS.get(item, ""))
	var node: Node3D
	if path != "" and ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as Node3D
	else:
		var fallback := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.045
		capsule.height = 0.28
		fallback.mesh = capsule
		node = fallback
	Shooter.apply_textured_materials(node)
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _bolt_model() -> Node3D:
	var root := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.006
	cylinder.bottom_radius = 0.006
	cylinder.height = 0.55
	shaft.mesh = cylinder
	shaft.rotation_degrees.x = 90.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.22, 0.11)
	material.roughness = 0.85
	shaft.material_override = material
	root.add_child(shaft)
	return root
