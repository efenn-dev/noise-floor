class_name ZombieBody
extends CharacterBody3D
## The physical zombie. Each physics frame it tells its ZombieBrain what it senses (where it is, which
## way it faces, whether it can see the player, what built piece it's pushing against), then walks
## where the brain wants: along the navmesh if there's a path, straight at the target if not.

const HEAD_Y := 1.45   # hits above this height (from the feet) count as head hits
const LEG_Y := 0.8     # V33: and below this, the legs (when the bone hit zones are off; data/hit_zones.json leg_height)
const HEIGHT := 1.8
const RADIUS := 0.35
## V24: the arms' reach in front of the body (it walks toward -Z): a ball this big at this offset makes the
## furthest point 0.54 m ahead, where the hands are in the walk and the scratch.
const REACH_RADIUS := 0.22
const REACH_OFFSET := Vector3(0.0, 1.25, -0.32)
const LOS_EVERY := 3   # physics frames between line-of-sight checks
## W3b: a zombie standing idle (and unhurt) further than this from the player rests: its animation stops and it
## skips its physics move and its sight ray until it's woken or you come near. Beyond every zombie's sight (30 m),
## so it changes nothing it would notice; downtown's zombies cost a soak day 60% more before this. W3c: 35 m (it
## was 50), so the new streets' house zombies just out of sight rest too; their bone zones stay on within
## ZombieHitboxes.RANGE, holding the resting pose, so a long shot still hits what it aims at.
## W3e: a far zombie strolling about (WANDER) rests too: its stroll waits until you come near or a noise draws it
## (eight roadside wanderers cost a soak day 16% before this).
const REST_BEYOND := 35.0
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
	"crawler": {"skin": Color(0.28, 0.31, 0.25), "shirts": [Color(0.24, 0.20, 0.18), Color(0.18, 0.22, 0.20)],
			"dim": 0.55},
	"screamer": {"skin": Color(0.62, 0.62, 0.58), "shirts": [Color(0.55, 0.12, 0.1)], "scale": 1.0},
	"brute": {"skin": Color(0.19, 0.21, 0.17), "shirts": [Color(0.16, 0.14, 0.12), Color(0.20, 0.18, 0.13)],
			"dim": 0.42},
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
## V35 (Emmitt: "the zombies seem to die facing away from the player each time"): the Death animation (UAL
## Death01) falls backwards, and V7 turned the body to face away from the blow first, so every zombie showed you
## its back as it went down. Now it dies facing whoever hit it, one of two ways: "back" (the Death animation: it
## goes over backwards and slides away from the blow; most deaths and every hard hit) or "forward" (a hit
## reaction, then it tips over toward you, about its feet).
var death_style := ""
static var settle_deaths := false  # --dead-zombies (screenshots): bodies are already down, the fall finished
static var forced_death_style := ""  # --death-style=back|forward (screenshots)
const BACK_FALL_SHARE := 3  # of every 5 zombies (by id) fall backwards; the rest forwards, unless hit hard
const HARD_HIT := 3.0       # knockback (m/s) that always knocks it over backwards
const FORWARD_FALL_TIME := 0.8  # seconds to tip over forwards
const LYING_LIFT := 0.14    # a tipped-over body lies this high once flat (its front, not its spine, on the ground)
var _death_slide := 0.0
var bad_moves := 0  # fix 2026-10-13: NaN steps dropped before they reached the physics engine
var _frame := 0
var resting := false  # W3b: see REST_BEYOND
var _far := false
var _anim_mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _shape: CollisionShape3D
var _corpse_shape: CollisionShape3D
var _reach_shape: CollisionShape3D  # V24: keeps the reaching arms out of walls
var _last_target := Vector3.INF
var _fall := 0.0
var _model: Node3D
var _hit_shapes: Array[CollisionShape3D] = []  # V33: the bone hit zones (ZombieHitboxes)
var _hitboxes_on := false
## A2: which of BODIES this zombie wears.
var body_variant := ""
var _anim: AnimationPlayer
var _last_hp := INF
var _flinch := 0.0  # seconds left of the hit reaction
var _voice: AudioStreamPlayer3D
var _next_moan := 3.0
var _was_attacking := false
var _said_death := false
var _climb_body: PhysicsBody3D

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
	_voice.pitch_scale = (0.85 + 0.06 * (brain.id % 5)) * float(brain.stats.get("voice_pitch", 1.0))
	_voice.max_distance = float(brain.stats.get("voice_distance", _voice.max_distance))
	_voice.volume_db = float(brain.stats.get("voice_volume_db", _voice.volume_db))
	_next_moan = 1.5 + brain.id % 9
	_configure_collision()
	var variant := variant_for(brain.id, brain.type)
	if BODIES[variant] != body_variant:
		_set_body(variant)
	var look: Dictionary = LOOKS.get(brain.type, {})
	var scale_variation := 1.0 if brain.stats.has("model_scale") else 0.94 + 0.04 * (brain.id % 4)
	_model.scale = Vector3.ONE * MODEL_SCALE * scale_variation * float(brain.stats.get("model_scale", look.get("scale", 1.0)))
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
	_build_hitboxes()  # V33: after the body and its size are final


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
	if type == "brute":
		return BODIES.find("heavy")
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


