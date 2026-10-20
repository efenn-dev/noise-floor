class_name GameData
extends RefCounted
## Content loaded from data/*.json. validate() lists every problem so a test can fail loudly.

const DIR := "res://data/"
const KINDS := ["foundation", "wall", "door", "barricade", "window", "belt", "machine", "bed", "storage", "generator", "solar",
		"pole", "trap", "turret", "prop", "workbench",
		# M15: automated defense
		"hopper", "sensor", "floodlight", "noisemaker", "bear_trap", "tripwire", "fence", "repair_station",
		# M16: heat
		"stove", "heater",
		# F2: the Hub and the rescue
		"hub", "radio_mast",
		# F3: belt routing
		"splitter", "merger",
		# F5: supply carts
		"cart_stop"]

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
var defense: Dictionary = {}     # M15: hoppers, turret parts, sensors and actions, traps, repair station, log, radio
var seasons: Dictionary = {}     # M16: calendar, per-season sun, crops, rain, cold and hearing; warmth, stove, heater
var projects: Dictionary = {}    # M17a: big projects (the water tower): phases, needs, work, reward; data/projects.json
var loot: Dictionary = {}        # container type -> rolls/items, plus optional gear ids for clothing sources
var difficulty: Dictionary = {}  # V29: Easy/Normal/Hard multipliers: data/difficulty.json
var resources: Dictionary = {}   # F1: resource node kinds, purities and the nodes on the map: data/resources.json
var areas: Dictionary = {}       # W3e: each WorldMap area's map name, loot multiplier and map colour: data/areas.json
var milestones: Dictionary = {}  # F2: the Hub's tiers and milestones, and the rescue broadcast: data/milestones.json
var learning: Dictionary = {}    # P10: pieces you learn by building ("after"): data/learning.json
var hit_zones: Dictionary = {}   # V33: damage per hit zone (torso, arm, leg), the leg line and the limp: data/hit_zones.json
var supplies: Dictionary = {}    # R1b: supply trucks, forage piles and the named guardians' posts: data/supplies.json
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
	data.defense = _read_json(DIR + "defense.json", data)
	data.seasons = _read_json(DIR + "seasons.json", data)
	data.projects = _read_json(DIR + "projects.json", data)
	data.projects.erase("_about")
	data.difficulty = _read_json(DIR + "difficulty.json", data)
	data.resources = _read_json(DIR + "resources.json", data)
	data.resources.erase("_about")
	data.areas = _read_json(DIR + "areas.json", data)
	data.areas.erase("_about")
	data.milestones = _read_json(DIR + "milestones.json", data)
	data.milestones.erase("_about")
	data.learning = _read_json(DIR + "learning.json", data)
	data.learning.erase("_about")
	data.hit_zones = _read_json(DIR + "hit_zones.json", data)
	data.hit_zones.erase("_about")
	data.supplies = _read_json(DIR + "supplies.json", data)
	data.supplies.erase("_about")
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
		var raw_salvage: Dictionary = b.get("salvage", {})
		buildables[id] = {
			"name": b.get("name", id),
			"kind": b.get("kind", ""),
			"size": Vector3(size[0], size[1], size[2]) if size.size() == 3 else Vector3.ZERO,
			"cost": cost,
			"recipe": b.get("recipe", ""),
			"needs_node": b.get("needs_node", ""),          # F1: an extractor goes only on this kind of resource node
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
			"sense": str(b.get("sense", "")),  # M15: a sensor's kind ("motion" or "noise"; F5: "night", the dusk timer)
			"action": str(b.get("action", "")),  # F5: a sensor's action when built ("" = the first in action_order)
			"sound": int(b.get("sound", 1)),
			"cap": int(b.get("cap", 0)),          # F5: a cart stop's cart: how many items it carries
			"speed": float(b.get("speed", 0.0)),  # F5: and how fast it drives (m/s)  # F5: how many walls' worth of sound an edge piece stops (a soundproof wall: 2)
			"player_placeable": bool(b.get("player_placeable", true)),  # false: town pieces (W1a)
			"against_wall": bool(b.get("against_wall", false)),
			"needs_project": str(b.get("needs_project", "")),  # M17a: can't be built until that project is done  # W1c: stands at the back of its cell, not the middle
		}
		if not raw_salvage.is_empty():  # P3: what pulling down one the town laid gives (see BuildGrid.refund_for)
			var salvage := {}
			for item: String in raw_salvage:
				salvage[item] = int(raw_salvage[item])
			buildables[id]["salvage"] = salvage
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
		for key: String in ["food", "water", "bag", "heal"]:  # F6: heal (a med kit)
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
		for item: String in b.get("salvage", {}):
			if not items.has(item) or b["salvage"][item] <= 0:
				errors.append("buildable '%s' has a bad salvage item '%s'" % [id, item])
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
		if b["kind"] == "sensor" and (not b["sense"] in ["motion", "noise", "night"] or (b["range"] <= 0.0 and b["sense"] != "night")):
			errors.append("sensor '%s' needs sense motion, noise or night, and a positive range to sense in" % id)
		if b["kind"] in ["floodlight", "noisemaker", "fence", "repair_station"] and b["watts"] <= 0.0:
			errors.append("%s '%s' needs power (watts)" % [b["kind"], id])
		if b["kind"] == "repair_station" and (b["range"] <= 0.0 or b["interval"] <= 0.0):
			errors.append("repair station '%s' needs a range and an interval" % id)
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
		if float(t.get("empty", 0.0)) < 0.0:
			errors.append("loot '%s' has a negative empty weight" % table)
		for e: Dictionary in t.get("items", []):
			if not items.has(e.get("item", "")):
				errors.append("loot '%s' has unknown item '%s'" % [table, e.get("item", "")])
			if float(e.get("weight", 0)) <= 0.0 or int(e.get("min", 0)) < 1 or int(e.get("max", 0)) < int(e.get("min", 0)):
				errors.append("loot '%s' entry '%s' needs weight > 0 and 1 <= min <= max" % [table, e.get("item", "")])
	_check_stats(errors, "zombie", zombies, ZOMBIE_STATS)
	for id: String in milestones.get("milestones", {}):  # F2
		var ms: Dictionary = milestones["milestones"][id]
		for b: String in ms.get("unlocks", []):
			if not buildables.has(b):
				errors.append("milestone '%s' unlocks unknown piece '%s'" % [id, b])
		for item: String in ms.get("cost", {}):
			if not items.has(item):
				errors.append("milestone '%s' costs unknown item '%s'" % [id, item])
	for id: String in learning.get("after", {}):  # P10: every "after" chain names real pieces and ends at an open one
		var seen := {}
		var at := id
		while learning["after"].has(at) and not seen.has(at):
			seen[at] = true
			if not buildables.has(at) or not buildables.has(str(learning["after"][at])):
				errors.append("learning: '%s' after '%s' names an unknown piece" % [at, learning["after"][at]])
				break
			at = str(learning["after"][at])
		if seen.has(at):
			errors.append("learning: '%s' is in a loop of pieces that need each other" % id)
	for area: String in WorldMap.AREAS:  # W3e: every area has a name and a loot multiplier
		var a: Dictionary = areas.get(area, {})
		if str(a.get("name", "")) == "" or float(a.get("loot", 0.0)) < 1.0:
			errors.append("area '%s' needs a name and a loot multiplier of at least 1 in areas.json" % area)
	for kind: String in resources.get("kinds", {}):  # F1
		var ex := str(resources["kinds"][kind].get("extractor", ""))
		if int(resources["kinds"][kind].get("holds", 0)) > 0:  # R1b: a forage pile: hand-gathered, no extractor
			if ex != "" or (resources["kinds"][kind].get("hand", {}) as Dictionary).is_empty():
				errors.append("resource kind '%s' holds a pile: it needs 'hand' and no extractor" % kind)
		elif not buildables.has(ex) or str(buildables[ex].get("needs_node", "")) != kind:
			errors.append("resource kind '%s' needs an extractor buildable whose needs_node is '%s'" % [kind, kind])
	for n: Dictionary in resources.get("nodes", []):
		if not resources["kinds"].has(n.get("kind", "")) or not resources.get("purity", {}).has(n.get("purity", "")):
			errors.append("resource node '%s' has an unknown kind or purity" % n.get("id", "?"))
	if not hit_zones.is_empty():  # V33 (tests that build GameData by hand may leave it out)
		for zone: String in ["torso", "arm", "leg"]:
			if not float(hit_zones.get("damage", {}).get(zone, -1.0)) > 0.0:
				errors.append("hit_zones.json needs a positive damage multiplier for '%s'" % zone)
		for key: String in ["leg_height", "limp_time", "limp_factor"]:
			if not hit_zones.get(key, null) is float:
				errors.append("hit_zones.json needs a number '%s'" % key)
	for id: String in zombies:
		var z: Dictionary = zombies[id]
		if not z.has("name") or str(z["name"]) == "":
			errors.append("zombie '%s' needs a name" % id)
		for key: String in ["door_break_multiplier", "parry_stagger_factor", "knockback_factor"]:
			if z.has(key) and float(z[key]) < 0.0:
				errors.append("zombie '%s' can't have a negative '%s'" % [id, key])
		for key: String in ["break_multiplier", "block_factor", "stumble_time", "stumble_slow", "eye_height",
				"head_height", "model_scale", "crawl_anim_speed", "voice_distance", "voice_pitch"]:
			if z.has(key) and float(z[key]) <= 0.0:
				errors.append("zombie '%s' needs a positive '%s'" % [id, key])
		if z.has("stumble_slow") and float(z["stumble_slow"]) > 1.0:
			errors.append("zombie '%s' stumble_slow can't exceed 1" % id)
		for key: String in ["collider_size", "collider_offset", "reach_offset"]:
			if z.has(key) and not (z[key] is Array and z[key].size() == 3):
				errors.append("zombie '%s' needs '%s' as [x, y, z]" % [id, key])
	_check_stats(errors, "weapon", weapons, WEAPON_STATS)
	for id: String in weapons:  # V15: every guard needs a sane fractional damage cut
		if float(weapons[id].get("block_reduction", 0.0)) > 1.0:
			errors.append("weapon '%s' block_reduction can't exceed 1" % id)
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
		for table_key: String in ["starting", "unlocks"]:
			for u: Dictionary in inf.get(table_key, []):
				if not zombies.has(u.get("type", "")):
					errors.append("infamy spawn table has unknown zombie '%s'" % u.get("type", ""))
				if float(u.get("chance", 0.0)) <= 0.0 or float(u.get("chance", 0.0)) > 1.0:
					errors.append("infamy spawn '%s' needs chance in (0, 1]" % u.get("type", ""))
				for cap: String in ["max_per_wave", "max_per_horde", "max_alive"]:
					if u.has(cap) and int(u[cap]) <= 0:
						errors.append("infamy spawn '%s' needs a positive '%s'" % [u.get("type", ""), cap])
		_check_gear(errors, self)
		_check_guns(errors, self)
		if not items.has("rotten_food"):
			errors.append("spoiled food needs a 'rotten_food' item")
	if not defense.is_empty():
		_check_defense(errors, self)
	_check_seasons(errors, self)
	_check_projects(errors, self)
	_check_difficulty(errors, difficulty)
	if not supplies.is_empty():
		_check_supplies(errors, self)  # R1b
	return errors


