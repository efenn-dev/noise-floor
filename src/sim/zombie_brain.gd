class_name ZombieBrain
extends RefCounted
## One zombie's mind. The world body moves it around and reports what it senses (position, facing,
## clear line of sight to the player, what it's bumping into); the brain decides what to do.
##   IDLE -> WANDER (random strolls near home; W1b: not when home is indoors, on a town floor: a zombie
##                   that has settled inside a house or the factory stands there until something draws it)
##   sees you -> CHASE -> close enough -> ATTACK (hits every attack_interval)
##   chasing but stuck against something you built -> BREAK (hits the piece until it's gone)
##   Q2: only a zombie that is chasing you or investigating a sound (a wave's road route included) breaks
##                  a piece, and only one in its way; an idle or wandering zombie that bumps a piece turns
##                  away to another wander spot. When the piece is gone it goes back to what it was doing.
##   loses sight -> walks to where it last saw you, waits LOSE_TIME there, then gives up (IDLE);
##                  it also gives up after CHASE_MEMORY if it can't get there
##   hears something (idle, wandering or already investigating) -> INVESTIGATE: walks to the sound;
##                  if it was a machine, wrecks it (BREAK); otherwise looks around, then IDLE.
##                  W1b: hear_via() gives it a few waypoints to walk first (a Director wave walks the road),
##                  each consumed on arrival; then it heads for the sound itself
##   a chaser/investigator at a broken window -> CLIMB for its data climb_seconds, unable to attack
##   hp 0 -> DEAD (the body lies there for CORPSE_TIME)
##   Q4: a guardian (Old Pete; TownPlan gives his hall as guard_area) never leaves its home area: it only
##                  hears sounds made inside it, only sees (and chases) a player inside it, gives up the moment
##                  the player steps out (at the doorway) and walks back to guard_spot, its place in the hall.

enum State { IDLE, WANDER, CHASE, ATTACK, BREAK, INVESTIGATE, CLIMB, DEAD }
const STATE_NAMES := ["idle", "wander", "chase", "attack", "break", "investigate", "climb", "dead"]
const LOSE_TIME := 4.0
const CHASE_MEMORY := 20.0
const SEARCH_RADIUS := 1.5  # "at the last-seen spot" for LOSE_TIME purposes
const BREAK_GIVE_UP := 30.0
const WANDER_RADIUS := 8.0
const WANDER_TIMEOUT := 12.0
const ARRIVE := 0.8
## S4: a corpse lies there, searchable, for CORPSE_TIME (four game-hours at the default clock); once
## searched it is cleared after SEARCHED_CORPSE_TIME.
const CORPSE_TIME := 240.0
const SEARCHED_CORPSE_TIME := 30.0
const EYE_HEIGHT := 1.6
const INVESTIGATE_TIME := 30.0
const MACHINE_REACH := 2.2  # close enough to a noisy machine to start wrecking it

var id: int
var type: String
var stats: Dictionary
var difficulty: Difficulty
var hp: float
var state: int = State.IDLE
var home: Vector3
var target_pos: Vector3  # where it wants to walk
var last_seen: Vector3
var break_key := ""
var break_from: int = State.CHASE  # Q2: what it was doing when it started breaking (CHASE or INVESTIGATE)
var sound_key := ""  # piece key of the machine it's walking toward, "" for other sounds
var sound_pos: Vector3  # where the sound it's investigating came from (target_pos once the route is walked)
var route: Array = []   # W1b: waypoints (Vector3) to walk before heading for sound_pos; target_pos = route[0]
## V17: scripted crossing of a broken window. The body draws this state and ignores that one collider.
var climb_key := ""
var climb_from_state: int = State.CHASE
var climb_start := Vector3.ZERO
var climb_to := Vector3.ZERO
var climb_landing := Vector3.INF
var climb_elapsed := 0.0
var climb_duration := 2.5
var dead_time := 0.0
var searched := false  # S4: the corpse has been looted
var screaming := 0.0  # seconds left of a screamer's shriek (it stands still)
## M15: seconds left pinned by a bear trap (can't walk, can still bite) and stunned by an electric fence
## (can't walk or attack). Set by Defense.
var pinned := 0.0
var stunned := 0.0
var _scream_cd := 0.0
## Q4: a guardian's home area (x, z in metres; empty = not a guardian) and its spot in it. Saved.
var guard_area := Rect2()
var guard_spot := Vector3.ZERO

