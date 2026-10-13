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

var data: GameData
var seed_value: int
var zombies: Dictionary = {}  # id -> ZombieBrain
var _next_id := 1
var _ticks := 0


func _init(p_data: GameData, p_seed: int = 1) -> void:
	data = p_data
	seed_value = p_seed


func spawn(type: String, pos: Vector3) -> ZombieBrain:
	var z := ZombieBrain.new(_next_id, type, data.zombies[type], pos, hash([seed_value, _next_id]))
	zombies[_next_id] = z
	_next_id += 1
	return z


## Brings back a saved zombie with its old id.
func restore(id: int, type: String, pos: Vector3) -> ZombieBrain:
	var z := ZombieBrain.new(id, type, data.zombies[type], pos, hash([seed_value, id]))
	zombies[id] = z
	_next_id = maxi(_next_id, id + 1)
	return z


## Scatters `count` shamblers along the sidewalks of the main street, away from the spawn point.
func spawn_town(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(side * rng.randf_range(4.5, 6.5), 0.0, rng.randf_range(-110.0, -25.0))
		spawn("shambler", pos)


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
		if noise != null and not z.is_dead() and (_ticks + id) % listen_every == 0:
			var heard := noise.loudest_heard(z.pos, z.hearing(ctx["night"]))
			if not heard.is_empty():  # Q4: a sound from something it may not break is walked to, not wrecked
				z.hear(heard["pos"], heard["key"] if breakable(ctx["pieces"], heard["key"]) else "")
		var eye := z.pos + Vector3.UP * ZombieBrain.EYE_HEIGHT
		var sees := not z.is_dead() and ZombieBrain.can_see(eye, z.facing, ctx["player_pos"], z.los_clear,
				ctx["night"], ctx["player_lit"], z.stats)
		if _spared(ctx["pieces"], z.blocked_by) or (z.state == ZombieBrain.State.BREAK and _spared(ctx["pieces"], z.break_key)):
			z.leave_furniture()  # M16, Q4: zombies only break what's on BREAKABLE_KINDS
		for e: Dictionary in z.think(dt, ctx["player_pos"], sees, ctx["player_dead"], ctx["pieces"]):
			e["zombie"] = id
			events.append(e)
		if z.is_dead() and z.dead_time >= ZombieBrain.CORPSE_TIME:
			zombies.erase(id)
	return events


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


## A piece it bumped (or is breaking) that it must leave alone (M16 furniture; Q4 everything not breakable).
func _spared(pieces: Dictionary, key: String) -> bool:
	return key != "" and pieces.has(key) and not breakable(pieces, key)
