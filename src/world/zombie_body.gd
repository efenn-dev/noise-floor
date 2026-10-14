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
## A2: five bodies from the same script (`zombie.py -- --variant=NAME`), with the same bones and animations;
## each zombie gets one by variant_for(id, type), so a crowd isn't one person copied.
const BODIES := ["default", "heavy", "slim", "short", "woman"]
const MODELS := [MODEL, preload("res://assets/models/zombie_heavy.glb"), preload("res://assets/models/zombie_slim.glb"),
		preload("res://assets/models/zombie_short.glb"), preload("res://assets/models/zombie_woman.glb")]
## Clothes that come with a body rather than being tinted per zombie (the shirt is); a runner's are dimmed.
const BODY_CLOTHES := ["Jeans", "Vest", "Hard Hat", "Cap"]
const MODEL_SCALE := 1.0  # built at real size (about HEIGHT tall)
const WALK_ANIM_SPEED := 1.0  # m/s the Walk animation's feet move at speed_scale 1
const RUN_ANIM_SPEED := 3.45  # m/s the Run animation's feet move at speed_scale 1
const RUN_ABOVE := 2.0  # m/s: faster than this, a runner runs instead of walking
## Textures and per-zombie palettes live together so an art pass can tune the whole look in one place.
## `tile_m` is the real-world width of one texture repeat. Materials not in `materials` are deliberately
## left as the model made them; test_textured_looks.gd makes a new model material fail until it is listed.
const LOOK_DATA := {
	"materials": {
		"Zombie Skin": {"texture": "zombie_skin", "tile_m": 0.32},
		"Shirt": {"texture": "cloth_cotton", "tile_m": 0.28},  # texture is replaced by shirt_textures
		"Jeans": {"texture": "denim", "tile_m": 0.30},
		"Boots": {"texture": "leather_boot", "tile_m": 0.22},
	},
	"untextured": ["Eyes", "Hair", "Stain", "Shadow", "Vest", "Hard Hat", "Cap"],
	"shirt_textures": ["cloth_cotton", "cloth_flannel", "cloth_workshirt"],
	"shirt_tints": [
		Color(0.62, 0.60, 0.55), Color(0.45, 0.50, 0.60), Color(0.60, 0.42, 0.38),
		Color(0.50, 0.55, 0.42), Color(0.70, 0.66, 0.50), Color(0.38, 0.40, 0.44),
	],
	# Small multipliers preserve zombie.py's skin colour while making a crowd less uniform.
	"skin_tints": [
		Color(0.94, 0.98, 0.91), Color(1.02, 0.94, 0.90), Color(0.90, 1.00, 0.96),
		Color(1.05, 1.01, 0.93),
	],
}

## How each kind of zombie looks, so you can tell them apart: skin and shirt tints, size.
const LOOKS := {
	"runner": {"skin": Color(0.17, 0.2, 0.15), "shirts": [Color(0.18, 0.18, 0.2), Color(0.2, 0.22, 0.3)], "scale": 0.92,
			"dim": 0.7},  # A2: a runner's vest, hat and trousers go dark too, whichever body it got
	"screamer": {"skin": Color(0.62, 0.62, 0.58), "shirts": [Color(0.55, 0.12, 0.1)], "scale": 1.0},
	"old_pete": {"skin": Color(0.4, 0.42, 0.34), "shirts": [Color(0.62, 0.16, 0.08)], "scale": 1.25},  # M13: the fireman
}
const LOOPED := ["Idle", "Walk", "Run", "Punch", "Crawl"]
const MOANS := 13  # assets/sounds/zombie/moan_NN.wav (CC0, assets/CREDITS.md)
const GRUNTS := 11  # assets/sounds/zombie/grunt_NN.wav

var brain: ZombieBrain
var player: Node3D
var agent: NavigationAgent3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _push := Vector3.ZERO
var _last_good := Vector3.ZERO  # Q1: the last finite position after a move (see the NaN guard)
## Q1: how many times a move came back NaN and was undone (for tests and the soak).
var nan_recoveries := 0
const NUDGE_RADIUS := 0.75  # S5: your feet are on the body inside this distance
const NUDGE_SHARE := 0.1  # S5: share of your walking speed a body shuffles at while you're on it
var death_dir := Vector3.ZERO  # V7: which way it was knocked as it died (it falls and slides that way)
var _death_slide := 0.0
var bad_moves := 0  # fix 2026-10-13: NaN steps dropped before they reached the physics engine
var _frame := 0
var _shape: CollisionShape3D
var _corpse_shape: CollisionShape3D
var _last_target := Vector3.INF
var _fall := 0.0
var _model: Node3D
## A2: which of BODIES this zombie wears.
var body_variant := ""
var _anim: AnimationPlayer
var _last_hp := INF
var _flinch := 0.0  # seconds left of the hit reaction
var _voice: AudioStreamPlayer3D
var _next_moan := 3.0
var _was_attacking := false
var _said_death := false