## Senses, written by the world body (or a test) before each think.
var pos: Vector3
var facing := Vector3.FORWARD
var los_clear := false     # nothing solid between its eyes and the player's
var blocked_by := ""       # piece key it is walking into, "" if none

## Set by take_hit; the world body applies it as a shove and clears it.
var knockback := Vector3.ZERO
## Set each tick by traps it stands on (1 = full speed).
var slow := 1.0
## V29: written by Horde each tick. Night movement and hearing use the shared Difficulty rule.
var night := false

var _cooldown := 0.0
var _timer := 0.0
var _lost := 0.0     # seconds waiting at the last-seen spot
var _unseen := 0.0   # seconds since it last saw you
var _rng := RandomNumberGenerator.new()
var _leg_time := INVESTIGATE_TIME  # each leg of a route gets this long before it gives up


func _init(p_id: int, p_type: String, p_stats: Dictionary, p_pos: Vector3, seed_value: int,
		p_difficulty: Difficulty = null) -> void:
	id = p_id
	type = p_type
	stats = p_stats
	difficulty = p_difficulty
	hp = max_hp()
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
	if screaming > 0.0 or pinned > 0.0 or stunned > 0.0:
		return 0.0
	match state:
		State.WANDER:
			return _night_speed(float(stats["wander_speed"])) * slow
		State.CHASE:
			return _night_speed(float(stats["chase_speed"])) * slow
		State.INVESTIGATE:
			return _night_speed(float(stats["investigate_speed"])) * slow
	return 0.0


func max_hp() -> float:
	return difficulty.scale("zombie_health", float(stats["hp"])) if difficulty != null else float(stats["hp"])


func attack_damage() -> float:
	return difficulty.scale("zombie_damage", float(stats["damage"])) if difficulty != null else float(stats["damage"])


func structure_damage() -> float:
	return difficulty.scale("zombie_damage", float(stats["structure_damage"])) \
			if difficulty != null else float(stats["structure_damage"])


func _night_speed(base: float) -> float:
	return difficulty.move_speed(base, night) if difficulty != null else base


## Damage that doesn't come from anyone (traps): hurts, but doesn't tell it where you are.
func hurt(damage: float) -> bool:
	if state == State.DEAD:
		return false
	hp -= damage
	if hp <= 0.0:
		hp = 0.0
		state = State.DEAD
		climb_key = ""
		return true
	return false


## Hearing threshold: heard level must reach this for it to notice a sound.
func hearing(night: bool) -> float:
	return difficulty.hearing(stats, night) if difficulty != null \
			else float(stats["hearing_night"] if night else stats["hearing_day"])


## V29: an exposed first-night wave knows the player's location and actively hunts it.
func hunt(at: Vector3) -> void:
	if state == State.DEAD:
		return
	state = State.CHASE
	last_seen = at
	target_pos = at
	blocked_by = ""
	route = []
	_lost = 0.0
	_unseen = 0.0


## Heard a sound at `at` (`key` = the machine making it, if any). Only idle, wandering or already
## investigating zombies follow sounds; chasing or fighting ones are busy.
func hear(at: Vector3, key: String = "", time: float = INVESTIGATE_TIME) -> void:
	if not in_guard(at):
		return  # Q4: a guardian ignores sounds from outside its home area
	if not (state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE):
		return
	if state == State.INVESTIGATE and not route.is_empty() and _flat_dist(at, sound_pos) < 1.0:
		_timer = maxf(_timer, time)  # the same sound it's already on its way to: keep to the route
		return
	state = State.INVESTIGATE
	blocked_by = ""  # Q2: a bump from before it heard this isn't in the way to the sound
	target_pos = at
	sound_pos = at
	sound_key = key
	route = []
	_timer = time