const ZOMBIE_STATS := ["hp", "wander_speed", "chase_speed", "attack_range", "attack_interval", "damage",
		"structure_damage", "sight_day", "sight_night", "sight_fov", "sense_radius", "hearing_day",
		"hearing_night", "investigate_speed", "climb_seconds"]
const WEAPON_STATS := ["damage", "head_multiplier", "range", "cooldown", "knockback", "block_reduction", "block_stamina"]
const SURVIVAL_STATS := ["food_drain", "water_drain", "energy_drain", "energy_sleep_gain", "starve_damage",
		"respawn_minimum", "heal_rate", "heal_sleep_rate", "heal_min", "stamina_regen", "stamina_regen_delay", "sprint_cost", "swing_cost", "bleed_chance",
		"vault_seconds", "vault_stamina", "vault_reach", "vault_clearance", "vault_cut_damage", "clear_glass_seconds",
		"clear_glass_weapon_mult",
		"bleed_damage", "bleed_time", "sleep_time_scale", "sleep_below_energy", "search_time", "search_range", "search_noise",
		"storage_range", "carry_base", "carry_slow_per_overload", "carry_min_speed", "carry_no_sprint",
		"carry_footstep_bonus", "siphon_noise", "car_fuel_min", "car_fuel_max", "car_wreck_chance",
		"gas_stale_day", "found_food_rots_day"]
