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
const MODEL := preload("res://assets/models/zombie.glb")  # rigged + animated by tools/art/zombie.py
const MODEL_SCALE := 1.0  # built at real size (about HEIGHT tall)
const WALK_ANIM_SPEED := 1.0  # m/s the Walk animation's feet move at speed_scale 1
const RUN_ANIM_SPEED := 3.45  # m/s the Run animation's feet move at speed_scale 1
const RUN_ABOVE := 2.0  # m/s: faster than this, a runner runs instead of walking
## How each kind of zombie looks, so you can tell them apart: skin and shirt tints, size.
const LOOKS := {
	"runner": {"skin": Color(0.17, 0.2, 0.15), "shirts": [Color(0.18, 0.18, 0.2), Color(0.2, 0.22, 0.3)], "scale": 0.92},
	"screamer": {"skin": Color(0.62, 0.62, 0.58), "shirts": [Color(0.55, 0.12, 0.1)], "scale": 1.0},
	"old_pete": {"skin": Color(0.4, 0.42, 0.34), "shirts": [Color(0.62, 0.16, 0.08)], "scale": 1.25},  # M13: the fireman
}
const LOOPED := ["Idle", "Walk", "Run", "Punch", "Crawl"]
const MOANS := 13  # assets/sounds/zombie/moan_NN.wav (CC0, assets/CREDITS.md)
const GRUNTS := 11  # assets/sounds/zombie/grunt_NN.wav
## Faded shirt colours, one per zombie, so a crowd isn't identical.
const SHIRTS := [Color(0.62, 0.6, 0.55), Color(0.45, 0.5, 0.6), Color(0.6, 0.42, 0.38), Color(0.5, 0.55, 0.42),
		Color(0.7, 0.66, 0.5), Color(0.38, 0.4, 0.44)]

var brain: ZombieBrain
var player: Node3D
var agent: NavigationAgent3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _push := Vector3.ZERO
var _last_good := Vector3.ZERO  # Q1: the last finite position after a move (see the NaN guard)
## Q1: how many times a move came back NaN and was undone (for tests and the soak).
var nan_recoveries := 0
var _frame := 0
var _last_target := Vector3.INF
var _fall := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _last_hp := INF
var _flinch := 0.0  # seconds left of the hit reaction
var _voice: AudioStreamPlayer3D
var _next_moan := 3.0
var _was_attacking := false
var _said_death := false


func setup(p_brain: ZombieBrain, p_player: Node3D) -> void:
	brain = p_brain
	player = p_player
	set_meta("zombie_id", brain.id)
	position = brain.pos
	_last_good = brain.pos
	var f := Vector3(brain.facing.x, 0.0, brain.facing.z)
	if f.length_squared() > 1e-6:
		rotation.y = atan2(-f.x, -f.z)
	_frame = brain.id  # stagger sight checks across zombies
	_last_hp = brain.hp
	_voice.pitch_scale = 0.85 + 0.06 * (brain.id % 5)
	_next_moan = 1.5 + brain.id % 9
	var look: Dictionary = LOOKS.get(brain.type, {})
	_model.scale = Vector3.ONE * MODEL_SCALE * (0.94 + 0.04 * (brain.id % 4)) * float(look.get("scale", 1.0))
	var shirts: Array = look.get("shirts", SHIRTS)
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			if mat.resource_name == "Shirt":
				mat = mat.duplicate()
				mat.albedo_color = shirts[brain.id % shirts.size()]
				mesh.set_surface_override_material(i, mat)
			elif mat.resource_name == "Zombie Skin" and look.has("skin"):
				mat = mat.duplicate()
				mat.albedo_color = look["skin"]
				mesh.set_surface_override_material(i, mat)


func _init() -> void:
	collision_layer = Layers.ZOMBIE
	collision_mask = Layers.WORLD | Layers.BUILT | Layers.ZOMBIE
	# Q1: zombies never ride anything. A car you had driven and parked handed a zombie scraping past it a
	# NaN "platform velocity", which turned its position NaN; taking no velocity from floors or walls stops it.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
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
	_animate(delta)
	_speak(delta)
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
	if global_position.is_finite():
		_last_good = global_position
	else:
		# Q1: a NaN move (the soak saw one beside a car you had just got out of) used to stick for good: the
		# brain went NaN too and every frame logged warnings. Step back to the last good spot instead.
		global_position = _last_good
		brain.pos = _last_good
		velocity = Vector3.ZERO
		_push = Vector3.ZERO
		nan_recoveries += 1

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
	for i in 4:  # it can see through window glass (BuildView marks windows "see_through")
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return true
		var other: Object = hit["collider"]
		if other == null or not other.has_meta("see_through"):
			return false
		query.exclude = query.exclude + [hit["rid"]]
	return false


