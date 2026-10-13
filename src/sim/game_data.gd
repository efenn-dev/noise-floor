class_name GameData
extends RefCounted
## Content loaded from data/*.json. validate() lists every problem so a test can fail loudly.

const DIR := "res://data/"
const KINDS := ["foundation", "wall", "door", "barricade", "window", "belt", "machine", "bed", "storage", "generator", "solar",
		"pole", "trap", "turret", "prop", "workbench"]

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
var guns: Dictionary = {}        # M14: gun bases, parts, ammo types, gun finds: data/guns.json
var gear: Dictionary = {}        # M13: rarities, tiers, bases, rolled stats, uniques, sets: data/gear.json
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
	data.gear = _read_json(DIR + "gear.json", data)
	data.guns = _read_json(DIR + "guns.json", data)
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
			"recipes": Array(b.get("recipes", [])),  # M13: a machine that can switch (the Press)
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
			"against_wall": bool(b.get("against_wall", false)),  # W1c: stands at the back of its cell, not the middle
		}
	recipes = {}
	for id: String in raw_recipes:
		var r: Dictionary = raw_recipes[id]
		recipes[id] = {"name": r.get("name", id), "time": float(r.get("time", 0.0)),
				"in": _int_counts(r.get("in", {})), "out": _int_counts(r.get("out", {})),
				# M14: made by hand at a "station" (the workbench), maybe gated by a "perk", maybe making a gear piece
				"station": str(r.get("station", "")), "perk": str(r.get("perk", "")), "gear": str(r.get("gear", ""))}
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
		for r: String in b["recipes"]:
			if not recipes.has(r):
				errors.append("machine '%s' can switch to unknown recipe '%s'" % [id, r])
		if b["kind"] in ["generator", "solar"] and b["watts_out"] <= 0.0:
			errors.append("%s '%s' needs a positive watts_out" % [b["kind"], id])
		if b["kind"] == "generator" and (not items.has(b["fuel"]) or b["burn_time"] <= 0.0):
			errors.append("generator '%s' needs a known fuel item and a positive burn_time" % id)
		if b["kind"] == "trap" and (b["damage"] <= 0.0 or b["slow"] <= 0.0 or b["slow"] > 1.0):
			errors.append("trap '%s' needs positive damage and a slow factor in (0, 1]" % id)
		if b["kind"] == "turret" and (b["damage"] <= 0.0 or b["range"] <= 0.0 or b["interval"] <= 0.0
				or not items.has(b["ammo"]) or b["ammo_cap"] <= 0 or b["loudness"] <= 0.0):
			errors.append("turret '%s' needs damage, range, interval, a known ammo item, ammo_cap and loudness" % id)
		if b["kind"] == "prop" and (size.x > 1.8 or size.z > 0.9 or b["player_placeable"]):
			errors.append("prop '%s' must fit along one wall of a cell (at most 1.8 x 0.9 m) and not be player-placeable" % id)
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
		if r["out"].is_empty() and r["gear"] == "":
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
		_check_gear(errors, self)
		_check_guns(errors, self)
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


## M14: guns.json. Every gun base names a gun with its numbers; every part base names a part with a slot;
## ammo types are items; finds name loot tables; workbench recipes make known gear and gate on known perks.
static func _check_guns(errors: PackedStringArray, d: GameData) -> void:
	var gn := d.guns
	if gn.is_empty():
		errors.append("no gun data")
		return
	for id: String in gn.get("guns", {}):
		var gun: Dictionary = gn["guns"][id]
		for key: String in ["damage", "range", "spread", "recoil", "settle", "handling", "magazine", "loudness",
				"cooldown", "reload", "wear_per_shot"]:
			if float(gun.get(key, 0)) <= 0.0:
				errors.append("gun '%s' needs a positive '%s'" % [id, key])
		if float(gun.get("loudness", 0)) > 100.0:
			errors.append("gun '%s' is louder than 100" % id)
	for id: String in gn.get("parts", {}):
		if not gn["parts"][id].get("slot", "") in gn.get("part_slots", []):
			errors.append("gun part '%s' needs a slot in part_slots" % id)
	for a: String in gn.get("ammo", {}):
		if not d.items.has(a):
			errors.append("ammo '%s' needs an item" % a)
	for b: String in d.gear.get("bases", {}):
		var base: Dictionary = d.gear["bases"][b]
		if base.get("slot", "") == "gun" and not gn.get("guns", {}).has(base.get("gun", "")):
			errors.append("gear base '%s' needs a gun in guns.json" % b)
		if base.get("slot", "") == "part" and not gn.get("parts", {}).has(base.get("part", "")):
			errors.append("gear base '%s' needs a part in guns.json" % b)
	for table: String in gn.get("finds", {}):
		if not d.loot.has(table):
			errors.append("gun finds name unknown loot table '%s'" % table)
	for id: String in d.recipes:
		var r: Dictionary = d.recipes[id]
		if r["gear"] != "" and not d.gear.get("bases", {}).has(r["gear"]):
			errors.append("recipe '%s' makes unknown gear '%s'" % [id, r["gear"]])
		if r["perk"] != "" and not d.skills.get("perks", {}).has(r["perk"]):
			errors.append("recipe '%s' needs unknown perk '%s'" % [id, r["perk"]])