const SOUNDS := ["footstep_walk", "footstep_sprint", "melee_hit", "block", "zombie_bash", "wreck", "door", "horn",
		"vault", "glass_clear"]
## Each car has its own key: item id "car_key:<car id>" (not in items.json).
const CAR_KEY := "car_key:"
const VEHICLE_STATS := ["tank", "metres_per_can", "idle_cans_per_minute", "loudness", "hp", "ram_damage", "mass",
		"engine_force", "brake_force", "max_steer_deg", "max_speed"]
const DIRECTOR_STATS := ["listen_distance", "gain_floor", "gain_rate", "night_multiplier", "decay", "max_heat",
		"check_every", "max_alive", "wanderers_at", "group_at", "horde_at", "wanderers", "group", "horde",
		"heat_per_zombie", "lure_time"]


## V29: every choice has the same complete, positive rule table. Runner count may be zero.
static func _check_difficulty(errors: PackedStringArray, defs: Dictionary) -> void:
	for id: String in Difficulty.ORDER:
		var cfg: Dictionary = defs.get(id, {})
		if not cfg.has("name"):
			errors.append("difficulty '%s' needs a name" % id)
		for key: String in Difficulty.REQUIRED:
			if not cfg.has(key) or float(cfg.get(key, 0.0)) <= 0.0:
				if key == "first_night_runners" and int(cfg.get(key, -1)) == 0:
					continue
				errors.append("difficulty '%s' needs positive '%s'" % [id, key])
		if not cfg.get("death_keeps_skills") is bool:
			errors.append("difficulty '%s' needs boolean death_keeps_skills" % id)


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
	var rows: Array = skills.get("tree_rows", [0, 3, 6])
	var placed := {}
	for t: String in trees:
		for p: String in trees[t].get("perks", []):
			if not perks.has(p) or not (perks[p].get("effects") is Dictionary) or perks[p]["effects"].is_empty():
				errors.append("perk '%s' (tree %s) needs effects" % [p, t])
				continue
			if perks[p].has("synergy") and not trees.has(perks[p]["synergy"].get("tree", "")):
				errors.append("perk '%s' synergy names an unknown tree" % p)
			if placed.has(p):
				errors.append("perk '%s' is in two trees" % p)
			placed[p] = true
			# P13: a row the tree has, an arrow to a perk above it in the same tree, a picture that exists
			var row := int(perks[p].get("row", 1))
			if row < 1 or row > rows.size():
				errors.append("perk '%s' row %d: the tree has rows 1-%d" % [p, row, rows.size()])
			var need := str(perks[p].get("needs", ""))
			if need != "":
				if not need in trees[t]["perks"]:
					errors.append("perk '%s' needs '%s', which isn't in its tree" % [p, need])
				elif int(perks.get(need, {}).get("row", 1)) >= row:
					errors.append("perk '%s' needs '%s', which isn't in a row above it" % [p, need])
			var icon := str(perks[p].get("icon", ""))
			if icon == "" or not ResourceLoader.exists("res://assets/icons/%s.png" % icon):
				errors.append("perk '%s' has no picture (assets/icons/%s.png)" % [p, icon])
	for p: String in perks:
		if not placed.has(p):
			errors.append("perk '%s' is in no tree" % p)