## The built piece it walked head-first into this frame, if any.
func _blocking_piece(dir: Vector3) -> String:
	if dir == Vector3.ZERO:
		return ""
	var want := dir.normalized()
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider()
		# Only something it walks into face first: the low edge of a floor it's stepping onto doesn't count.
		if other != null and other.has_meta("piece_key") and hit.get_normal().dot(-want) > 0.5 				and absf(hit.get_normal().y) < 0.5:
			return other.get_meta("piece_key")
	return ""


func _lie_down(delta: float) -> void:
	if collision_layer != 0:
		collision_layer = 0
		collision_mask = Layers.WORLD
	_fall = minf(1.0, _fall + delta * 2.5)  # the Death animation does the falling
	velocity = Vector3(0, velocity.y - _gravity * delta, 0) if not is_on_floor() else Vector3.ZERO
	move_and_slide()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_mesh() -> void:
	_model = MODEL.instantiate() as Node3D
	_model.rotation.y = PI  # built facing Blender -Y, which imports as +Z; bodies walk toward -Z
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for anim_name: String in LOOPED:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.max_distance = 45.0
	_voice.unit_size = 4.0
	_voice.volume_db = -4.0
	add_child(_voice)


## Pick the animation from what the brain is doing and how fast the body really moves.
func _animate(delta: float) -> void:
	if brain.hp < _last_hp and not brain.is_dead():
		_flinch = 0.45
		_say("grunt", GRUNTS)
	_last_hp = brain.hp
	_flinch = maxf(0.0, _flinch - delta)
	var want := "Idle"
	var speed_scale := 1.0
	var moving := Vector2(velocity.x, velocity.z).length()
	if brain.is_dead():
		want = "Death"
	elif brain.screaming > 0.0 and _anim.has_animation("Scream"):
		want = "Scream"
	elif _flinch > 0.0:
		want = "HitReact"
	elif brain.state == ZombieBrain.State.ATTACK or brain.state == ZombieBrain.State.BREAK:
		want = "Punch"
	elif moving > RUN_ABOVE and _anim.has_animation("Run"):
		want = "Run"
		speed_scale = clampf(moving / (RUN_ANIM_SPEED * _model.scale.x / MODEL_SCALE), 0.6, 1.5)
	elif moving > 0.1:
		want = "Walk"
		speed_scale = clampf(moving / (WALK_ANIM_SPEED * _model.scale.x / MODEL_SCALE), 0.5, 1.6)
	var once := want == "Death" or want == "Scream"  # these play through once, then hold
	if _anim.current_animation != want and not (once and _anim.assigned_animation == want and _anim.is_playing()) \
			and not (want == "Death" and _anim.assigned_animation == "Death"):
		_anim.play(want, 0.2)
	_anim.speed_scale = speed_scale


## Moans now and then (more often while chasing), a grunt when it starts an attack or gets hit,
## and one last moan when it dies.
func _speak(delta: float) -> void:
	if brain.is_dead():
		if not _said_death:
			_said_death = true
			_say("moan", MOANS)
		return
	var attacking := brain.state == ZombieBrain.State.ATTACK or brain.state == ZombieBrain.State.BREAK
	if attacking and not _was_attacking:
		_say("grunt", GRUNTS)
	_was_attacking = attacking
	_next_moan -= delta
	if _next_moan <= 0.0:
		_say("moan", MOANS)
		_next_moan = randf_range(2.5, 5.0) if brain.state == ZombieBrain.State.CHASE else randf_range(6.0, 14.0)


func _say(kind: String, count: int) -> void:
	if _voice.playing and kind == "moan":
		return  # don't cut itself off for an idle moan
	_voice.stream = SoundView.stream("zombie/%s_%02d" % [kind, 1 + randi() % count])
	if SoundView.audible:
		_voice.play()


func _exit_tree() -> void:
	if _voice != null:
		_voice.stop()  # a sound still playing when the node goes would be held by the audio server