## Shared by every body with the same material name, source colour and deterministic look. Set only in
## setup(), never per frame. This keeps a street full of matching outfits to one material apiece.
static var _look_material_cache: Dictionary = {}


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
	var variant := variant_for(brain.id, brain.type)
	if BODIES[variant] != body_variant:
		_set_body(variant)
	var look: Dictionary = LOOKS.get(brain.type, {})
	_model.scale = Vector3.ONE * MODEL_SCALE * (0.94 + 0.04 * (brain.id % 4)) * float(look.get("scale", 1.0))
	var shirt_look := shirt_look_for(brain.id)
	var shirts: Array = look.get("shirts", LOOK_DATA["shirt_tints"])
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null:
				continue
			var tint := source.albedo_color
			var texture := ""
			if source.resource_name == "Shirt":
				tint = shirts[brain.id % shirts.size()] if look.has("shirts") else shirt_look["tint"]
				texture = String(shirt_look["texture"])
			elif source.resource_name == "Zombie Skin":
				# The named kind colour remains exact (runner green, screamer pale, Old Pete olive). Ordinary
				# zombies get the subtle id-based multiplier requested for crowd variety.
				tint = look["skin"] if look.has("skin") else skin_tint_for(brain.id, source.albedo_color)
			elif source.resource_name in BODY_CLOTHES and look.has("dim"):
				tint = tint.darkened(look["dim"])
			if LOOK_DATA["materials"].has(source.resource_name):
				var mapping: Dictionary = LOOK_DATA["materials"][source.resource_name]
				if texture == "":
					texture = String(mapping["texture"])
				mesh.set_surface_override_material(i, _material_for_look(source, texture, float(mapping["tile_m"]), tint))
			elif tint != source.albedo_color:
				mesh.set_surface_override_material(i, _plain_material_for_look(source, tint))


## The same id always receives the same cloth and faded colour, before and after saving. The two picks use
## different mixed parts of the id so a short run of ids does not just cycle through three fixed pairs.
static func shirt_look_for(id: int) -> Dictionary:
	var h := id * 0x45D9F3B + 0x27100001
	h = h ^ (h >> 16)
	var textures: Array = LOOK_DATA["shirt_textures"]
	var tints: Array = LOOK_DATA["shirt_tints"]
	return {"texture": textures[posmod(h, textures.size())], "tint": tints[posmod(h >> 8, tints.size())]}


## A slight warm/cool shift around the skin colour authored in zombie.py.
static func skin_tint_for(id: int, base: Color) -> Color:
	var shifts: Array = LOOK_DATA["skin_tints"]
	var shift: Color = shifts[posmod(id * 5 + 1, shifts.size())]
	return Color(clampf(base.r * shift.r, 0.0, 1.0), clampf(base.g * shift.g, 0.0, 1.0),
			clampf(base.b * shift.b, 0.0, 1.0), base.a)


## Object-space triplanar: the texture follows the animated body rather than being projected from the world.
static func _material_for_look(source: StandardMaterial3D, texture: String, tile_m: float,
		tint: Color) -> StandardMaterial3D:
	var key := "textured|%s|%s|%.3f|%s|%.3f|%.3f" % [source.resource_name, texture, tile_m,
			tint.to_html(), source.metallic, source.roughness]
	if not _look_material_cache.has(key):
		var mat := source.duplicate() as StandardMaterial3D
		mat.resource_name = source.resource_name
		mat.albedo_color = Surfaces.tint_for_texture(tint, texture)  # V2 review: no longer near-black
		mat.set_meta("look_tint", tint)  # the look's own colour, before the texture brightness is divided out
		mat.albedo_texture = load("res://assets/textures/%s_albedo.jpg" % texture)
		mat.normal_enabled = true
		mat.normal_texture = load("res://assets/textures/%s_normal.jpg" % texture)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = false
		mat.uv1_scale = Vector3.ONE / tile_m
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_look_material_cache[key] = mat
	return _look_material_cache[key]