## M15: defense.json. Every action in action_order has a name and hold; items it names exist.
static func _check_defense(errors: PackedStringArray, d: GameData) -> void:
	var df := d.defense
	for a: String in df.get("action_order", []):
		var act: Dictionary = df.get("actions", {}).get(a, {})
		if not act.has("name") or float(act.get("hold", -1.0)) < 0.0:
			errors.append("defense action '%s' needs a name and a hold of 0 or more" % a)
	for item: String in df.get("hopper", {}).get("feeds", []):
		if not d.items.has(item):
			errors.append("hopper feeds unknown item '%s'" % item)
	for key: String in ["repair_station", "radio"]:
		if not d.items.has(str(df.get(key, {}).get("item", ""))):
			errors.append("defense.json %s needs a known item" % key)
	if int(df.get("log", {}).get("size", 0)) <= 0:
		errors.append("defense.json log needs a size")


## M16: seasons.json. Four seasons in "order", each with sun hours inside the day (sunrise before sunset),
## crop and rain speeds and cold drains of 0 or more, and a hearing bonus; the warmth thresholds in order;
## the stove's fuel (in buildables.json) an item, and its burn time, cap and radius positive.
static func _check_seasons(errors: PackedStringArray, d: GameData) -> void:
	var se := d.seasons
	if se.is_empty():
		if not d.buildables.is_empty() and d.buildables.has("stove"):
			errors.append("no seasons data")
		return
	if int(se.get("days_per_season", 0)) <= 0:
		errors.append("seasons.json needs a positive days_per_season")
	var order: Array = se.get("order", [])
	var defs: Dictionary = se.get("seasons", {})
	if order.size() != 4 or defs.size() != 4:
		errors.append("seasons.json needs four seasons in 'order', each defined once")
	for s: String in order:
		var def: Dictionary = defs.get(s, {})
		if not def.has("name"):
			errors.append("season '%s' needs a name" % s)
			continue
		var rise := float(def.get("sunrise", -1.0))
		var fall := float(def.get("sunset", -1.0))
		if rise <= 0.0 or fall >= 24.0 or rise >= fall:
			errors.append("season '%s' needs 0 < sunrise < sunset < 24" % s)
		for key: String in ["crop_speed", "rain_speed", "cold_day", "cold_night", "hearing_night"]:
			if not def.has(key) or float(def[key]) < 0.0:
				errors.append("season '%s' needs '%s' of 0 or more" % [s, key])
	var w: Dictionary = se.get("warmth", {})
	for key: String in ["heat_gain", "cold_at", "freezing_at", "freeze_damage", "freeze_every", "cold_stamina_regen"]:
		if float(w.get(key, 0.0)) <= 0.0:
			errors.append("seasons.json warmth needs a positive '%s'" % key)
	if float(w.get("freezing_at", 0.0)) >= float(w.get("cold_at", 0.0)):
		errors.append("seasons.json warmth: freezing_at must be below cold_at")
	for key: String in ["indoor_cold", "asleep_indoor_cold"]:  # Q4: share of the outdoor cold under a roof
		var f := float(w.get(key, -1.0))
		if f < 0.0 or f > 1.0:
			errors.append("seasons.json warmth needs a '%s' in 0..1" % key)
	var bc := float(w.get("bonus_cap", -1.0))
	if bc < 0.0 or bc > 1.0:
		errors.append("seasons.json warmth needs a bonus_cap in 0..1")
	var st: Dictionary = se.get("stove", {})
	for key: String in ["hours_per_fuel", "cap", "radius"]:
		if float(st.get(key, 0.0)) <= 0.0:
			errors.append("seasons.json stove needs a positive '%s'" % key)
	if float(se.get("heater", {}).get("radius", 0.0)) <= 0.0:
		errors.append("seasons.json heater needs a positive radius")
	if d.buildables.has("stove") and not d.items.has(str(d.buildables["stove"]["fuel"])):
		errors.append("the stove's fuel must be an item")


