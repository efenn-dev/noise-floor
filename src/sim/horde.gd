class_name Horde
extends RefCounted
## All the zombies. Thinks for each one on the sim tick (in id order, so it's deterministic) and
## clears away corpses after a while.

var data: GameData
var seed_value: int
var zombies: Dictionary = {}  # id -> ZombieBrain
var _next_id := 1


func _init(p_data: GameData, p_seed: int = 1) -> void:
	data = p_data
	seed_value = p_seed


func spawn(type: String, pos: Vector3) -> ZombieBrain:
	var z := ZombieBrain.new(_next_id, type, data.zombies[type], pos, hash([seed_value, _next_id]))
	zombies[_next_id] = z
	_next_id += 1
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


## ctx: player_pos, player_dead, night, player_lit, pieces. Returns attack events with "zombie" added.
func tick(dt: float, ctx: Dictionary) -> Array:
	var events := []
	var ids := zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = zombies[id]
		var eye := z.pos + Vector3.UP * ZombieBrain.EYE_HEIGHT
		var sees := not z.is_dead() and ZombieBrain.can_see(eye, z.facing, ctx["player_pos"], z.los_clear,
				ctx["night"], ctx["player_lit"], z.stats)
		for e: Dictionary in z.think(dt, ctx["player_pos"], sees, ctx["player_dead"], ctx["pieces"]):
			e["zombie"] = id
			events.append(e)
		if z.is_dead() and z.dead_time >= ZombieBrain.CORPSE_TIME:
			zombies.erase(id)
	return events