## Like hear(), but walk through `via` (waypoints, in order) first. A Director wave uses it so the
## zombies come down the road before turning toward the noise.
func hear_via(via: Array, at: Vector3, key: String = "", time: float = INVESTIGATE_TIME) -> void:
	if not in_guard(at):
		return
	hear(at, key, time)
	if state != State.INVESTIGATE or via.is_empty() or is_guardian():
		return
	route = via.duplicate()
	target_pos = route[0]
	_leg_time = time


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
	_scream_cd = maxf(0.0, _scream_cd - dt)
	screaming = maxf(0.0, screaming - dt)
	pinned = maxf(0.0, pinned - dt)
	if stunned > 0.0:
		stunned = maxf(0.0, stunned - dt)
		return events  # M15: shocked by a fence: it does nothing at all for a moment
	if player_dead:
		sees = false
	# Q4: a guardian takes no notice of a player outside its home area, and gives up at once if it was after one.
	if not in_guard(player_pos):
		sees = false
		if state == State.CHASE or state == State.ATTACK or state == State.CLIMB \
				or (state == State.BREAK and break_from == State.CHASE):
			_go_back()
	# Screamers shriek when they spot you: a loud noise that pulls in everything within earshot.
	if sees and stats.has("scream_loudness") and _scream_cd <= 0.0:
		events.append({"target": "scream"})
		screaming = float(stats["scream_time"])
		_scream_cd = float(stats["scream_cooldown"])
	if sees:
		last_seen = player_pos
		_lost = 0.0
		_unseen = 0.0
		if state == State.IDLE or state == State.WANDER:
			blocked_by = ""  # Q2: what it bumped while strolling isn't in the way to you
		if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
			state = State.CHASE
	var reach := float(stats["attack_range"])
	var dist := _flat_dist(pos, player_pos)
	match state:
		State.IDLE:
			_timer -= dt
			if _timer <= 0.0 and is_guardian() and _flat_dist(pos, guard_spot) > ARRIVE * 2.0:
				_go_back()  # Q4: a guardian away from its spot walks back to it
			elif _timer <= 0.0 and _indoors(pieces, home):
				_timer = _rng.randf_range(2.0, 6.0)  # settled inside: it stays put until something draws it
			elif _timer <= 0.0:
				var angle := _rng.randf_range(0.0, TAU)
				var r := _rng.randf_range(2.0, WANDER_RADIUS)
				target_pos = _clamp_guard(home + Vector3(cos(angle) * r, 0.0, sin(angle) * r))
				state = State.WANDER
				_timer = WANDER_TIMEOUT
		State.WANDER:
			_timer -= dt
			if blocked_by != "":
				_turn_away()  # Q2: it bumped a piece: never breaks it, strolls somewhere else instead
			elif _flat_dist(pos, target_pos) < ARRIVE or _timer <= 0.0:
				_go_idle(false)
		State.INVESTIGATE:
			_timer -= dt
			if _broken_window(pieces, blocked_by):
				_start_climb(blocked_by, pieces[blocked_by] as Dictionary)
			elif blocked_by != "" and _standing(pieces, blocked_by):
				_start_break(blocked_by)
			elif not route.is_empty():
				if _flat_dist(pos, target_pos) < ARRIVE * 2.0:  # reached a waypoint: on to the next, or the sound
					route.pop_front()
					target_pos = route[0] if not route.is_empty() else sound_pos
					_timer = _leg_time
				elif _timer <= 0.0:
					_go_idle(true)
			elif sound_key != "" and pieces.has(sound_key) and _flat_dist(pos, target_pos) < MACHINE_REACH:
				_start_break(sound_key)  # found the noisy machine: wreck it
			elif _flat_dist(pos, target_pos) < ARRIVE * 2.0 or _timer <= 0.0:
				_go_idle(true)
		State.CHASE:
			target_pos = last_seen
			if player_dead:
				_go_idle(true)
			elif _broken_window(pieces, blocked_by):
				_start_climb(blocked_by, pieces[blocked_by] as Dictionary)
			elif blocked_by != "" and _standing(pieces, blocked_by):
				_start_break(blocked_by)
			elif sees and dist <= reach:
				state = State.ATTACK
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
			if _broken_window(pieces, break_key):
				_start_climb(break_key, pieces[break_key] as Dictionary, break_from)
			elif sees and dist <= reach and not _window_piece(pieces, break_key):
				state = State.ATTACK
			elif not _standing(pieces, break_key):
				_after_break()
			else:
				if not sees:
					_lost += dt
				if _lost >= BREAK_GIVE_UP:
					_go_idle(true)
				elif _cooldown <= 0.0:
					events.append({"target": break_key})
					_cooldown = float(stats["attack_interval"])
		State.CLIMB:
			climb_elapsed = minf(climb_duration, climb_elapsed + dt)
			if climb_elapsed >= climb_duration:
				pos = climb_to
				climb_landing = climb_to
				state = climb_from_state
				climb_key = ""
				blocked_by = ""
				target_pos = last_seen if state == State.CHASE else sound_pos
	return events