## M14: guns.json. Every gun base names a gun with its numbers; every part base names a part with a slot;
## ammo types are items; finds name loot tables; workbench recipes make known gear and gate on known perks.
static func _check_guns(errors: PackedStringArray, d: GameData) -> void:
	var gn := d.guns
	if gn.is_empty():
		errors.append("no gun data")
		return
	for id: String in gn.get("guns", {}):
		var gun: Dictionary = gn["guns"][id]
		var gun_slots: Array = gun.get("part_slots", [])
		if gun_slots.is_empty():
			errors.append("gun '%s' needs part_slots" % id)
		for slot: String in gun_slots:
			if not slot in gn.get("part_slots", []):
				errors.append("gun '%s' has unknown part slot '%s'" % [id, slot])
		for key: String in ["damage", "range", "spread", "ads_spread", "recoil", "settle", "handling", "magazine", "loudness",
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
		if base.get("slot", "") in ["primary", "sidearm"] and not gn.get("guns", {}).has(base.get("gun", "")):
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
		for table: String in base.get("sources", []):
			if not d.loot.has(table) or not b in d.loot.get(table, {}).get("gear", []):
				errors.append("gear base '%s' needs loot table '%s' to list it" % [b, table])
	for table: String in d.loot:
		for b: String in d.loot[table].get("gear", []):
			if not g.get("bases", {}).has(b):
				errors.append("loot '%s' lists unknown gear '%s'" % [table, b])
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


## M17a: data/projects.json. Every project has a name, a deliver_range and work_radius, at least one phase
## (a name, known items needed in positive amounts, positive work_hours and loudness, optional positive watts)
## and a reward (rain_mult >= 1, unlocks that are known buildables); a buildable's needs_project is a project.
static func _check_projects(errors: PackedStringArray, d: GameData) -> void:
	for id: String in d.projects:
		var p: Variant = d.projects[id]
		if not p is Dictionary or not p.has("name") or float(p.get("deliver_range", 0)) <= 0.0 				or float(p.get("work_radius", 0)) <= 0.0:
			errors.append("project '%s' needs a name, deliver_range and work_radius" % id)
			continue
		var phases: Array = p.get("phases", [])
		if phases.is_empty():
			errors.append("project '%s' needs phases" % id)
		for ph: Dictionary in phases:
			if not ph.has("name") or float(ph.get("work_hours", 0)) <= 0.0 or float(ph.get("loudness", 0)) <= 0.0 					or float(ph.get("watts", 0)) < 0.0:
				errors.append("project '%s' phase '%s' needs a name, positive work_hours and loudness" % [id, ph.get("name", "?")])
			for item: String in ph.get("needs", {}):
				if not d.items.has(item) or int(ph["needs"][item]) <= 0:
					errors.append("project '%s' phase '%s' needs a bad item '%s'" % [id, ph.get("name", "?"), item])
		var reward: Dictionary = p.get("reward", {})
		if float(reward.get("rain_mult", 1.0)) < 1.0:
			errors.append("project '%s' rain_mult must be 1 or more" % id)
		for u: String in reward.get("unlocks", []):
			if not d.buildables.has(u):
				errors.append("project '%s' unlocks unknown buildable '%s'" % [id, u])
	for id: String in d.buildables:
		var need: String = d.buildables[id].get("needs_project", "")
		if need != "" and not d.projects.is_empty() and not d.projects.has(need):
			errors.append("buildable '%s' needs unknown project '%s'" % [id, need])


## R1b: supplies.json. The truck has named spots on the map beside a road, a vehicle model and a loot table; the pile
## kinds are piles (resources.json "holds"); each guardian is a named zombie type with a gold piece (gear.json
## zombie_uniques) and a known post; the named dead's pockets (guns.json zombie_extra_uniques) hold real items.
static func _check_supplies(errors: PackedStringArray, d: GameData) -> void:
	var s := d.supplies
	var tc: Dictionary = s.get("truck", {})
	if tc.is_empty() or (tc.get("spots", []) as Array).is_empty():
		errors.append("supplies.json needs a truck with spots")
	if not d.vehicles.has(str(tc.get("model", ""))):
		errors.append("supply truck model '%s' needs a vehicle" % tc.get("model", ""))
	if not d.loot.has(str(tc.get("table", ""))):
		errors.append("supply truck table '%s' needs a loot table" % tc.get("table", ""))
	for key: String in ["first_day", "every_days", "horn_hours", "horn_loudness"]:
		if float(tc.get(key, 0)) <= 0.0:
			errors.append("supply truck needs a positive '%s'" % key)
	for sp: Dictionary in tc.get("spots", []):
		var pos: Array = sp.get("pos", [])
		if pos.size() != 2 or str(sp.get("name", "")) == "" or not WorldMap.EXTENT.has_point(Vector2(float(pos[0]), float(pos[1]))):
			errors.append("supply truck spot '%s' needs a name and a pos [x, z] on the map" % sp.get("name", "?"))
		elif WorldMap.on_road(Vector2(float(pos[0]), float(pos[1])), 1.0):
			errors.append("supply truck spot '%s' is on the road" % sp.get("name", "?"))
	var pc: Dictionary = s.get("piles", {})
	for kind in pc.get("kinds", []):
		if int(((d.resources.get("kinds", {}) as Dictionary).get(kind, {}) as Dictionary).get("holds", 0)) <= 0:
			errors.append("pile kind '%s' needs a resources.json kind with 'holds'" % kind)
	if (pc.get("area", []) as Array).size() != 4:
		errors.append("supplies.json piles need an area [x, z, w, h]")
	for type: String in s.get("guardians", {}):
		var g: Dictionary = s["guardians"][type]
		if not d.zombies.has(type) or not bool(d.zombies[type].get("named", false)):
			errors.append("guardian '%s' needs a named zombie type" % type)
		if not str(g.get("post", "")) in SimWorld.GUARDIAN_POSTS:
			errors.append("guardian '%s' needs a known post" % type)
		if not d.gear.get("zombie_uniques", {}).has(type):
			errors.append("guardian '%s' needs a gold piece (gear.json zombie_uniques)" % type)
	for type: String in d.guns.get("zombie_extra_uniques", {}):
		var e: Dictionary = d.guns["zombie_extra_uniques"][type]
		if not d.zombies.has(type) or (e.has("unique") and not d.gear.get("uniques", {}).has(e["unique"])):
			errors.append("zombie_extra_uniques '%s' needs a zombie and a real unique" % type)
		for item: String in e.get("ammo", {}):
			if not d.items.has(item):
				errors.append("zombie_extra_uniques '%s' carries unknown item '%s'" % [type, item])
