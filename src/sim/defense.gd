class_name Defense
extends RefCounted
## Traps, turrets and the repair station, on the sim tick.
##   Spike strip: a zombie standing on its cell moves at `slow` speed and takes `damage` a second.
##     The damage it deals wears the strip down (its hp); at 0 it's gone.
##   Turrets (nail, crossbow, rifle): every `interval` seconds, if it has ammo (and power, if it needs
##     watts), shoots the nearest living zombie within its range that it can see (built walls and closed
##     doors block the shot; barricades don't). One round per shot, `damage` per hit, a one-off noise of its
##     loudness, and the zombie it hit comes for the turret. M15: a suppressor on it cuts the loudness and
##     wears a little each shot, like on a gun; a scope adds range (guns.json parts). Kills and an empty
##     magazine go in the base log.
##   M15 bear trap: snaps on the first zombie that steps in its cell: `damage`, pinned for `pin` seconds,
##     then stays sprung until you reset it (E).
##   M15 tripwire bell (an edge): a zombie walking across it rings it (a one-off at its loudness) and sets off
##     every sensor within trigger_radius (Automation reads `bells`).
##   M15 electric fence (an edge, needs power): a zombie touching it is stunned and takes `damage`; a
##     browned-out or unconnected fence does nothing.
##   M15 repair station (needs power): every `interval` seconds it spends one wall panel to give hp_per_panel
##     back to the most damaged wall, door, barricade or fence within its range.
## Numbers: data/buildables.json (pieces) and data/defense.json.

var data: GameData
var build: BuildGrid
var factory: Factory
## Set by SimWorld (M15).
var power: PowerGrid
var gear: Gear
var base_log: BaseLog
## Shots in the last moment, for drawing tracers: {from: Vector3, to: Vector3, age: float}
var recent_shots: Array = []
## M15: bear traps that have snapped and wait for a reset: piece key -> true.
var sprung: Dictionary = {}
## M15: tripwires that rang this tick (their centres), for Automation.
var bells: Array = []
## M15: total hp given back by repair stations (for tests).
var repaired := 0

const SHOT_DRAW_TIME := 0.15
const BELL_COOLDOWN := 2.0
const WATCHED := ["trap", "bear_trap", "tripwire", "fence", "repair_station"]

var _by_kind: Dictionary = {}  # kind -> [piece keys], rebuilt when the grid changes
var _dirty := true
var _last_cell: Dictionary = {}  # zombie id -> cell last tick (tripwires)
var _bell_cd: Dictionary = {}    # tripwire key -> seconds before it can ring again


func _init(p_data: GameData, p_build: BuildGrid, p_factory: Factory) -> void:
	data = p_data
	build = p_build
	factory = p_factory
	build.piece_added.connect(_on_added)
	build.piece_removed.connect(_on_removed)


func _on_added(_key: String) -> void:
	_dirty = true


func _on_removed(key: String, _piece: Dictionary) -> void:
	_dirty = true
	sprung.erase(key)


## Piece keys of one kind (traps, bear traps, tripwires, fences, repair stations), sorted. Cached until the grid changes.
func keys_of(kind: String) -> Array:
	if _dirty:
		_dirty = false
		_by_kind = {}
		for key: String in build.pieces:
			var k := build.kind_of(build.pieces[key]["id"])
			if k in WATCHED:
				if not _by_kind.has(k):
					_by_kind[k] = []
				_by_kind[k].append(key)
		for k: String in _by_kind:
			_by_kind[k].sort()
	return _by_kind.get(kind, [])


func tick(dt: float, horde: Horde, noise: NoiseField) -> void:
	for s: Dictionary in recent_shots:
		s["age"] += dt
	recent_shots = recent_shots.filter(func(s: Dictionary) -> bool: return s["age"] < SHOT_DRAW_TIME)
	bells = []
	_traps(dt, horde)
	_bear_traps(horde)
	_tripwires(dt, horde, noise)
	_fences(horde)
	_turrets(dt, horde, noise)
	_repairs(dt)


func _traps(dt: float, horde: Horde) -> void:
	var traps := {}  # cell -> key
	for key: String in keys_of("trap"):
		traps[build.pieces[key]["cell"]] = key
	var ids := horde.zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = horde.zombies[id]
		z.slow = 1.0
		if z.is_dead() or traps.is_empty():
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


