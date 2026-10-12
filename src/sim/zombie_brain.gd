class_name ZombieBrain
extends RefCounted
## One zombie's mind. The world body moves it around and reports what it senses (position, facing,
## clear line of sight to the player, what it's bumping into); the brain decides what to do.
##   IDLE -> WANDER (random strolls near home)
##   sees you -> CHASE -> close enough -> ATTACK (hits every attack_interval)
##   chasing but stuck against something you built -> BREAK (hits the piece until it's gone)
##   loses sight -> walks to where it last saw you, waits LOSE_TIME there, then gives up (IDLE);
##                  it also gives up after CHASE_MEMORY if it can't get there
##   hears something (idle, wandering or already investigating) -> INVESTIGATE: walks to the sound;
##                  if it was a machine, wrecks it (BREAK); otherwise looks around, then IDLE
##   hp 0 -> DEAD (the body lies there for CORPSE_TIME)

enum State { IDLE, WANDER, CHASE, ATTACK, BREAK, INVESTIGATE, DEAD }
const STATE_NAMES := ["idle", "wander", "chase", "attack", "break", "investigate", "dead"]
const LOSE_TIME := 4.0
const CHASE_MEMORY := 20.0
const SEARCH_RADIUS := 1.5  # "at the last-seen spot" for LOSE_TIME purposes
const BREAK_GIVE_UP := 30.0
const WANDER_RADIUS := 8.0
const WANDER_TIMEOUT := 12.0
const ARRIVE := 0.8
const CORPSE_TIME := 15.0
const EYE_HEIGHT := 1.6
const INVESTIGATE_TIME := 30.0
const MACHINE_REACH := 2.2  # close enough to a noisy machine to start wrecking it

var id: int
var type: String
var stats: Dictionary
var hp: float
var state: int = State.IDLE
var home: Vector3
var target_pos: Vector3  # where it wants to walk
var last_seen: Vector3
var break_key := ""
var sound_key := ""  # piece key of the machine it's walking toward, "" for other sounds
var dead_time := 0.0

## Senses, written by the world body (or a test) before each think.
var pos: Vector3
var facing := Vector3.FORWARD
var los_clear := false     # nothing solid between its eyes and the player's
var blocked_by := ""       # piece key it is walking into, "" if none

## Set by take_hit; the world body applies it as a shove and clears it.
var knockback := Vector3.ZERO

var _cooldown := 0.0
var _timer := 0.0
var _lost := 0.0     # seconds waiting at the last-seen spot
var _unseen := 0.0   # seconds since it last saw you
var _rng := RandomNumberGenerator.new()


func _init(p_id: int, p_type: String, p_stats: Dictionary, p_pos: Vector3, seed_value: int) -> void:
	id = p_id
	type = p_type
	stats = p_stats
	hp = float(stats["hp"])
	pos = p_pos
	home = p_pos
	target_pos = p_pos
	_rng.seed = seed_value
	_timer = _rng.randf_range(0.5, 4.0)


func state_name() -> String:
	return STATE_NAMES[state]


func is_dead() -> bool:
	return state == State.DEAD


## How fast the body should walk right now (m/s). 0 = stand still.
func move_speed() -> float:
	match state:
		State.WANDER:
			return float(stats["wander_speed"])
		State.CHASE:
			return float(stats["chase_speed"])
		State.INVESTIGATE:
			return float(stats["investigate_speed"])
	return 0.0


## Hearing threshold: heard level must reach this for it to notice a sound.
func hearing(night: bool) -> float:
	return float(stats["hearing_night"] if night else stats["hearing_day"])


## Heard a sound at `at` (`key` = the machine making it, if any). Only idle, wandering or already
## investigating zombies follow sounds; chasing or fighting ones are busy.
func hear(at: Vector3, key: String = "", time: float = INVESTIGATE_TIME) -> void:
	if not (state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE):
		return
	state = State.INVESTIGATE
	target_pos = at
	sound_key = key
	_timer = time


