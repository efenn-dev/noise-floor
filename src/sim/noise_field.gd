class_name NoiseField
extends RefCounted
## Every sound in the world this tick, and how loud each one is wherever a zombie stands.
##   heard level = loudness - 20 * log10(max(distance, 1)) - 10 * (walls in between)
## F5: a soundproof wall counts as two walls for sound (BuildGrid.edge_sound); heard_radii() turns the formula
## round for the build ghost's rings: how far each way a sound carries before it's too quiet to hear.
## Continuous sounds: machines while they work and generators while they run (a muffler takes 15 off). One-off sounds: footsteps,
## pipe hits, zombies bashing and wrecking things. One-offs stay audible for HEAR_WINDOW so every
## zombie (they listen every HEAR_WINDOW) gets one chance to hear each.
## Walls are built walls, closed doors, barricades and whole windows on the 2 m grid. Since W1a the
## town's houses are made of the same pieces, so they muffle too.

const HEAR_WINDOW := 0.5
const RADII := 32         # F5: directions heard_radii() looks in
const HEARD_MAX := 400.0  # F5: rays stop here (the map is 720 m across: past this a sound is heard everywhere)
const DRAW_TIME := 1.5  # one-offs stay in `recent` this long so the overlay can show them

var data: GameData
## Set by SimWorld (M12): Dampened Gears makes machines quieter.
var skills: Skills
var build: BuildGrid
## {pos: Vector3, loudness: float, key: String (piece key or ""), kind: String}
var continuous: Array = []
var recent: Array = []  # one-offs, each with an extra "age" in seconds
var _pending: Array = []
## M16: dB every sound carries farther by right now: on cold, still nights (autumn +3, winter +6 in
## data/seasons.json "hearing_night"), 0 otherwise. Set by SimWorld every tick. level() adds it, and every
## listener (zombies, the Director's heat, noise sensors, the overlay's rings) goes through level().
var carry_bonus := 0.0


func _init(p_data: GameData, p_build: BuildGrid) -> void:
	data = p_data
	build = p_build


static func heard_level(loudness: float, distance: float, walls: int) -> float:
	return loudness - 20.0 * log(maxf(distance, 1.0)) / log(10.0) - 10.0 * walls


## M16: how loud a sound is to a listener now: heard_level plus tonight's carry_bonus. The one place the
## season's bonus is added.
func level(loudness: float, distance: float, walls: int) -> float:
	return heard_level(loudness, distance, walls) + carry_bonus


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
	var quiet := machine_quiet()  # P2: once per tick (Skills.bonus walks skills, perks and gear)
	for cell: Vector2i in factory.machines:
		var m: Factory.Machine = factory.machines[cell]
		if m.crafting and m.powered and not m.frozen:  # M15: a stopped machine (brownout, quiet mode) is silent; M16: a frozen planter too
			continuous.append({"pos": Vector3((cell.x + 0.5) * BuildGrid.GRID, 1.0, (cell.y + 0.5) * BuildGrid.GRID),
					"loudness": machine_loudness(m, quiet), "key": "o:%d:%d" % [cell.x, cell.y], "kind": m.id})
	var kept := []
	for s: Dictionary in recent:
		s["age"] += dt
		if s["age"] < DRAW_TIME:
			kept.append(s)
	recent = kept
	recent.append_array(_pending)
	_pending.clear()


## `quiet` is machine_quiet() when the caller already has it (refresh), so it's worked out once a tick.
func machine_loudness(m: Factory.Machine, quiet: float = -1.0) -> float:
	var base: float = data.buildables[m.id]["loudness"]
	var q := quiet if quiet >= 0.0 else machine_quiet()
	return maxf(0.0, base - muffle_cut(m.muffled, m.boxed) - q)


## F5: how much a muffler, and a sound box over it, take off a machine's or generator's loudness.
func muffle_cut(muffled: bool, boxed: bool) -> float:
	return (float(data.noise["muffler"]["cut"]) if muffled else 0.0) + (float(data.noise["sound_box"]["cut"]) if boxed else 0.0)


## How much quieter Dampened Gears makes machines and generators (M12; skills set by SimWorld).
func machine_quiet() -> float:
	return skills.bonus("machine_quiet") if skills != null else 0.0


## The loudest sound a listener at `at` can hear over `threshold`, with "heard" (its level) added.
## Returns {} if nothing is loud enough.
func loudest_heard(at: Vector3, threshold: float) -> Dictionary:
	var best := {}
	var best_level := -INF
	for s: Dictionary in continuous + recent:
		if s.has("age") and s["age"] >= HEAR_WINDOW:
			continue
		var d := Vector2(s["pos"].x - at.x, s["pos"].z - at.z).length()
		var open := level(s["loudness"], d, 0)
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
	return level(s["loudness"], distance, outdoor_walls(s["pos"], distance))


