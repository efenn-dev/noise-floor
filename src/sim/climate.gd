class_name Climate
extends RefCounted
## M16: the cold, and what keeps it off. Numbers in data/seasons.json.
##   warmth (on PlayerStats, 0..100) drains outdoors by the season's cold (per game-hour, more at night),
##   slower with Skills.bonus("warmth") (the jacket), and comes back fast within reach of a heat source.
##   Q4: a roof (a town floor under you) only slows the cold: indoors it drains at indoor_cold (a third) of the
##   outdoor rate, and asleep indoors at asleep_indoor_cold (half) of that again; only heat warms you up.
##   Asleep outdoors (a bed you built in the open) it never falls, as since M16.
##   stove: E loads planks (pockets, then crates); it burns one per hours_per_fuel game-hours while it has
##   any, lit, heating radius m and making a quiet continuous noise (its loudness in buildables.json).
##   electric heater: a 40 W consumer on the power grid; heats radius m while powered. Silent.

var data: GameData
var build: BuildGrid
var power: PowerGrid
## Stoves: piece key -> {planks: int (waiting), fuel: float (game-hours left in the one burning), lit: bool}
var stoves: Dictionary = {}
var heaters: Dictionary = {}  # piece key -> true
var _refunds: Dictionary = {}  # key -> planks left in a stove that was just removed


func _init(p_data: GameData, p_build: BuildGrid, p_power: PowerGrid) -> void:
	data = p_data
	build = p_build
	power = p_power
	build.piece_added.connect(_on_added)
	build.piece_removed.connect(_on_removed)


func cfg() -> Dictionary:
	return data.seasons


## Burns the stoves' fuel. `seconds_per_hour` is the clock's (real seconds per game-hour).
func tick(dt: float, seconds_per_hour: float) -> void:
	var per_plank := float(cfg()["stove"]["hours_per_fuel"])
	for key: String in stoves:
		var s: Dictionary = stoves[key]
		if s["fuel"] <= 0.0 and s["planks"] > 0:
			s["planks"] -= 1
			s["fuel"] += per_plank
		s["lit"] = s["fuel"] > 0.0
		if s["lit"]:
			s["fuel"] -= dt / seconds_per_hour
			while s["fuel"] <= 0.0 and s["planks"] > 0:
				s["planks"] -= 1
				s["fuel"] += per_plank
			s["fuel"] = maxf(0.0, s["fuel"])
			s["lit"] = s["fuel"] > 0.0


## E on a stove: loads planks from `inv` up to the cap. Returns how many went in.
func load_fuel(key: String, inv: Inventory) -> int:
	if not stoves.has(key):
		return 0
	var s: Dictionary = stoves[key]
	var fuel: String = data.buildables[build.pieces[key]["id"]]["fuel"]
	var n := mini(inv.count(fuel), int(cfg()["stove"]["cap"]) - s["planks"])
	if n > 0 and inv.remove(fuel, n):
		s["planks"] += n
		return n
	return 0


## Game-hours a stove will still burn.
func hours_left(key: String) -> float:
	var s: Dictionary = stoves[key]
	return s["fuel"] + s["planks"] * float(cfg()["stove"]["hours_per_fuel"])


func heater_on(key: String) -> bool:
	return heaters.has(key) and power.is_powered(key)


## Is `at` within reach of a lit stove or a powered heater?
func heat_near(at: Vector3) -> bool:
	var sr := float(cfg()["stove"]["radius"])
	for key: String in stoves:
		if stoves[key]["lit"] and _flat(build.piece_center(key), at) <= sr:
			return true
	var hr := float(cfg()["heater"]["radius"])
	for key: String in heaters:
		if heater_on(key) and _flat(build.piece_center(key), at) <= hr:
			return true
	return false


## Warmth per game-hour for someone at a spot: + near heat, else - the season's cold (cold_night after dark),
## cut by `bonus` (capped at bonus_cap). Q4: under a roof the cold is cut to indoor_cold of that (and asleep
## there, by asleep_indoor_cold again); a roof no longer warms you. Asleep outdoors it never falls.
func warmth_rate(season: Dictionary, night: bool, near_heat: bool, indoors: bool, asleep: bool, bonus: float) -> float:
	var w: Dictionary = cfg()["warmth"]
	if near_heat:
		return float(w["heat_gain"])
	var cold := float(season.get("cold_night" if night else "cold_day", 0.0))
	var rate := -cold * (1.0 - clampf(bonus, 0.0, float(w["bonus_cap"])))
	if indoors:
		rate *= float(w["indoor_cold"])
		return rate * float(w["asleep_indoor_cold"]) if asleep else rate
	return maxf(0.0, rate) if asleep else rate


## Lit stoves as noise sources: {pos, loudness, key, kind}.
func noise_sources() -> Array:
	var out := []
	for key: String in stoves:
		if stoves[key]["lit"]:
			var id: String = build.pieces[key]["id"]
			out.append({"pos": build.piece_center(key), "loudness": float(data.buildables[id]["loudness"]), "key": key, "kind": id})
	return out


## Planks that were waiting in stove `key` when it was removed (once).
func take_refund(key: String) -> int:
	var n: int = _refunds.get(key, 0)
	_refunds.erase(key)
	return n


func to_dict() -> Dictionary:
	return stoves.duplicate(true)


## A saved {key: {planks, fuel, lit}}; stoves the save doesn't know stay empty.
func from_dict(d: Dictionary) -> void:
	for key: String in d:
		if stoves.has(key):
			var s: Dictionary = d[key]
			stoves[key] = {"planks": int(s.get("planks", 0)), "fuel": float(s.get("fuel", 0.0)), "lit": bool(s.get("lit", false))}


func _on_added(key: String) -> void:
	match build.kind_of(build.pieces[key]["id"]):
		"stove":
			stoves[key] = {"planks": 0, "fuel": 0.0, "lit": false}
		"heater":
			heaters[key] = true


func _on_removed(key: String, _piece: Dictionary) -> void:
	if stoves.has(key):
		_refunds[key] = stoves[key]["planks"]
	stoves.erase(key)
	heaters.erase(key)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