## Can a zombie at `from` facing `facing` see a player at `to`? Close by, it notices you whatever way it
## faces; further out you must be in its field of view and in range. Range shrinks at night unless
## your flashlight is on.
static func can_see(from: Vector3, p_facing: Vector3, to: Vector3, p_los_clear: bool, night: bool, lit: bool,
		p_stats: Dictionary) -> bool:
	if not p_los_clear:
		return false
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := d.length()
	if dist <= float(p_stats["sense_radius"]):
		return true
	var sight: float = p_stats["sight_night"] if night and not lit else p_stats["sight_day"]
	if dist > sight:
		return false
	var look := Vector3(p_facing.x, 0.0, p_facing.z)
	if look.length_squared() < 1e-6:
		return true
	return rad_to_deg(look.angle_to(d)) <= float(p_stats["sight_fov"]) / 2.0


## One sim tick. `pieces` is the build grid's piece table (to know if a wall still stands).
## Returns attacks made this tick: [{"target": "player"}] or [{"target": piece_key}].
func think(dt: float, player_pos: Vector3, sees: bool, player_dead: bool, pieces: Dictionary) -> Array:
	if state == State.DEAD:
		dead_time += dt
		return []
	var events := []
	_cooldown = maxf(0.0, _cooldown - dt)
	if player_dead:
		sees = false
	if sees:
		last_seen = player_pos
		_lost = 0.0
		_unseen = 0.0
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
	var reach := float(stats["attack_range"])
	var dist := _flat_dist(pos, player_pos)
	match state:
		State.IDLE:
			_timer -= dt
			if _timer <= 0.0:
				var angle := _rng.randf_range(0.0, TAU)
				var r := _rng.randf_range(2.0, WANDER_RADIUS)
				target_pos = home + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
				state = State.WANDER
				_timer = WANDER_TIMEOUT
		State.WANDER:
			_timer -= dt
			if _flat_dist(pos, target_pos) < ARRIVE or _timer <= 0.0 or blocked_by != "":
				_go_idle(false)
		State.INVESTIGATE:
			_timer -= dt
			if blocked_by != "" and pieces.has(blocked_by):
				_start_break(blocked_by)
			elif sound_key != "" and pieces.has(sound_key) and _flat_dist(pos, target_pos) < MACHINE_REACH:
				_start_break(sound_key)  # found the noisy machine: wreck it
			elif _flat_dist(pos, target_pos) < ARRIVE * 2.0 or _timer <= 0.0:
				_go_idle(true)
		State.CHASE:
			target_pos = last_seen
			if player_dead:
				_go_idle(true)
			elif sees and dist <= reach:
				state = State.ATTACK
			elif blocked_by != "" and pieces.has(blocked_by):
				_start_break(blocked_by)
			elif not sees:
				_unseen += dt
				if _flat_dist(pos, last_seen) < SEARCH_RADIUS:
					_lost += dt
				if _lost >= LOSE_TIME or _unseen >= CHASE_MEMORY:
					_go_idle(true)
		State.ATTACK:
			target_pos = player_pos
			if player_dead:
				_go_idle(true)
			elif not sees or dist > reach + 0.3:
				state = State.CHASE
			elif _cooldown <= 0.0:
				events.append({"target": "player"})
				_cooldown = float(stats["attack_interval"])
		State.BREAK:
			if sees and dist <= reach:
				state = State.ATTACK
			elif not pieces.has(break_key):
				state = State.CHASE
				break_key = ""
			else:
				if not sees:
					_lost += dt
				if _lost >= BREAK_GIVE_UP:
					_go_idle(true)
				elif _cooldown <= 0.0:
					events.append({"target": break_key})
					_cooldown = float(stats["attack_interval"])
	return events


## Hit by the player standing at `from`. Returns true if this killed it.
func take_hit(damage: float, from: Vector3, push: float) -> bool:
	if state == State.DEAD:
		return false
	hp -= damage
	var away := Vector3(pos.x - from.x, 0.0, pos.z - from.z)
	knockback = away.normalized() * push if away.length_squared() > 1e-6 else Vector3.ZERO
	if hp <= 0.0:
		hp = 0.0
		state = State.DEAD
		return true
	if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
		state = State.CHASE  # it knows where you are now
		last_seen = from
		_lost = 0.0
		_unseen = 0.0
	return false


func _start_break(key: String) -> void:
	state = State.BREAK
	break_key = key
	_lost = 0.0


func _go_idle(new_home: bool) -> void:
	state = State.IDLE
	break_key = ""
	sound_key = ""
	_timer = _rng.randf_range(2.0, 6.0)
	target_pos = pos
	if new_home:
		home = pos


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