## V28: collider, navigation footprint and reach follow the type's data. A crawler is a low box stretched
## along its facing; a brute uses a wider, taller capsule and reach ball.
func _configure_collision() -> void:
	if brain.stats.has("collider_size"):
		var raw_size: Array = brain.stats["collider_size"]
		var box := BoxShape3D.new()
		box.size = Vector3(float(raw_size[0]), float(raw_size[1]), float(raw_size[2]))
		_shape.shape = box
		var raw_offset: Array = brain.stats.get("collider_offset", [0.0, box.size.y / 2.0, 0.0])
		_shape.position = Vector3(float(raw_offset[0]), float(raw_offset[1]), float(raw_offset[2]))
		agent.radius = box.size.x / 2.0
		agent.height = box.size.y
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = float(brain.stats.get("body_radius", RADIUS))
		capsule.height = float(brain.stats.get("body_height", HEIGHT))
		_shape.shape = capsule
		_shape.position = Vector3.UP * capsule.height / 2.0
		agent.radius = capsule.radius
		agent.height = capsule.height
	var reach_radius := float(brain.stats.get("reach_radius", REACH_RADIUS))
	_reach_shape.disabled = reach_radius <= 0.0
	if reach_radius > 0.0:
		(_reach_shape.shape as SphereShape3D).radius = reach_radius
		var raw_reach: Array = brain.stats.get("reach_offset", [REACH_OFFSET.x, REACH_OFFSET.y, REACH_OFFSET.z])
		_reach_shape.position = Vector3(float(raw_reach[0]), float(raw_reach[1]), float(raw_reach[2]))


## Height above this body's feet where a ray or swing counts as a head hit.
func head_y() -> float:
	return float(brain.stats.get("head_height", HEAD_Y))


## V33: the zone a hit at height `y` lands in when the bone zones are off (or a swing slips between them).
func zone_at(y: float, at: Vector3 = Vector3.INF) -> String:
	if brain.stats.has("head_ahead") and at.is_finite():  # a crawler lies flat: its head is its front
		var fwd := -global_basis.z
		var ahead := Vector2(at.x - global_position.x, at.z - global_position.z).dot(Vector2(fwd.x, fwd.z).normalized())
		return "head" if ahead >= float(brain.stats["head_ahead"]) else "torso"
	var above := y - global_position.y
	if above >= head_y():
		return "head"
	if above <= float(brain.stats.get("leg_height", LEG_Y)):
		return "leg"
	return "torso"


## V33: whether the bone hit zones are on (near the player, alive).
func hitboxes_on() -> bool:
	return _hitboxes_on and not _hit_shapes.is_empty()


func _build_hitboxes() -> void:
	_hit_shapes = ZombieHitboxes.build(_model, ZombieHitboxes.fit(_model, body_variant), brain.id)
	_hitboxes_on = true
	_set_hitboxes(player != null and is_inside_tree() and player.is_inside_tree()
			and global_position.distance_to(player.global_position) < ZombieHitboxes.RANGE)


