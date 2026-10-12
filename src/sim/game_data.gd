class_name GameData
extends RefCounted
## Content loaded from data/*.json. validate() lists every problem so a test can fail loudly.

const DIR := "res://data/"
const KINDS := ["foundation", "wall", "belt", "machine"]

var items: Dictionary = {}       # id -> {name}
var buildables: Dictionary = {}  # id -> {name, kind, size: Vector3, cost: {item: int}}
var recipes: Dictionary = {}     # id -> {name, time: float, in: {item: int}, out: {item: int}}
var debug_kit: Dictionary = {}   # item -> int
var zombies: Dictionary = {}     # type -> stats (numbers), see data/zombies.json
var weapons: Dictionary = {}     # id -> stats (numbers), see data/weapons.json
var noise: Dictionary = {}       # muffler, sounds, director tuning: see data/noise.json
var load_errors: PackedStringArray = []


static func load_default() -> GameData:
	var data := GameData.new()
	data.load_from(_read_json(DIR + "items.json", data), _read_json(DIR + "buildables.json", data),
			_read_json(DIR + "debug_kit.json", data), _read_json(DIR + "recipes.json", data))
	data.zombies = _read_json(DIR + "zombies.json", data)
	data.weapons = _read_json(DIR + "weapons.json", data)
	data.noise = _read_json(DIR + "noise.json", data)
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
		if b["kind"] == "machine" and (b["loudness"] <= 0.0 or b["loudness"] > 100.0):
			errors.append("machine '%s' needs a loudness from 1 to 100" % id)
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if r["time"] <= 0.0:
			errors.append("recipe '%s' needs a positive time" % id)
		if r["in"].is_empty() or r["out"].is_empty():
			errors.append("recipe '%s' needs inputs and outputs" % id)
		for part in ["in", "out"]:
			for item: String in r[part]:
				if not items.has(item):
					errors.append("recipe '%s' uses unknown item '%s'" % [id, item])
				elif r[part][item] <= 0:
					errors.append("recipe '%s' has a non-positive amount of '%s'" % [id, item])
	for item: String in debug_kit:
		if not items.has(item):
			errors.append("debug kit has unknown item '%s'" % item)
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
		_check_stats(errors, "noise", {"director": noise.get("director", {})}, DIRECTOR_STATS)
	return errors


const ZOMBIE_STATS := ["hp", "wander_speed", "chase_speed", "attack_range", "attack_interval", "damage",
		"structure_damage", "sight_day", "sight_night", "sight_fov", "sense_radius", "hearing_day",
		"hearing_night", "investigate_speed"]
const WEAPON_STATS := ["damage", "head_multiplier", "range", "cooldown", "knockback"]
const SOUNDS := ["footstep_walk", "footstep_sprint", "melee_hit", "zombie_bash", "wreck"]
const DIRECTOR_STATS := ["listen_distance", "gain_floor", "gain_rate", "night_multiplier", "decay", "max_heat",
		"check_every", "max_alive", "wanderers_at", "group_at", "horde_at", "wanderers", "group", "horde",
		"heat_per_zombie", "lure_time"]


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
	return Color.from_string(items.get(item, {}).get("color", ""), Color(0.6, 0.6, 0.6))


func item_name(item: String) -> String:
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
