class_name GameData
extends RefCounted
## Content loaded from data/*.json. validate() lists every problem so a test can fail loudly.

const DIR := "res://data/"
const KINDS := ["foundation", "wall", "door", "barricade", "window", "belt", "machine", "bed", "storage", "generator", "solar",
		"pole", "trap", "turret"]

var items: Dictionary = {}       # id -> {name}
var buildables: Dictionary = {}  # id -> {name, kind, size: Vector3, cost: {item: int}}
var recipes: Dictionary = {}     # id -> {name, time: float, in: {item: int}, out: {item: int}}
var debug_kit: Dictionary = {}   # item -> int
var zombies: Dictionary = {}     # type -> stats (numbers), see data/zombies.json
var weapons: Dictionary = {}     # id -> stats (numbers), see data/weapons.json
var noise: Dictionary = {}       # muffler, sounds, director tuning: see data/noise.json
var skills: Dictionary = {}      # levels, xp per action, hotwiring: data/skills.json
var vehicles: Dictionary = {}    # car type -> size, seat, fuel, loudness, handling: data/vehicles.json
var survival: Dictionary = {}    # hunger, thirst, energy, stamina, bleeding, carry weight: data/survival.json
var loot: Dictionary = {}        # container type -> {name, rolls: [min, max], items: [{item, weight, min, max}]}
var load_errors: PackedStringArray = []


static func load_default() -> GameData:
	var data := GameData.new()
	data.load_from(_read_json(DIR + "items.json", data), _read_json(DIR + "buildables.json", data),
			_read_json(DIR + "debug_kit.json", data), _read_json(DIR + "recipes.json", data))
	data.zombies = _read_json(DIR + "zombies.json", data)
	data.weapons = _read_json(DIR + "weapons.json", data)
	data.noise = _read_json(DIR + "noise.json", data)
	data.survival = _read_json(DIR + "survival.json", data)
	data.vehicles = _read_json(DIR + "vehicles.json", data)
	data.skills = _read_json(DIR + "skills.json", data)
	data.loot = _read_json(DIR + "loot.json", data)
	return data


## Fills from already-parsed JSON (tests pass dictionaries straight in).
func load_from(raw_items: Dictionary, raw_buildables: Dictionary, raw_kit: Dictionary,
		raw_recipes: Dictionary = {}) -> void:
	items = raw_items
	buildables = {}
	for id: String in raw_buildables:
		var b: Dictionary = raw_buildables[id]
		var size: Array = b.get("size", [])
		var cost := {}
		var raw_cost: Dictionary = b.get("cost", {})
		for item: String in raw_cost:
			cost[item] = int(raw_cost[item])
		buildables[id] = {
			"name": b.get("name", id),
			"kind": b.get("kind", ""),
			"size": Vector3(size[0], size[1], size[2]) if size.size() == 3 else Vector3.ZERO,
			"cost": cost,
			"recipe": b.get("recipe", ""),
			"hp": int(b.get("hp", 0)),
			"loudness": float(b.get("loudness", 0.0)),
			"watts": float(b.get("watts", 0.0)),          # power a machine draws while working
			"watts_out": float(b.get("watts_out", 0.0)),  # power a generator or panel makes
			"fuel": b.get("fuel", ""),
			"burn_time": float(b.get("burn_time", 0.0)),  # seconds of full load per fuel item
			"reach": float(b.get("reach", 0.0)),          # how far a power pole connects
			"damage": float(b.get("damage", 0.0)),        # trap: per second; turret: per shot
			"slow": float(b.get("slow", 1.0)),            # trap: speed factor for zombies on it
			"range": float(b.get("range", 0.0)),          # turret reach in m
			"interval": float(b.get("interval", 0.0)),    # turret: seconds between shots
			"ammo": b.get("ammo", ""),
			"ammo_cap": int(b.get("ammo_cap", 0)),
			"player_placeable": bool(b.get("player_placeable", true)),  # false: town pieces (W1a)
		}
	recipes = {}
	for id: String in raw_recipes:
		var r: Dictionary = raw_recipes[id]
		recipes[id] = {"name": r.get("name", id), "time": float(r.get("time", 0.0)),
				"in": _int_counts(r.get("in", {})), "out": _int_counts(r.get("out", {}))}
	debug_kit = {}
	for item: String in raw_kit:
		debug_kit[item] = int(raw_kit[item])


