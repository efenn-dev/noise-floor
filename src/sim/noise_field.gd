class_name NoiseField
extends RefCounted
## Every sound in the world this tick, and how loud each one is wherever a zombie stands.
##   heard level = loudness - 20 * log10(max(distance, 1)) - 10 * (walls in between)
## Continuous sounds: machines while they work and generators while they run (a muffler takes 15 off). One-off sounds: footsteps,
## pipe hits, zombies bashing and wrecking things. One-offs stay audible for HEAR_WINDOW so every
## zombie (they listen every HEAR_WINDOW) gets one chance to hear each.
## Walls are built walls, closed doors, barricades and whole windows on the 2 m grid. Since W1a the
## town's houses are made of the same pieces, so they muffle too.

const HEAR_WINDOW := 0.5
const DRAW_TIME := 1.5  # one-offs stay in `recent` this long so the overlay can show them

var data: GameData
var build: BuildGrid
## {pos: Vector3, loudness: float, key: String (piece key or ""), kind: String}
var continuous: Array = []
var recent: Array = []  # one-offs, each with an extra "age" in seconds
var _pending: Array = []


func _init(p_data: GameData, p_build: BuildGrid) -> void:
	data = p_data
	build = p_build


static func heard_level(loudness: float, distance: float, walls: int) -> float:
	return loudness - 20.0 * log(maxf(distance, 1.0)) / log(10.0) - 10.0 * walls


## Queues a one-off sound; it becomes audible on the next tick.
func emit(pos: Vector3, loudness: float, kind: String, key: String = "") -> void:
	_pending.append({"pos": pos, "loudness": loudness, "key": key, "kind": kind, "age": 0.0})


func emit_kind(pos: Vector3, kind: String) -> void:
	emit(pos, float(data.noise["sounds"][kind]), kind)


## Once per tick: lists the machines that are working, ages one-offs and takes in new ones.
func refresh(factory: Factory, dt: float, power: PowerGrid = null, vehicles: Vehicles = null) -> void:
	continuous.clear()
	if power != null:
		continuous.append_array(power.noise_sources())  # running generators
	if vehicles != null:
		continuous.append_array(vehicles.noise_sources())  # running car engines
	for cell: Vector2i in factory.machines:
		var m: Factory.Machine = factory.machines[cell]
		if m.crafting:
			continuous.append({"pos": Vector3((cell.x + 0.5) * BuildGrid.GRID, 1.0, (cell.y + 0.5) * BuildGrid.GRID),
					"loudness": machine_loudness(m), "key": "o:%d:%d" % [cell.x, cell.y], "kind": m.id})
	var kept := []
	for s: Dictionary in recent:
		s["age"] += dt
		if s["age"] < DRAW_TIME:
			kept.append(s)
	recent = kept
	recent.append_array(_pending)
	_pending.clear()


func machine_loudness(m: Factory.Machine) -> float:
	var base: float = data.buildables[m.id]["loudness"]
	return base - (float(data.noise["muffler"]["cut"]) if m.muffled else 0.0)


## The loudest sound a listener at `at` can hear over `threshold`, with "heard" (its level) added.
## Returns {} if nothing is loud enough.
func loudest_heard(at: Vector3, threshold: float) -> Dictionary:
	var best := {}
	var best_level := -INF
	for s: Dictionary in continuous + recent:
		if s.has("age") and s["age"] >= HEAR_WINDOW:
			continue
		var d := Vector2(s["pos"].x - at.x, s["pos"].z - at.z).length()
		var open := heard_level(s["loudness"], d, 0)
		if open < threshold or open <= best_level:
			continue  # too quiet even before walls: skip the wall count
		var level := open - 10.0 * walls_between(s["pos"], at)
		if level >= threshold and level > best_level:
			best_level = level
			best = s.duplicate()
			best["heard"] = level
	return best


## How loud a sound is to the world outside: the loudest it gets at `distance` in any of 8 directions,
## so a gap in your walls lets it out.
func outdoor_level(s: Dictionary, distance: float) -> float:
	var best := -INF
	for i in 8:
		var a := TAU * i / 8.0
		var to: Vector3 = s["pos"] + Vector3(cos(a), 0.0, sin(a)) * distance
		best = maxf(best, heard_level(s["loudness"], distance, walls_between(s["pos"], to)))
	return best


## Built walls crossed by the straight line from a to b (walks the grid cell by cell). Closed doors
## count; open doors don't. Barricades count for sound but not for sight (`for_sight`).
func walls_between(a: Vector3, b: Vector3, for_sight: bool = false) -> int:
	var g := BuildGrid.GRID
	var x0 := a.x / g
	var z0 := a.z / g
	var dx := b.x / g - x0
	var dz := b.z / g - z0
	var cx := floori(x0)
	var cz := floori(z0)
	var steps := absi(floori(b.x / g) - cx) + absi(floori(b.z / g) - cz)
	var step_x := 1 if dx > 0.0 else -1
	var step_z := 1 if dz > 0.0 else -1
	var t_max_x := INF if dx == 0.0 else ((cx + 1 - x0) / dx if dx > 0.0 else (x0 - cx) / -dx)
	var t_max_z := INF if dz == 0.0 else ((cz + 1 - z0) / dz if dz > 0.0 else (z0 - cz) / -dz)
	var t_dx := INF if dx == 0.0 else absf(1.0 / dx)
	var t_dz := INF if dz == 0.0 else absf(1.0 / dz)
	var count := 0
	for i in steps:
		if t_max_x < t_max_z:
			var line_x := cx + (1 if step_x > 0 else 0)  # crossing the west edge of cell (line_x, cz)
			if build.edge_blocks("w:%d:%d:w" % [line_x, cz], for_sight):
				count += 1
			cx += step_x
			t_max_x += t_dx
		else:
			var line_z := cz + (1 if step_z > 0 else 0)  # crossing the north edge of cell (cx, line_z)
			if build.edge_blocks("w:%d:%d:n" % [cx, line_z], for_sight):
				count += 1
			cz += step_z
			t_max_z += t_dz
	return count