func _bear_traps(horde: Horde) -> void:
	var armed := {}  # cell -> key
	for key: String in keys_of("bear_trap"):
		if not sprung.has(key):
			armed[build.pieces[key]["cell"]] = key
	if armed.is_empty():
		return
	var ids := horde.zombies.keys()
	ids.sort()
	for id: int in ids:
		var z: ZombieBrain = horde.zombies[id]
		var cell := BuildGrid.world_to_cell(z.pos)
		if z.is_dead() or z.pinned > 0.0 or not armed.has(cell):
			continue
		var key: String = armed[cell]
		armed.erase(cell)
		sprung[key] = true
		z.pinned = float(data.defense["bear_trap"]["pin"])
		z.hurt(data.buildables[build.pieces[key]["id"]]["damage"])
		if base_log != null:
			base_log.add("%s caught a %s" % [base_log.thing_name(key), z.type.replace("_", " ")], build.piece_center(key))


## Resets a sprung bear trap. "" or why not.
func reset_trap(key: String) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "bear_trap":
		return "Not a bear trap"
	if not sprung.has(key):
		return "It's already set"
	sprung.erase(key)
	return ""


func _tripwires(dt: float, horde: Horde, noise: NoiseField) -> void:
	for k: String in _bell_cd.keys():
		_bell_cd[k] -= dt
		if _bell_cd[k] <= 0.0:
			_bell_cd.erase(k)
	if keys_of("tripwire").is_empty():
		_last_cell = {}
		return
	var seen := {}
	for id: int in horde.zombies:
		var z: ZombieBrain = horde.zombies[id]
		if z.is_dead():
			continue
		var cell := BuildGrid.world_to_cell(z.pos)
		seen[id] = cell
		var was: Vector2i = _last_cell.get(id, cell)
		if was == cell or absi(was.x - cell.x) + absi(was.y - cell.y) != 1:
			continue
		var key := BuildGrid.key_for_wall_edge(was, Factory.DIRS.find(cell - was))
		if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "tripwire" or _bell_cd.has(key):
			continue
		_bell_cd[key] = BELL_COOLDOWN
		var at := build.piece_center(key)
		noise.emit(at, data.buildables[build.pieces[key]["id"]]["loudness"], "bell")
		bells.append(at)
		if base_log != null:
			base_log.add("%s rang" % base_log.thing_name(key), at)
	_last_cell = seen


func _fences(horde: Horde) -> void:
	var fences := keys_of("fence")
	if fences.is_empty():
		return
	var reach := float(data.defense["fence"]["reach"])
	for key: String in fences:
		if power != null and not power.is_powered(key):
			continue  # no power, no shock
		var piece: Dictionary = build.pieces[key]
		var c: Vector2i = piece["cell"]
		var a := Vector2(c.x, c.y) * BuildGrid.GRID
		var b := a + (Vector2(BuildGrid.GRID, 0) if piece["side"] == BuildGrid.Side.NORTH else Vector2(0, BuildGrid.GRID))
		for id: int in horde.zombies:
			var z: ZombieBrain = horde.zombies[id]
			if z.is_dead() or z.stunned > 0.0:
				continue
			var p := Vector2(z.pos.x, z.pos.z)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) > reach:
				continue
			z.stunned = float(data.defense["fence"]["stun"])
			z.hurt(data.buildables[piece["id"]]["damage"])
			if base_log != null:
				base_log.add_once("zap:" + key, 30.0, "%s is shocking zombies" % base_log.thing_name(key), build.piece_center(key), false)


## A turret's numbers with its parts: {range, loudness, damage, interval, muzzle_wear}.
func turret_stats(t: Factory.Turret) -> Dictionary:
	var b: Dictionary = data.buildables[t.id]
	var s := {"range": float(b["range"]), "loudness": float(b["loudness"]), "damage": float(b["damage"]),
			"interval": float(b["interval"]), "muzzle_wear": 0.0}
	if gear == null:
		return s
	for slot: String in t.parts:
		var p: Dictionary = t.parts[slot]
		var pd := gear.part_def(p)
		if slot == "muzzle":
			s["muzzle_wear"] = float(pd.get("wear_per_shot", 0.0))
		if not gear.working(p):
			continue  # a worn-out part stops working
		s["range"] *= 1.0 + float(pd.get("range", 0.0))
		s["loudness"] = maxf(0.0, s["loudness"] + float(pd.get("loudness", 0.0)))
	return s