func validate() -> PackedStringArray:
	var errors := load_errors.duplicate()
	for id: String in items:
		if not items[id] is Dictionary or not items[id].has("name"):
			errors.append("item '%s' needs a name" % id)
			continue
		var w: Variant = items[id].get("weight")
		if not (w is float or w is int) or float(w) < 0.0:
			errors.append("item '%s' needs a weight in kg (0 or more)" % id)
		for key: String in ["food", "water", "bag"]:
			if items[id].has(key) and float(items[id][key]) <= 0.0:
				errors.append("item '%s' needs a positive '%s'" % [id, key])
	for id: String in buildables:
		var b: Dictionary = buildables[id]
		if not b["kind"] in KINDS:
			errors.append("buildable '%s' has unknown kind '%s'" % [id, b["kind"]])
		var size: Vector3 = b["size"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			errors.append("buildable '%s' needs a positive [x, y, z] size" % id)
		if b["cost"].is_empty():
			errors.append("buildable '%s' costs nothing" % id)
		for item: String in b["cost"]:
			if not items.has(item):
				errors.append("buildable '%s' costs unknown item '%s'" % [id, item])
			if b["cost"][item] <= 0:
				errors.append("buildable '%s' has a non-positive cost for '%s'" % [id, item])
		if b["hp"] <= 0:
			errors.append("buildable '%s' needs positive hp" % id)
		if b["kind"] == "machine" and not recipes.has(b["recipe"]):
			errors.append("machine '%s' has unknown recipe '%s'" % [id, b["recipe"]])
		if b["kind"] in ["generator", "solar"] and b["watts_out"] <= 0.0:
			errors.append("%s '%s' needs a positive watts_out" % [b["kind"], id])
		if b["kind"] == "generator" and (not items.has(b["fuel"]) or b["burn_time"] <= 0.0):
			errors.append("generator '%s' needs a known fuel item and a positive burn_time" % id)
		if b["kind"] == "trap" and (b["damage"] <= 0.0 or b["slow"] <= 0.0 or b["slow"] > 1.0):
			errors.append("trap '%s' needs positive damage and a slow factor in (0, 1]" % id)
		if b["kind"] == "turret" and (b["damage"] <= 0.0 or b["range"] <= 0.0 or b["interval"] <= 0.0
				or not items.has(b["ammo"]) or b["ammo_cap"] <= 0 or b["loudness"] <= 0.0):
			errors.append("turret '%s' needs damage, range, interval, a known ammo item, ammo_cap and loudness" % id)
		if b["kind"] == "pole" and b["reach"] <= 0.0:
			errors.append("pole '%s' needs a positive reach" % id)
		if b["watts"] < 0.0:
			errors.append("buildable '%s' can't draw negative watts" % id)
		if b["kind"] in ["machine", "generator"] and (b["loudness"] <= 0.0 or b["loudness"] > 100.0):
			errors.append("machine '%s' needs a loudness from 1 to 100" % id)
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if r["time"] <= 0.0:
			errors.append("recipe '%s' needs a positive time" % id)
		if r["out"].is_empty():
			errors.append("recipe '%s' needs outputs" % id)  # no inputs is fine (rain collector)
		for part in ["in", "out"]:
			for item: String in r[part]:
				if not items.has(item):
					errors.append("recipe '%s' uses unknown item '%s'" % [id, item])
				elif r[part][item] <= 0:
					errors.append("recipe '%s' has a non-positive amount of '%s'" % [id, item])
	for item: String in debug_kit:
		if not items.has(item):
			errors.append("debug kit has unknown item '%s'" % item)
	_check_stats(errors, "survival", {"survival": survival} if not survival.is_empty() else {}, SURVIVAL_STATS)
	for table: String in loot:
		var t: Dictionary = loot[table]
		var rolls: Array = t.get("rolls", [])
		if rolls.size() != 2 or int(rolls[0]) < 1 or int(rolls[1]) < int(rolls[0]):
			errors.append("loot '%s' needs rolls [min, max]" % table)
		if t.get("items", []).is_empty():
			errors.append("loot '%s' has no items" % table)
		for e: Dictionary in t.get("items", []):
			if not items.has(e.get("item", "")):
				errors.append("loot '%s' has unknown item '%s'" % [table, e.get("item", "")])
			if float(e.get("weight", 0)) <= 0.0 or int(e.get("min", 0)) < 1 or int(e.get("max", 0)) < int(e.get("min", 0)):
				errors.append("loot '%s' entry '%s' needs weight > 0 and 1 <= min <= max" % [table, e.get("item", "")])
	_check_stats(errors, "zombie", zombies, ZOMBIE_STATS)
	_check_stats(errors, "weapon", weapons, WEAPON_STATS)
	if noise.is_empty():
		errors.append("no noise data")
	else:
		var muffler: Dictionary = noise.get("muffler", {})
		for item: String in muffler.get("cost", {}):
			if not items.has(item):
				errors.append("muffler costs unknown item '%s'" % item)
		_check_stats(errors, "noise", {"muffler": muffler}, ["cut", "slowdown"])
		_check_stats(errors, "noise", {"sounds": noise.get("sounds", {})}, SOUNDS)
		_check_stats(errors, "vehicle", vehicles, VEHICLE_STATS)
		var levels: Array = skills.get("levels", [])
		if levels.size() < 3 or levels[0] != 0:
			errors.append("skills.json needs 'levels' starting at 0")
		for i in range(1, levels.size()):
			if float(levels[i]) <= float(levels[i - 1]):
				errors.append("skill levels must go up")
		_check_stats(errors, "skills", {"hotwire": skills}, ["hotwire_level", "hotwire_seconds", "hotwire_min_seconds", "hotwire_noise"])
		_check_stats(errors, "skills", {"perks": skills}, ["levels_per_perk_point", "perk_max_rank", "sneak_range",
				"heavy_load", "search_time_min"])
		_check_skills(errors, skills)
		for id: String in vehicles:
			for key: String in ["size", "seat"]:
				var v: Variant = vehicles[id].get(key)
				if not (v is Array and v.size() == 3):
					errors.append("vehicle '%s' needs '%s' as [x, y, z]" % [id, key])
		_check_stats(errors, "noise", {"director": noise.get("director", {})}, DIRECTOR_STATS)
		var inf: Dictionary = noise.get("infamy", {})
		_check_stats(errors, "noise", {"infamy": inf}, ["one_off_floor", "one_off_rate"])
		for u: Dictionary in inf.get("unlocks", []):
			if not zombies.has(u.get("type", "")):
				errors.append("infamy unlocks unknown zombie '%s'" % u.get("type", ""))
		if not items.has("rotten_food"):
			errors.append("spoiled food needs a 'rotten_food' item")
	return errors


const ZOMBIE_STATS := ["hp", "wander_speed", "chase_speed", "attack_range", "attack_interval", "damage",
		"structure_damage", "sight_day", "sight_night", "sight_fov", "sense_radius", "hearing_day",
		"hearing_night", "investigate_speed"]
const WEAPON_STATS := ["damage", "head_multiplier", "range", "cooldown", "knockback"]
const SURVIVAL_STATS := ["food_drain", "water_drain", "energy_drain", "energy_sleep_gain", "starve_damage",
		"respawn_minimum", "stamina_regen", "stamina_regen_delay", "sprint_cost", "swing_cost", "bleed_chance",
		"bleed_damage", "sleep_time_scale", "sleep_below_energy", "search_time", "search_range", "search_noise",
		"storage_range", "carry_base", "carry_slow_per_overload", "carry_min_speed", "carry_no_sprint",
		"carry_footstep_bonus", "siphon_noise", "car_fuel_min", "car_fuel_max", "car_wreck_chance",
		"gas_stale_day", "found_food_rots_day"]
const SOUNDS := ["footstep_walk", "footstep_sprint", "melee_hit", "zombie_bash", "wreck", "door", "horn"]
## Each car has its own key: item id "car_key:<car id>" (not in items.json).
const CAR_KEY := "car_key:"
const VEHICLE_STATS := ["tank", "metres_per_can", "idle_cans_per_minute", "loudness", "hp", "ram_damage", "mass",
		"engine_force", "brake_force", "max_steer_deg", "max_speed"]
const DIRECTOR_STATS := ["listen_distance", "gain_floor", "gain_rate", "night_multiplier", "decay", "max_heat",
		"check_every", "max_alive", "wanderers_at", "group_at", "horde_at", "wanderers", "group", "horde",
		"heat_per_zombie", "lure_time"]


## M12: every skill in "order" has a name, xp and effects; every tree's perks exist with effects.
static func _check_skills(errors: PackedStringArray, skills: Dictionary) -> void:
	var defs: Dictionary = skills.get("skills", {})
	var order: Array = skills.get("order", [])
	if order.size() != defs.size():
		errors.append("skills.json 'order' must list every skill once")
	for s: String in order:
		if not defs.has(s) or not (defs[s].get("xp") is Dictionary) or not (defs[s].get("effects") is Dictionary):
			errors.append("skill '%s' needs a name, xp and effects" % s)
	var perks: Dictionary = skills.get("perks", {})
	var trees: Dictionary = skills.get("trees", {})
	for t: String in trees:
		for p: String in trees[t].get("perks", []):
			if not perks.has(p) or not (perks[p].get("effects") is Dictionary) or perks[p]["effects"].is_empty():
				errors.append("perk '%s' (tree %s) needs effects" % [p, t])
			elif perks[p].has("synergy") and not trees.has(perks[p]["synergy"].get("tree", "")):
				errors.append("perk '%s' synergy names an unknown tree" % p)


static func _check_stats(errors: PackedStringArray, what: String, table: Dictionary, keys: Array) -> void:
	if table.is_empty() and what != "":
		errors.append("no %s data" % what)
	for id: String in table:
		for key: String in keys:
			var v: Variant = table[id].get(key)
			if not (v is float or v is int) or float(v) <= 0.0:
				errors.append("%s '%s' needs a positive number for '%s'" % [what, id, key])


## Item color for drawing (items.json "color", grey if missing).
func item_color(item: String) -> Color:
	if item.begins_with(CAR_KEY):
		return Color(0.85, 0.7, 0.3)
	return Color.from_string(items.get(item, {}).get("color", ""), Color(0.6, 0.6, 0.6))


func item_weight(item: String) -> float:
	if item.begins_with(CAR_KEY):
		return 0.02
	return float(items.get(item, {}).get("weight", 0.0))


## An item's value for "food", "water" or "bag" (0 if it has none); "bandage" gives 1 for bandages.
func item_value(item: String, key: String) -> float:
	var v: Variant = items.get(item, {}).get(key, 0)
	return 1.0 if v is bool and v else (float(v) if not v is bool else 0.0)


func item_name(item: String) -> String:
	if item.begins_with(CAR_KEY):
		return "Car key"
	return items.get(item, {}).get("name", item)


static func _int_counts(raw: Dictionary) -> Dictionary:
	var out := {}
	for item: String in raw:
		out[item] = int(raw[item])
	return out


static func _read_json(path: String, data: GameData) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		data.load_errors.append("could not read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		data.load_errors.append("%s is not a JSON object" % path)
		return {}
	return parsed