static func _plain_material_for_look(source: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var key := "plain|%s|%s|%.3f|%.3f" % [source.resource_name, tint.to_html(), source.metallic, source.roughness]
	if not _look_material_cache.has(key):
		var mat := source.duplicate() as StandardMaterial3D
		mat.resource_name = source.resource_name
		mat.albedo_color = tint
		_look_material_cache[key] = mat
	return _look_material_cache[key]


## A2: the body a zombie gets, from its id and kind: the same zombie always gets the same one (saves,
## reloads and every PC agree). Ids come in blocks of five, each block a hashed shuffle of the five bodies,
## so any handful of zombies spawned together is a mix rather than a run of the same person.
static func variant_for(id: int, type: String) -> int:
	var n := BODIES.size()
	var h := (floori(float(id) / n) + 1) * 0x9E3779B1 + type.hash()
	h = (h ^ (h >> 15)) * 0x2C1B3C6D
	var order := range(n)
	for i in range(n - 1, 0, -1):  # Fisher-Yates, driven by the hash's bits
		h = h ^ (h >> 13)
		h = h * 0x5DEECE66D + 11
		var j := posmod(h >> 17, i + 1)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	return order[posmod(id, n)]


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
	_shape = CollisionShape3D.new()
	_shape.shape = capsule
	_shape.position.y = HEIGHT / 2.0
	add_child(_shape)
	# S4: once it's dead the capsule goes and this low slab takes over, so the look ray finds the body on the
	# ground (E searches it, like a bag) and nothing trips over a standing ghost.
	_corpse_shape = CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(1.3, 0.4, 1.3)
	_corpse_shape.shape = slab
	_corpse_shape.position.y = 0.2
	_corpse_shape.disabled = true
	add_child(_corpse_shape)
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
		if brain.knockback.is_finite():
			_push += brain.knockback
		brain.knockback = Vector3.ZERO
	var move := dir.normalized() * speed + _push
	if not move.is_finite():
		# Fix 2026-10-13: a NaN step must never reach the physics engine; it poisons whatever it touches
		# (a car, then every zombie against the car). Stand still this frame instead.
		move = Vector3.ZERO
		_push = Vector3.ZERO
		bad_moves += 1
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
	if not velocity.is_finite():
		velocity = Vector3.ZERO  # Fix 2026-10-13: same guard for a body lying down
	if collision_layer != Layers.BAG:
		collision_layer = Layers.BAG  # S4: only the look ray sees a corpse (like a dropped bag)
		collision_mask = Layers.WORLD
		_shape.disabled = true
		_corpse_shape.disabled = false
		set_meta("container_id", SimWorld.CORPSE + str(brain.id))  # the Interactor offers to search it
		# S5 (Emmitt: "when you walk over a slain zombie you push the dead bodies"): a body is a kinematic
		# body, which the engine treats as unpushable and infinitely heavy, so it shoved you, and it shoved
		# any car it touched (a likely source of the car's NaN). It now ignores you and the cars entirely;
		# walking over it nudges it a little instead (_nudge).
		if player is PhysicsBody3D:
			add_collision_exception_with(player)
		if is_inside_tree():
			for car: Node in get_tree().get_nodes_in_group("cars"):
				if car is PhysicsBody3D:
					add_collision_exception_with(car)
		# V7: fall away from the blow. The Death animation tips the body forward, so it turns to face the way
		# it was knocked (away from you when nothing knocked it) and slides back a little as it drops.
		var away := brain.knockback
		if away.length_squared() < 0.01 and player != null:
			away = global_position - player.global_position
		away.y = 0.0
		if away.is_finite() and away.length_squared() > 1e-4:
			death_dir = away.normalized()
			_death_slide = clampf(brain.knockback.length() * 0.3, 0.6, 2.2) if brain.knockback.is_finite() else 0.6
		brain.knockback = Vector3.ZERO
		if get_parent() != null:  # a pool spreading under the body for as long as it lies there
			ImpactFx.stain(get_parent(), global_position + Vector3.UP * 0.05, Vector3.UP, 1.5, ZombieBrain.CORPSE_TIME, 4.0)
	_fall = minf(1.0, _fall + delta * 2.5)  # the Death animation does the falling
	var slide := death_dir * _death_slide * maxf(0.0, 1.0 - _fall * 1.4)
	velocity = Vector3(slide.x, 0.0 if is_on_floor() else velocity.y - _gravity * delta, slide.z)
	if death_dir != Vector3.ZERO and _fall < 0.6:
		rotation.y = lerp_angle(rotation.y, atan2(-death_dir.x, -death_dir.z), clampf(14.0 * delta, 0.0, 1.0))
	var nudge := nudge_for(player, global_position) if _fall >= 1.0 else Vector3.ZERO
	velocity.x += nudge.x
	velocity.z += nudge.z
	move_and_slide()


## S5: how hard walking over a body shuffles it: a small share of your speed while your feet are on it,
## nothing when you stand still. Bodies are heavy: they shift a little, they don't skate away.
static func nudge_for(walker: Node3D, body_pos: Vector3) -> Vector3:
	var w := walker as CharacterBody3D
	if w == null:
		return Vector3.ZERO
	var d := body_pos - w.global_position
	d.y = 0.0
	if d.length() > NUDGE_RADIUS:
		return Vector3.ZERO
	var v := Vector3(w.velocity.x, 0.0, w.velocity.z)
	if v.length() < 0.5:
		return Vector3.ZERO
	return v * NUDGE_SHARE


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_mesh() -> void:
	_set_body(0)  # setup() swaps in the zombie's own body
	_voice = AudioStreamPlayer3D.new()
	_voice.position.y = 1.6
	_voice.max_distance = 45.0
	_voice.unit_size = 4.0
	_voice.volume_db = -4.0
	add_child(_voice)


## Put on body BODIES[index] (replacing the one it has), standing in Idle.
func _set_body(index: int) -> void:
	if _model != null:
		remove_child(_model)
		_model.queue_free()
	body_variant = BODIES[index]
	_model = (MODELS[index] as PackedScene).instantiate() as Node3D
	_model.rotation.y = PI  # built facing Blender -Y, which imports as +Z; bodies walk toward -Z
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for anim_name: String in LOOPED:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")


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
