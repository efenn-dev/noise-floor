class_name GameData
extends RefCounted
## Content loaded from data/*.json. validate() lists every problem so a test can fail loudly.

const DIR := "res://data/"
const KINDS := ["foundation", "wall"]

var items: Dictionary = {}       # id -> {name}
var buildables: Dictionary = {}  # id -> {name, kind, size: Vector3, cost: {item: int}}
var debug_kit: Dictionary = {}   # item -> int
var load_errors: PackedStringArray = []


static func load_default() -> GameData:
	var data := GameData.new()
	data.load_from(_read_json(DIR + "items.json", data), _read_json(DIR + "buildables.json", data),
			_read_json(DIR + "debug_kit.json", data))
	return data


## Fills from already-parsed JSON (tests pass dictionaries straight in).
func load_from(raw_items: Dictionary, raw_buildables: Dictionary, raw_kit: Dictionary) -> void:
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
		}
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
	for item: String in debug_kit:
		if not items.has(item):
			errors.append("debug kit has unknown item '%s'" % item)
	return errors


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