## The fewest walls between `pos` and a point `distance` away, over 8 directions (the gap sound leaks out of).
## The Director caches this per source (M15), since it only changes when the build grid does.
func outdoor_walls(pos: Vector3, distance: float) -> int:
	var best := 1 << 30
	for i in 8:
		var a := TAU * i / 8.0
		best = mini(best, walls_between(pos, pos + Vector3(cos(a), 0.0, sin(a)) * distance))
		if best == 0:
			break  # an open side: it can't get any lower
	return best


## F5: how far a sound of `loudness` (plus `bonus`, the season's night carry) at `pos` carries before it drops under
## `threshold`, in each of RADII directions (direction i is the angle TAU * i / RADII from +X, as in outdoor_walls),
## walls on the way included. Each ray stops at HEARD_MAX. Returns the radii in metres.
func heard_radii(pos: Vector3, loudness: float, threshold: float, bonus: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var spare := loudness + bonus - threshold  # dB to lose before it's too quiet
	var open := pow(10.0, spare / 20.0)
	for i in RADII:
		var a := TAU * i / RADII
		var walls := 0
		var last := 0.0  # where the last wall it got through stands
		var r := open
		for c: Vector2 in sound_crossings(pos, pos + Vector3(cos(a), 0.0, sin(a)) * minf(open, HEARD_MAX)):
			r = pow(10.0, (spare - 10.0 * walls) / 20.0)
			if r < c.x:
				break  # too quiet before it reaches this wall
			walls += int(c.y)
			last = c.x
			r = pow(10.0, (spare - 10.0 * walls) / 20.0)
		out.append(minf(HEARD_MAX, maxf(last, r) if spare > 0.0 else 0.0))
	return out


## F5: the walls a sound crosses on the straight line from a to b, nearest first: Vector2(distance from a in metres,
## walls' worth of sound it stops). The same grid walk as walls_between.
func sound_crossings(a: Vector3, b: Vector3) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var g := BuildGrid.GRID
	var x0 := a.x / g
	var z0 := a.z / g
	var dx := b.x / g - x0
	var dz := b.z / g - z0
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var cx := floori(x0)
	var cz := floori(z0)
	var steps := absi(floori(b.x / g) - cx) + absi(floori(b.z / g) - cz)
	var step_x := 1 if dx > 0.0 else -1
	var step_z := 1 if dz > 0.0 else -1
	var t_max_x := INF if dx == 0.0 else ((cx + 1 - x0) / dx if dx > 0.0 else (x0 - cx) / -dx)
	var t_max_z := INF if dz == 0.0 else ((cz + 1 - z0) / dz if dz > 0.0 else (z0 - cz) / -dz)
	var t_dx := INF if dx == 0.0 else absf(1.0 / dx)
	var t_dz := INF if dz == 0.0 else absf(1.0 / dz)
	for i in steps:
		var key := ""
		var t := 0.0
		if t_max_x < t_max_z:
			key = "w:%d:%d:w" % [cx + (1 if step_x > 0 else 0), cz]
			t = t_max_x
			cx += step_x
			t_max_x += t_dx
		else:
			key = "w:%d:%d:n" % [cx, cz + (1 if step_z > 0 else 0)]
			t = t_max_z
			cz += step_z
			t_max_z += t_dz
		if build.pieces.has(key):
			var w := build.edge_sound(key)
			if w > 0:
				out.append(Vector2(t * length, w))
	return out


## Built walls crossed by the straight line from a to b (walks the grid cell by cell). Closed doors
## count; open doors don't. Barricades count for sound but not for sight (`for_sight`). F5: for sound, a soundproof
## wall counts twice (BuildGrid.edge_sound).
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
			count += _wall_count("w:%d:%d:w" % [line_x, cz], for_sight)
			cx += step_x
			t_max_x += t_dx
		else:
			var line_z := cz + (1 if step_z > 0 else 0)  # crossing the north edge of cell (cx, line_z)
			count += _wall_count("w:%d:%d:n" % [cx, line_z], for_sight)
			cz += step_z
			t_max_z += t_dz
	return count


## One edge's part in walls_between: for sight 1 if it blocks the view, for sound its walls' worth (F5).
func _wall_count(key: String, for_sight: bool) -> int:
	if not build.pieces.has(key):
		return 0
	if for_sight:
		return 1 if build.edge_blocks(key, true) else 0
	return build.edge_sound(key)
