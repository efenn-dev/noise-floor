class_name Horde
extends RefCounted
## All the zombies. Thinks for each one on the sim tick (in id order, so it's deterministic), lets each
## listen for sounds every NoiseField.HEAR_WINDOW (staggered by id), and clears away corpses.

## Q4: the one list of what zombies may break (buildables.json kinds): structure and the things that make
## noise. Everything else (furniture, beds, storage crates, stoves, heaters, workbenches, poles, hoppers, the
## repair station, solar panels, belts, traps) is walked around, never wrecked. "fence" is the electric fence,
## a wall you build. NEVER_BREAK_IDS: pieces of a breakable kind that are still spared (the water tap is a
## "machine" by kind but is plumbing, not a noise-maker).
const BREAKABLE_KINDS := ["wall", "door", "window", "barricade", "fence", "machine", "generator", "turret", "sensor",
		"noisemaker", "floodlight"]
const NEVER_BREAK_IDS := ["water_tap"]
## W3e: far zombies think less often. One further than FAR_THINK from the player that is idle, wandering or dead
## thinks every THINK_EVERY ticks (a fifth of a second), with that many ticks' time at once, so its timers keep
## pace. It still listens on its usual ticks, and a noise that draws it makes it think every tick again.
const FAR_THINK := 60.0
const THINK_EVERY := 4

var data: GameData
var seed_value: int
var difficulty: Difficulty
var zombies: Dictionary = {}  # id -> ZombieBrain
var _next_id := 1
var _ticks := 0
var lazy_skips := 0  # W3e: thinks skipped for far zombies (tests, the stress report)


func _init(p_data: GameData, p_seed: int = 1, p_difficulty: Difficulty = null) -> void:
	data = p_data
	seed_value = p_seed
	difficulty = p_difficulty


func spawn(type: String, pos: Vector3) -> ZombieBrain:
	var z := ZombieBrain.new(_next_id, type, data.zombies[type], pos, hash([seed_value, _next_id]), difficulty)
	zombies[_next_id] = z
	_next_id += 1
	return z


## Brings back a saved zombie with its old id.
func restore(id: int, type: String, pos: Vector3) -> ZombieBrain:
	var z := ZombieBrain.new(id, type, data.zombies[type], pos, hash([seed_value, id]), difficulty)
	zombies[id] = z
	_next_id = maxi(_next_id, id + 1)
	return z


## Scatters `count` starting zombies along the sidewalks, away from the spawn point. V28: the Director's
## data table gives crawlers a small day-one share; the same deterministic id always rolls the same kind.
func spawn_town(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(side * rng.randf_range(4.5, 6.5), 0.0, rng.randf_range(-110.0, -25.0))
		spawn_starting(pos, false)


## V28: rolls a type from noise.json's starting spawn table. Houses use the larger indoor chance.
func spawn_starting(pos: Vector3, indoors: bool) -> ZombieBrain:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, _next_id, "starting_zombie", indoors])
	for entry: Dictionary in data.noise["infamy"].get("starting", []):
		var key := "indoor_chance" if indoors else "street_chance"
		if rng.randf() < float(entry.get(key, entry.get("chance", 0.0))):
			return spawn(str(entry["type"]), pos)
	return spawn("shambler", pos)


func alive_count() -> int:
	var n := 0
	for id: int in zombies:
		if not zombies[id].is_dead():
			n += 1
	return n