func _set_hitboxes(on: bool) -> void:
	if on == _hitboxes_on:
		return
	_hitboxes_on = on
	for cs: CollisionShape3D in _hit_shapes:
		if is_instance_valid(cs):
			cs.disabled = not on


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
	# V24 (Emmitt: "you can see zombie arms sticking through walls"): the motion-captured walk and scratch hold
	# the arms out past the capsule, so a zombie pressed against a wall put its hands through it. A ball at arm
	# height in front of the chest stops the body that much further from whatever it walks into.
	_reach_shape = CollisionShape3D.new()
	var reach := SphereShape3D.new()
	reach.radius = REACH_RADIUS
	_reach_shape.shape = reach
	_reach_shape.position = REACH_OFFSET
	add_child(_reach_shape)
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
	if brain.climb_landing.is_finite():
		global_position = brain.climb_landing
		brain.climb_landing = Vector3.INF
		_end_climb_collision()
	if (_frame + brain.id) % 10 == 0:
		_far = player != null and global_position.distance_to(player.global_position) > REST_BEYOND
	_rest(_far and not brain.is_dead() and (brain.state == ZombieBrain.State.IDLE or brain.state == ZombieBrain.State.WANDER)
			and brain.knockback == Vector3.ZERO and brain.hp >= _last_hp and brain.screaming <= 0.0)
	if resting:
		_frame += 1
		brain.los_clear = false
		if (_frame + brain.id) % 10 == 0:
			_set_hitboxes(player != null and global_position.distance_to(player.global_position) < ZombieHitboxes.RANGE)
		return
	_animate(delta)
	_speak(delta)
	if brain.is_dead():
		_end_climb_collision()
		_set_hitboxes(false)
		_lie_down(delta)
		return
	if (_frame + brain.id) % 10 == 0:  # V33: zones on near the player, off further out
		_set_hitboxes(player != null and global_position.distance_to(player.global_position) < ZombieHitboxes.RANGE)
	if brain.state == ZombieBrain.State.CLIMB:
		_climb_window()
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


## W3b: starts or ends resting (see REST_BEYOND): the animation player stops advancing (manual mode keeps the
## pose and the clip it was on).
func _rest(on: bool) -> void:
	if on == resting:
		return
	resting = on
	if on:
		velocity = Vector3.ZERO
	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if on else _anim_mode


## V17: code-driven climb, independent of model animation names. The sim supplies its deterministic
## 2.5-second fraction; this body leans and arcs over the sill while ignoring only that window body.
func _climb_window() -> void:
	if _climb_body == null or not is_instance_valid(_climb_body) \
			or str(_climb_body.get_meta("piece_key", "")) != brain.climb_key:
		_end_climb_collision()
		for node: Node in get_tree().get_nodes_in_group("build_pieces"):
			if node is PhysicsBody3D and str(node.get_meta("piece_key", "")) == brain.climb_key:
				_climb_body = node as PhysicsBody3D
				add_collision_exception_with(_climb_body)
				break
	var k := smoothstep(0.0, 1.0, brain.climb_fraction())
	var arc := float(brain.stats.get("climb_arc", 0.45))
	global_position = brain.climb_start.lerp(brain.climb_to, k) + Vector3.UP * sin(PI * k) * arc
	brain.pos = global_position
	velocity = Vector3.ZERO
	var face := _flat(brain.climb_to - brain.climb_start)
	if face.length_squared() > 1e-4:
		rotation.y = atan2(-face.x, -face.z)
	_last_good = global_position