func _turrets(dt: float, horde: Horde, noise: NoiseField) -> void:
	var cells := factory.turrets.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var t: Factory.Turret = factory.turrets[cell]
		var key := "o:%d:%d" % [cell.x, cell.y]
		if not build.pieces.has(key):
			continue
		t.cooldown = maxf(0.0, t.cooldown - dt)
		if power != null and data.buildables[t.id]["watts"] > 0.0 and not power.is_powered(key):
			t.target = -1
			continue  # the rifle turret needs power to aim
		var st := turret_stats(t)
		var muzzle := build.piece_center(key) + Vector3(0, 0.4, 0)
		t.target = _pick_target(muzzle, st["range"], horde, noise)
		if t.target == -1 or t.ammo <= 0 or t.cooldown > 0.0:
			continue
		var z: ZombieBrain = horde.zombies[t.target]
		t.ammo -= 1
		t.shots += 1
		t.cooldown = st["interval"]
		var killed := z.take_hit(st["damage"], muzzle, 1.0)
		noise.emit(muzzle, st["loudness"], "turret")
		recent_shots.append({"from": muzzle, "to": z.pos + Vector3(0, 1.3, 0), "age": 0.0})
		var worn := t.parts.has("muzzle") and gear != null and gear._wear(t.parts["muzzle"], st["muzzle_wear"])
		if base_log == null:
			continue
		if worn:
			base_log.add("%s: its suppressor is worn out" % base_log.thing_name(key), muzzle)
		if killed:
			base_log.add("%s killed a %s" % [base_log.thing_name(key), z.type.replace("_", " ")], z.pos, false)
		if t.ammo == 0:
			base_log.add("%s out of %s" % [base_log.thing_name(key), String(data.item_name(t.ammo_item)).to_lower()], muzzle)


func _repairs(dt: float) -> void:
	var cfg: Dictionary = data.defense["repair_station"]
	for key: String in keys_of("repair_station"):
		var piece: Dictionary = build.pieces[key]
		var bin: Factory.Bin = factory.bins.get(piece["cell"])
		if bin == null:
			continue
		if power != null:
			power.wants[key] = bin.count > 0
			if not power.is_powered(key):
				continue
		var b: Dictionary = data.buildables[piece["id"]]
		bin.timer = minf(bin.timer + dt, b["interval"])
		if bin.count <= 0 or bin.timer < b["interval"] - 1e-6:
			continue
		var target := most_damaged(build.piece_center(key), b["range"], cfg["repairs"])
		if target == "":
			continue
		var t: Dictionary = build.pieces[target]
		var max_hp: int = data.buildables[t["id"]]["hp"]
		var gain := mini(int(cfg["hp_per_panel"]), max_hp - int(t["hp"]))
		t["hp"] = int(t["hp"]) + gain
		repaired += gain
		bin.take_one()
		bin.timer = 0.0
		if base_log != null:
			base_log.add("Repair station fixed the %s (%d/%d hp)" % [base_log.place_name(target).to_lower(), t["hp"], max_hp],
					build.piece_center(target), false)


## The piece of one of `kinds` within `reach` of `at` missing the most hp ("" if none). Broken windows don't count.
func most_damaged(at: Vector3, reach: float, kinds: Array) -> String:
	var best := ""
	var best_missing := 0
	var keys := build.pieces.keys()
	keys.sort()
	for key: String in keys:
		var p: Dictionary = build.pieces[key]
		if not build.kind_of(p["id"]) in kinds or build.is_broken(key):
			continue
		var missing: int = int(data.buildables[p["id"]]["hp"]) - int(p["hp"])
		if missing <= best_missing:
			continue
		var c := build.piece_center(key)
		if Vector2(c.x - at.x, c.z - at.z).length() > reach:
			continue
		best = key
		best_missing = missing
	return best


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