## ctx: player_pos, player_dead, night, player_lit, pieces, and optionally noise (NoiseField).
## Returns attack events with "zombie" added.
func tick(dt: float, ctx: Dictionary) -> Array:
	var events := []
	_ticks += 1
	var listen_every := maxi(1, roundi(NoiseField.HEAR_WINDOW / dt))
	var noise: NoiseField = ctx.get("noise")
	var ids := zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = zombies[id]
		z.night = bool(ctx["night"])
		if noise != null and not z.is_dead() and (_ticks + id) % listen_every == 0:
			var heard := noise.loudest_heard(z.pos, z.hearing(ctx["night"]))
			if not heard.is_empty():  # Q4: a sound from something it may not break is walked to, not wrecked
				z.hear(heard["pos"], heard["key"] if breakable(ctx["pieces"], heard["key"]) else "")
		var who := nearest_player(z.pos, ctx)  # co-op A: the nearest living player, or the one player
		var player_pos: Vector3 = who["pos"]
		var far := Vector2(z.pos.x - player_pos.x, z.pos.z - player_pos.z).length() > FAR_THINK
		var lazy := far and (z.is_dead() or z.state == ZombieBrain.State.IDLE or z.state == ZombieBrain.State.WANDER)
		if lazy and (_ticks + id) % THINK_EVERY != 0:
			lazy_skips += 1
			continue
		var step := dt * THINK_EVERY if lazy else dt
		var eye := z.pos + Vector3.UP * z.eye_height()
		var sees := not z.is_dead() and ZombieBrain.can_see(eye, z.facing, player_pos, z.los_clear,
				ctx["night"], who["lit"], z.stats)
		if _spared_for(z, ctx["pieces"], z.blocked_by) \
				or (z.state == ZombieBrain.State.BREAK and _spared_for(z, ctx["pieces"], z.break_key)):
			z.leave_furniture()  # M16, Q4: zombies only break what's on BREAKABLE_KINDS
		for e: Dictionary in z.think(step, player_pos, sees, who["dead"], ctx["pieces"]):
			e["zombie"] = id
			e["player"] = who["index"]  # co-op A: whom it went for
			events.append(e)
		if z.is_dead() and z.dead_time >= (ZombieBrain.SEARCHED_CORPSE_TIME if z.searched else ZombieBrain.CORPSE_TIME):
			zombies.erase(id)
	return events


## Co-op A: of ctx["players"] ({index, pos, dead, lit} each), the nearest one alive to `at`, or the nearest of all when
## none is alive; without a roster, the one player the older ctx keys describe (index 0).
static func nearest_player(at: Vector3, ctx: Dictionary) -> Dictionary:
	var roster: Array = ctx.get("players", [])
	if roster.is_empty():
		return {"index": 0, "pos": ctx["player_pos"], "dead": ctx["player_dead"], "lit": ctx["player_lit"]}
	var best: Dictionary = {}
	var best_d := INF
	for p: Dictionary in roster:
		var d := Vector2(p["pos"].x - at.x, p["pos"].z - at.z).length_squared()
		var alive_wins: bool = not p["dead"] and not best.is_empty() and best["dead"]
		var dead_loses: bool = p["dead"] and not best.is_empty() and not best["dead"]
		if best.is_empty() or alive_wins or (not dead_loses and d < best_d):
			best = p
			best_d = d
	return best


## Q4: may a zombie break the piece at `key`? Town pieces count by their kind too (town walls are "wall").
func breakable(pieces: Dictionary, key: String) -> bool:
	if key == "" or not pieces.has(key):
		return false
	var p: Variant = pieces[key]
	if not (p is Dictionary):
		return false
	var id: String = p.get("id", "")
	if id in NEVER_BREAK_IDS or not data.buildables.has(id):
		return false
	return data.buildables[id]["kind"] in BREAKABLE_KINDS


## V28: a crawler treats a door like furniture: it paths around it and never starts bashing it.
func breakable_for(z: ZombieBrain, pieces: Dictionary, key: String) -> bool:
	if not breakable(pieces, key):
		return false
	var id: String = pieces[key].get("id", "")
	return data.buildables[id]["kind"] != "door" or float(z.stats.get("door_break_multiplier", 1.0)) > 0.0


## A piece it bumped (or is breaking) that it must leave alone (M16 furniture; Q4 everything not breakable).
func _spared_for(z: ZombieBrain, pieces: Dictionary, key: String) -> bool:
	return key != "" and pieces.has(key) and not breakable_for(z, pieces, key)