func _end_climb_collision() -> void:
	if _climb_body != null and is_instance_valid(_climb_body):
		remove_collision_exception_with(_climb_body)
	_climb_body = null


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
	var from := global_position + Vector3.UP * brain.eye_height()
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
		_reach_shape.disabled = true
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
		# V7: knocked away from the blow. V35: it keeps facing the blow (or you, when nothing knocked it) and
		# either goes over backwards, sliding back a little, or collapses forward toward you.
		var away := brain.knockback
		var hard := away.is_finite() and away.length() >= HARD_HIT
		if away.length_squared() < 0.01 and player != null:
			away = global_position - player.global_position
		away.y = 0.0
		if away.is_finite() and away.length_squared() > 1e-4:
			death_dir = away.normalized()
			_death_slide = clampf(brain.knockback.length() * 0.3, 0.6, 2.2) if brain.knockback.is_finite() else 0.6
		death_style = death_style_for(brain.id, hard)
		if death_style == "forward":
			_death_slide = 0.0  # it drops where it stands
		if settle_deaths:
			_fall = 1.0
			_death_slide = 0.0
			rotation.y = atan2(death_dir.x, death_dir.z)
		brain.knockback = Vector3.ZERO
		if get_parent() != null:  # a pool spreading under the body for as long as it lies there
			ImpactFx.stain(get_parent(), global_position + Vector3.UP * 0.05, Vector3.UP, 1.5, ZombieBrain.CORPSE_TIME, 4.0)
	_fall = minf(1.0, _fall + delta * (1.0 / FORWARD_FALL_TIME if death_style == "forward" else 2.5))
	var slide := death_dir * _death_slide * maxf(0.0, 1.0 - _fall * 1.4)
	velocity = Vector3(slide.x, 0.0 if is_on_floor() else velocity.y - _gravity * delta, slide.z)
	if death_dir != Vector3.ZERO and _fall < 0.6:  # V35: face the blow (its front, -Z, against death_dir)
		rotation.y = lerp_angle(rotation.y, atan2(death_dir.x, death_dir.z), clampf(14.0 * delta, 0.0, 1.0))
	var nudge := nudge_for(player, global_position) if _fall >= 1.0 else Vector3.ZERO
	velocity.x += nudge.x
	velocity.z += nudge.z
	move_and_slide()


## V35: how a zombie dies: "back" for every hard hit and BACK_FALL_SHARE of every 5 by id, else "forward".
static func death_style_for(id: int, hard_hit: bool) -> String:
	if forced_death_style != "":
		return forced_death_style
	return "back" if hard_hit or posmod(id, 5) < BACK_FALL_SHARE else "forward"


## V35: how far over (radians about its feet, toward its front) a "forward" fall is at `fall` 0-1: slow to start,
## then it drops, flat (90 degrees) at the end.
static func forward_tilt(fall: float) -> float:
	var t := clampf(fall, 0.0, 1.0)
	return PI / 2.0 * t * t


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
	_anim_mode = _anim.callback_mode_process
	resting = false
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
	var climbing := brain.state == ZombieBrain.State.CLIMB
	var climb_wave := sin(PI * brain.climb_fraction())
	_model.rotation.x = deg_to_rad(float(brain.stats.get("climb_tilt_deg", 35.0))) * climb_wave if climbing else 0.0
	_model.position.y = -float(brain.stats.get("climb_dip", 0.22)) * climb_wave if climbing else 0.0
	if brain.is_dead() and death_style == "forward":
		var tip := forward_tilt(_fall)  # V35: over forwards, toward you, about its feet
		_model.rotation.x = tip
		_model.position.y = LYING_LIFT * sin(tip)
	if brain.is_dead():
		want = "HitReact" if death_style == "forward" and _anim.has_animation("HitReact") else "Death"
	elif brain.screaming > 0.0 and _anim.has_animation("Scream"):
		want = "Scream"
	elif brain.stats.has("crawl_anim_speed"):
		want = "Crawl"
		speed_scale = clampf(moving / float(brain.stats["crawl_anim_speed"]), 0.5, 1.6)
	elif _flinch > 0.0:
		want = "HitReact"
	elif climbing:
		want = "Crawl" if _anim.has_animation("Crawl") else "Walk"
		speed_scale = 0.7
	elif brain.state == ZombieBrain.State.ATTACK or brain.state == ZombieBrain.State.BREAK:
		want = "Punch"
	elif moving > RUN_ABOVE and _anim.has_animation("Run"):
		want = "Run"
		speed_scale = clampf(moving / (RUN_ANIM_SPEED * _model.scale.x / MODEL_SCALE), 0.6, 1.5)
	elif moving > 0.1:
		want = "Walk"
		speed_scale = clampf(moving / (WALK_ANIM_SPEED * _model.scale.x / MODEL_SCALE), 0.5, 1.6)
	var once := want == "Death" or want == "Scream" or brain.is_dead()  # these play through once, then hold
	if _anim.current_animation != want and not (once and _anim.assigned_animation == want and _anim.is_playing()) \
			and not (brain.is_dead() and _anim.assigned_animation == want):
		_anim.play(want, 0.2)
	_anim.speed_scale = speed_scale
	if brain.is_dead() and settle_deaths and _anim.current_animation != "":
		_anim.seek(_anim.current_animation_length, true)  # already down (screenshots)


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
