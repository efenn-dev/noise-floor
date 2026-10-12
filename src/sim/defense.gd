class_name Defense
extends RefCounted
## Traps and turrets, on the sim tick.
##   Spike strip: a zombie standing on its cell moves at `slow` speed and takes `damage` a second.
##     The damage it deals wears the strip down (its hp); at 0 it's gone.
##   Nail turret: every `interval` seconds, if it has ammo, shoots the nearest living zombie within
##     `range` that it can see (built walls and closed doors block the shot; barricades don't).
##     One nail per shot, `damage` per hit, a one-off noise of its loudness, and the zombie it hit
##     comes for the turret.

var data: GameData
var build: BuildGrid
var factory: Factory
## Shots in the last moment, for drawing tracers: {from: Vector3, to: Vector3, age: float}
var recent_shots: Array = []

const SHOT_DRAW_TIME := 0.15


func _init(p_data: GameData, p_build: BuildGrid, p_factory: Factory) -> void:
	data = p_data
	build = p_build
	factory = p_factory


func tick(dt: float, horde: Horde, noise: NoiseField) -> void:
	for s: Dictionary in recent_shots:
		s["age"] += dt
	recent_shots = recent_shots.filter(func(s: Dictionary) -> bool: return s["age"] < SHOT_DRAW_TIME)
	_traps(dt, horde)
	_turrets(dt, horde, noise)


func _traps(dt: float, horde: Horde) -> void:
	var traps := {}  # cell -> key
	for key: String in build.pieces:
		if build.kind_of(build.pieces[key]["id"]) == "trap":
			traps[build.pieces[key]["cell"]] = key
	var ids := horde.zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = horde.zombies[id]
		z.slow = 1.0
		if z.is_dead():
			continue
		var cell := BuildGrid.world_to_cell(z.pos)
		if not traps.has(cell) or not build.pieces.has(traps[cell]):
			continue
		var key: String = traps[cell]
		var b: Dictionary = data.buildables[build.pieces[key]["id"]]
		z.slow = b["slow"]
		var dmg: float = b["damage"] * dt
		z.hurt(dmg)
		build.pieces[key]["wear"] = build.pieces[key].get("wear", 0.0) + dmg
		if build.pieces[key]["wear"] >= 1.0:  # hp is whole numbers: wear it down a point at a time
			var whole := floori(build.pieces[key]["wear"])
			build.pieces[key]["wear"] -= whole
			build.damage(key, whole)


func _turrets(dt: float, horde: Horde, noise: NoiseField) -> void:
	var cells := factory.turrets.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var t: Factory.Turret = factory.turrets[cell]
		var key := "o:%d:%d" % [cell.x, cell.y]
		if not build.pieces.has(key):
			continue
		var b: Dictionary = data.buildables[build.pieces[key]["id"]]
		t.cooldown = maxf(0.0, t.cooldown - dt)
		var muzzle := build.piece_center(key) + Vector3(0, 0.4, 0)
		t.target = _pick_target(muzzle, b["range"], horde, noise)
		if t.target == -1 or t.ammo <= 0 or t.cooldown > 0.0:
			continue
		var z: ZombieBrain = horde.zombies[t.target]
		t.ammo -= 1
		t.shots += 1
		t.cooldown = b["interval"]
		z.take_hit(b["damage"], muzzle, 1.0)
		noise.emit(muzzle, b["loudness"], "turret")
		recent_shots.append({"from": muzzle, "to": z.pos + Vector3(0, 1.3, 0), "age": 0.0})


func _pick_target(from: Vector3, reach: float, horde: Horde, noise: NoiseField) -> int:
	var best := -1
	var best_d := INF
	var ids := horde.zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = horde.zombies[id]
		if z.is_dead():
			continue
		var d := Vector2(z.pos.x - from.x, z.pos.z - from.z).length()
		if d > reach or d >= best_d:
			continue
		if noise.walls_between(from, z.pos, true) > 0:
			continue  # can't see it through a wall or closed door
		best = id
		best_d = d
	return best
