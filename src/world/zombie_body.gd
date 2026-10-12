class_name ZombieBody
extends CharacterBody3D
## The physical zombie. Each physics frame it tells its ZombieBrain what it senses (where it is, which
## way it faces, whether it can see the player, what built piece it's pushing against), then walks
## where the brain wants: along the navmesh if there's a path, straight at the target if not.

const HEAD_Y := 1.45   # hits above this height (from the feet) count as head hits
const HEIGHT := 1.8
const RADIUS := 0.35
const LOS_EVERY := 3   # physics frames between line-of-sight checks
const REPATH_DIST := 0.75

var brain: ZombieBrain
var player: Node3D
var agent: NavigationAgent3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _push := Vector3.ZERO
var _frame := 0
var _last_target := Vector3.INF
var _fall := 0.0


func setup(p_brain: ZombieBrain, p_player: Node3D) -> void:
	brain = p_brain
	player = p_player
	set_meta("zombie_id", brain.id)
	position = brain.pos
	var f := Vector3(brain.facing.x, 0.0, brain.facing.z)
	if f.length_squared() > 1e-6:
		rotation.y = atan2(-f.x, -f.z)
	_frame = brain.id  # stagger sight checks across zombies


func _init() -> void:
	collision_layer = Layers.ZOMBIE
	collision_mask = Layers.WORLD | Layers.BUILT | Layers.ZOMBIE
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = HEIGHT / 2.0
	add_child(shape)
	_build_mesh()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.6
	agent.radius = RADIUS
	agent.height = HEIGHT
	add_child(agent)


func _physics_process(delta: float) -> void:
	if brain == null:
		return
	if brain.is_dead():
		_lie_down(delta)
		return
	brain.pos = global_position
	brain.facing = -global_basis.z
	_frame += 1
	if _frame % LOS_EVERY == 0:
		brain.los_clear = _has_line_of_sight()

	var speed := brain.move_speed()
	var dir := Vector3.ZERO
	if speed > 0.0:
		dir = _steer()
	var face := dir
	if speed == 0.0 and brain.state != ZombieBrain.State.IDLE:
		face = _flat(brain.target_pos - global_position)  # turn toward what it's hitting

	if brain.knockback != Vector3.ZERO:
		_push += brain.knockback
		brain.knockback = Vector3.ZERO
	var move := dir.normalized() * speed + _push
	_push = _push.move_toward(Vector3.ZERO, 10.0 * delta)
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()

	if face.length_squared() > 1e-4:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), clampf(6.0 * delta, 0.0, 1.0))
	brain.blocked_by = _blocking_piece(dir)


## Next point to walk toward: the navmesh path if there is one, otherwise straight at the target.
func _steer() -> Vector3:
	if brain.target_pos.distance_to(_last_target) > REPATH_DIST:
		agent.target_position = brain.target_pos
		_last_target = brain.target_pos
	var dir := Vector3.ZERO
	if not agent.is_navigation_finished():
		dir = _flat(agent.get_next_path_position() - global_position)
	if dir.length() < 0.05:
		dir = _flat(brain.target_pos - global_position)  # no path (or path ends short): head straight in
	return dir if dir.length() > 0.3 else Vector3.ZERO


func _has_line_of_sight() -> bool:
	if player == null:
		return false
	var from := global_position + Vector3.UP * ZombieBrain.EYE_HEIGHT
	var to := player.global_position + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.BUILT, [get_rid()])
	if player is CollisionObject3D:
		query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The built piece it walked head-first into this frame, if any.
func _blocking_piece(dir: Vector3) -> String:
	if dir == Vector3.ZERO:
		return ""
	var want := dir.normalized()
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider()
		if other != null and other.has_meta("piece_key") and hit.get_normal().dot(-want) > 0.5:
			return other.get_meta("piece_key")
	return ""


func _lie_down(delta: float) -> void:
	if collision_layer != 0:
		collision_layer = 0
		collision_mask = Layers.WORLD
	_fall = minf(1.0, _fall + delta * 2.5)
	rotation.x = lerpf(0.0, -PI / 2.0, _fall)
	velocity = Vector3(0, velocity.y - _gravity * delta, 0) if not is_on_floor() else Vector3.ZERO
	move_and_slide()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_mesh() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.45, 0.55, 0.4)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.28, 0.25, 0.3)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.45
	body.mesh = capsule
	body.position.y = 0.75
	body.material_override = cloth
	add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	head.mesh = sphere
	head.position.y = 1.62
	head.material_override = skin
	add_child(head)
	for side in [-1.0, 1.0]:  # arms reaching forward
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.12, 0.6)
		arm.mesh = box
		arm.position = Vector3(side * 0.28, 1.3, -0.3)
		arm.material_override = skin
		add_child(arm)
