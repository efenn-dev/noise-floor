class_name Scares
extends RefCounted
## S4: jumpscares, Zomboid-style. Two moments the world plays a sting for:
## - "close": a zombie you had not seen for a while (or ever) is suddenly in view within CLOSE_DIST, as when
##   one is standing behind a door you open or steps round a corner at you;
## - "horde": HORDE_COUNT or more zombies start chasing you within HORDE_WINDOW seconds (a mob aggroed).
## Pure rules over the horde's state; SoundView plays `fired`. Seen = in front of you (within CONE_DEG of
## where you look), with nothing solid between (the body's line-of-sight check, `los_clear`), within SEE_DIST.

const CLOSE_DIST := 6.0
const SEE_DIST := 30.0
const CONE_DEG := 55.0
const UNSEEN_SECONDS := 3.0  # out of sight this long, a zombie can surprise you again
const CLOSE_COOLDOWN := 8.0
const HORDE_COUNT := 4
const HORDE_WINDOW := 3.0
const HORDE_COOLDOWN := 45.0
const KEEP := 8  # how many fired stings are kept for the world to pick up

## Newest last: {"kind": "close" | "horde", "pos": Vector3, "zombie": id (close only), "time": seconds}.
var fired: Array = []
var _time := 0.0
var _last_seen: Dictionary = {}  # zombie id -> last time it was in view
var _prev_state: Dictionary = {}  # zombie id -> its state last tick
var _chases: Array = []  # times zombies started chasing, within HORDE_WINDOW
var _close_cd := 0.0
var _horde_cd := 0.0


## One sim tick. Returns the stings fired this tick (also appended to `fired`).
func tick(dt: float, zombies: Dictionary, player_pos: Vector3, player_facing: Vector3, player_dead: bool) -> Array:
	_time += dt
	_close_cd = maxf(0.0, _close_cd - dt)
	_horde_cd = maxf(0.0, _horde_cd - dt)
	var out := []
	var look := Vector3(player_facing.x, 0.0, player_facing.z)
	look = look.normalized() if look.length_squared() > 1e-6 else Vector3(0, 0, -1)
	for id: int in zombies:
		var z: ZombieBrain = zombies[id]
		if z.is_dead():
			_last_seen.erase(id)
			_prev_state.erase(id)
			continue
		var prev: int = _prev_state.get(id, z.state)  # the first tick we know it: no transition
		if z.state == ZombieBrain.State.CHASE and prev != ZombieBrain.State.CHASE and prev != ZombieBrain.State.ATTACK:
			_chases.append(_time)
		_prev_state[id] = z.state
		var d := Vector3(z.pos.x - player_pos.x, 0.0, z.pos.z - player_pos.z)
		var dist := d.length()
		var in_view := z.los_clear and dist <= SEE_DIST and (dist < 1.0 or rad_to_deg(look.angle_to(d)) <= CONE_DEG)
		if not in_view:
			continue
		var last: float = _last_seen.get(id, -INF)
		if not player_dead and dist <= CLOSE_DIST and _time - last > UNSEEN_SECONDS and _close_cd <= 0.0:
			out.append({"kind": "close", "pos": z.pos, "zombie": id, "time": _time})
			_close_cd = CLOSE_COOLDOWN
		_last_seen[id] = _time
	while not _chases.is_empty() and _time - float(_chases[0]) > HORDE_WINDOW:
		_chases.pop_front()
	if _chases.size() >= HORDE_COUNT and _horde_cd <= 0.0 and not player_dead:
		out.append({"kind": "horde", "pos": player_pos, "time": _time})
		_horde_cd = HORDE_COOLDOWN
		_chases.clear()
	if not out.is_empty():
		fired.append_array(out)
		while fired.size() > KEEP:
			fired.pop_front()
	return out


## How many of each kind have fired, for tests and the session log.
func count(kind: String) -> int:
	var n := 0
	for e: Dictionary in fired:
		if e["kind"] == kind:
			n += 1
	return n