## Q4: is this zombie a guardian (it has a home area it never leaves)?
func is_guardian() -> bool:
	return guard_area.has_area()


## Q4: make it a guardian of `area` (x, z in metres), standing at `spot`.
func set_guard(area: Rect2, spot: Vector3) -> void:
	guard_area = area
	guard_spot = spot
	home = spot


## Q4: is `at` inside its home area? Always true for an ordinary zombie.
func in_guard(at: Vector3) -> bool:
	return not is_guardian() or guard_area.has_point(Vector2(at.x, at.z))


func _clamp_guard(at: Vector3) -> Vector3:
	if not is_guardian():
		return at
	var lo := guard_area.position + Vector2.ONE
	var hi := guard_area.end - Vector2.ONE
	return Vector3(clampf(at.x, lo.x, hi.x), at.y, clampf(at.z, lo.y, hi.y))


## Q4: a guardian drops what it was doing and walks back to its spot (WANDER toward it, then IDLE there).
func _go_back() -> void:
	if state == State.CLIMB:
		climb_landing = pos  # tells the body to restore the window collision exception
	state = State.WANDER
	break_key = ""
	climb_key = ""
	sound_key = ""
	blocked_by = ""
	route = []
	home = guard_spot
	target_pos = guard_spot
	_timer = 120.0
	_lost = 0.0
	_unseen = 0.0


## W1b: is `at` on a town floor (inside a house or the factory)?
static func _indoors(pieces: Dictionary, at: Vector3) -> bool:
	var cell := BuildGrid.world_to_cell(at)
	var p: Variant = pieces.get("f:%d:%d" % [cell.x, cell.y])
	return p is Dictionary and p.get("id", "") == "town_floor"


## A piece still there to break: not wrecked, and not a window whose glass is already gone (W1a).
static func _standing(pieces: Dictionary, key: String) -> bool:
	if not pieces.has(key):
		return false
	var p: Variant = pieces[key]
	return not (p is Dictionary and p.get("id", "") == "window" and int(p.get("hp", 1)) <= 0)


static func _broken_window(pieces: Dictionary, key: String) -> bool:
	return _window_piece(pieces, key) and int((pieces[key] as Dictionary).get("hp", 1)) <= 0


static func _window_piece(pieces: Dictionary, key: String) -> bool:
	if key == "" or not pieces.has(key):
		return false
	var p: Variant = pieces[key]
	return p is Dictionary and p.get("id", "") == "window"