## M13: gear.json. Rarity colours, tiers, bases (a slot, a weight, a weapon in weapons.json for
## weapons), stat ranges (min <= max), uniques and sets naming real bases and stats, drop chances in 0..1.
static func _check_gear(errors: PackedStringArray, d: GameData) -> void:
	var g := d.gear
	if g.is_empty():
		errors.append("no gear data")
		return
	var slots: Array = g.get("slots", [])
	for r: String in ["white", "blue", "yellow", "gold", "set", "orange"]:
		if not g.get("rarities", {}).has(r) or Color.from_string(str(g["rarities"][r].get("color", "")), Color(0, 0, 0, 0)).a == 0.0:
			errors.append("gear rarity '%s' needs a colour" % r)
	for r: String in ["white", "blue", "yellow"]:
		var span: Array = g.get("rarities", {}).get(r, {}).get("stats", [])
		if span.size() != 2 or int(span[0]) > int(span[1]):
			errors.append("gear rarity '%s' needs stats [min, max]" % r)
	for t: String in ["civilian", "police"]:
		var tier: Dictionary = g.get("tiers", {}).get(t, {})
		if float(tier.get("base_mult", 0)) <= 0.0 or float(tier.get("chance", -1)) < 0.0:
			errors.append("gear tier '%s' needs base_mult and chance" % t)
	for b: String in g.get("bases", {}):
		var base: Dictionary = g["bases"][b]
		if not (base.get("slot", "") in slots or base.get("slot", "") == "part") or float(base.get("weight", 0)) <= 0.0:
			errors.append("gear base '%s' needs a slot and a weight" % b)
		if base.get("slot", "") == "weapon" and not d.weapons.has(base.get("weapon", "")):
			errors.append("gear base '%s' needs a weapon in weapons.json" % b)
	for s: String in g.get("stats", {}):
		var st: Dictionary = g["stats"][s]
		if float(st.get("min", 0)) <= 0.0 or float(st.get("max", 0)) < float(st.get("min", 0)) or not "%d" in str(st.get("text", "")):
			errors.append("gear stat '%s' needs 0 < min <= max and a text with %%d" % s)
	for u: String in g.get("uniques", {}):
		var un: Dictionary = g["uniques"][u]
		if not g.get("bases", {}).has(un.get("base", "")) or un.get("stats", {}).is_empty():
			errors.append("unique '%s' needs a base and stats" % u)
		for s: String in un.get("stats", {}):
			if not g.get("stats", {}).has(s) or float(un["stats"][s][1]) < float(un["stats"][s][0]):
				errors.append("unique '%s' has a bad stat '%s'" % [u, s])
	for s: String in g.get("sets", {}):
		for b: String in g["sets"][s].get("pieces", {}):
			if not g.get("bases", {}).has(b):
				errors.append("set '%s' names unknown base '%s'" % [s, b])
		if g["sets"][s].get("bonuses", {}).is_empty():
			errors.append("set '%s' needs bonuses" % s)
	for table: String in g.get("containers", {}):
		if not d.loot.has(table) or float(g["containers"][table]) < 0.0 or float(g["containers"][table]) > 1.0:
			errors.append("gear chance for '%s' needs a loot table and a chance in 0..1" % table)
	for z: String in g.get("zombie_uniques", {}):
		if not d.zombies.has(z) or not g.get("uniques", {}).has(g["zombie_uniques"][z]):
			errors.append("zombie unique '%s' needs a zombie and a unique" % z)
	if not g.get("bases", {}).has(g.get("start_weapon", "")):
		errors.append("gear needs a start_weapon base")
	for key: String in ["wear_per_hit", "wear_per_day", "broken_below"]:
		if float(g.get(key, 0)) <= 0.0:
			errors.append("gear needs a positive '%s'" % key)
	if not d.weapons.has("fists"):
		errors.append("weapons.json needs 'fists' (no weapon equipped)")


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