## The climb path is derived only from saved piece data, keeping the rule headless and deterministic.
func _start_climb(key: String, piece: Dictionary, from_state: int = -1) -> void:
	if piece.get("id", "") != "window" or int(piece.get("hp", 1)) > 0:
		return
	climb_from_state = (break_from if state == State.BREAK else state) if from_state < 0 else from_state
	if not climb_from_state in [State.CHASE, State.INVESTIGATE]:
		return
	var cell: Vector2i = piece["cell"]
	var side := int(piece.get("side", BuildGrid.Side.NORTH))
	var center := Vector3((float(cell.x) + 0.5) * BuildGrid.GRID, pos.y, float(cell.y) * BuildGrid.GRID)
	var normal := Vector3(0, 0, 1)
	if side == BuildGrid.Side.WEST:
		center = Vector3(float(cell.x) * BuildGrid.GRID, pos.y, (float(cell.y) + 0.5) * BuildGrid.GRID)
		normal = Vector3(1, 0, 0)
	var side_sign := 1.0 if (pos - center).dot(normal) >= 0.0 else -1.0
	climb_key = key
	climb_start = pos
	climb_to = center - normal * side_sign * 1.05
	climb_elapsed = 0.0
	climb_duration = float(stats["climb_seconds"])
	target_pos = climb_to
	state = State.CLIMB
	break_key = ""


func climb_fraction() -> float:
	return clampf(climb_elapsed / maxf(0.001, climb_duration), 0.0, 1.0) if state == State.CLIMB else 0.0


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
		climb_key = ""
		return true
	if state == State.IDLE or state == State.WANDER or state == State.INVESTIGATE:
		state = State.CHASE  # it knows where you are now
		last_seen = from
		_lost = 0.0
		_unseen = 0.0
	return false


func _start_break(key: String) -> void:
	if state != State.CHASE and state != State.INVESTIGATE:
		return  # Q2: idle and wandering zombies never break anything
	break_from = state
	state = State.BREAK
	break_key = key
	_lost = 0.0


## Q2: the piece is gone. A chaser chases on; an investigator walks on to the sound (or, if what it broke
## was the noisy machine itself, it's done). It used to always chase, toward wherever it last saw you
## (or the world origin if it never had), breaking whatever stood on the way.
func _after_break() -> void:
	var was := break_key
	break_key = ""
	blocked_by = ""
	if break_from == State.INVESTIGATE:
		if was == sound_key:
			_go_idle(true)
		else:
			state = State.INVESTIGATE
			_timer = maxf(_timer, 5.0)
	else:
		state = State.CHASE


## M16 (reverses W1c's "bashed by zombies like a crate"): it walked into a piece of furniture, which is never
## broken. A stroller turns away as from anything else (Q2); a chaser or investigator forgets the bump and keeps
## going, and its body's navmesh path goes round the piece (furniture is a navmesh obstacle). One that was
## already breaking furniture (a save from before M16) stops and carries on as after a break.
func leave_furniture() -> void:
	if state == State.WANDER:
		return
	if state == State.BREAK:
		_after_break()
		return
	blocked_by = ""


## Q2: a wandering zombie walked into a piece: pick another stroll spot, away from the way it was going.
func _turn_away() -> void:
	var was := Vector3(target_pos.x - pos.x, 0.0, target_pos.z - pos.z)
	blocked_by = ""
	_timer = WANDER_TIMEOUT
	for i in 8:
		var angle := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(2.0, WANDER_RADIUS)
		target_pos = home + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		if Vector3(target_pos.x - pos.x, 0.0, target_pos.z - pos.z).dot(was) < 0.0:
			return
	target_pos = pos - was.normalized() * 2.0 if was.length_squared() > 1e-6 else pos  # straight back


func _go_idle(new_home: bool) -> void:
	state = State.IDLE
	break_key = ""
	climb_key = ""
	sound_key = ""
	route = []
	_timer = _rng.randf_range(2.0, 6.0)
	target_pos = pos
	if new_home and not is_guardian():  # Q4: a guardian's home stays its spot
		home = pos


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
