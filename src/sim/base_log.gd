class_name BaseLog
extends RefCounted
## M15: what happened at your base, with the game time, so you can read it after a night away: turret kills
## and empty magazines, walls and doors hit or wrecked, sensors going off and what they did, noisemakers,
## waves and Old Pete. Keeps the last `size` entries (data/defense.json "log"). Rules elsewhere add to it;
## SimWorld radios the far ones to the HUD when you carry a radio. Places are named by their direction from
## the middle of everything you built ("West wall"), worked out again whenever you build or lose a piece.

var data: GameData
var build: BuildGrid
var size := 50
## Oldest first: {when: "day 2 21:40", text, pos: Vector3, radio: bool}
var entries: Array = []
## Entries added since SimWorld last looked (it radios the far ones, then clears this).
var fresh: Array = []
## Game time for new entries; SimWorld sets it each tick.
var now := "day 1 08:00"
var _quiet: Dictionary = {}  # throttle key -> seconds until it may log again
var _center := Vector3.ZERO
var _dirty := true


func _init(p_data: GameData, p_build: BuildGrid) -> void:
	data = p_data
	build = p_build
	size = int(data.defense.get("log", {}).get("size", 50))
	build.piece_added.connect(_on_added)
	build.piece_removed.connect(_on_removed)


func _on_added(_key: String) -> void:
	_dirty = true


func _on_removed(_key: String, _piece: Dictionary) -> void:
	_dirty = true


func add(text: String, pos: Vector3, radio: bool = true) -> void:
	var e := {"when": now, "text": text, "pos": pos, "radio": radio}
	entries.append(e)
	fresh.append(e)
	while entries.size() > size:
		entries.pop_front()


## Like add(), but at most once per `seconds` for the same `key` (a wall under attack, a fence zapping).
func add_once(key: String, seconds: float, text: String, pos: Vector3, radio: bool = true) -> bool:
	if _quiet.get(key, 0.0) > 0.0:
		return false
	_quiet[key] = seconds
	add(text, pos, radio)
	return true


func tick(dt: float) -> void:
	for k: String in _quiet.keys():
		_quiet[k] -= dt
		if _quiet[k] <= 0.0:
			_quiet.erase(k)


## Newest first: "day 2 21:40  West wall under attack: 6 zombies".
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(entries.size() - 1, -1, -1):
		out.append("%s  %s" % [entries[i]["when"], entries[i]["text"]])
	return out


## "North", "south-east"...: where `at` is from the middle of your base (the pieces you built).
func direction(at: Vector3) -> String:
	if _dirty:
		_dirty = false
		var sum := Vector3.ZERO
		var n := 0
		for key: String in build.pieces:
			if build.player_placeable(build.pieces[key]["id"]):
				sum += build.piece_center(key)
				n += 1
		_center = sum / n if n > 0 else Vector3.ZERO
	var d := Vector2(at.x - _center.x, at.z - _center.z)
	if d.length() < 1.5:
		return "middle"
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var a := fposmod(atan2(d.x, -d.y), TAU)  # 0 = north (-Z), clockwise to the east (+X)
	return names[roundi(a / (TAU / 8.0)) % 8]


## "West wall", "North-east door": a piece's name with where it is.
func place_name(key: String) -> String:
	var piece: Dictionary = build.pieces[key]
	var dir := direction(build.piece_center(key))
	var noun: String = String(data.buildables[piece["id"]]["name"]).to_lower()
	return (dir.substr(0, 1).to_upper() + dir.substr(1) + " " + noun) if dir != "middle" else data.buildables[piece["id"]]["name"]


## "Nail turret (west)".
func thing_name(key: String) -> String:
	var piece: Dictionary = build.pieces[key]
	var dir := direction(build.piece_center(key))
	return "%s (%s)" % [data.buildables[piece["id"]]["name"], dir] if dir != "middle" else data.buildables[piece["id"]]["name"]


func to_dict() -> Array:
	var out := []
	for e: Dictionary in entries:
		out.append({"when": e["when"], "text": e["text"], "pos": [e["pos"].x, e["pos"].y, e["pos"].z], "radio": e["radio"]})
	return out


func load_list(a: Array) -> void:
	entries = []
	for e: Dictionary in a:
		var p: Array = e.get("pos", [0, 0, 0])
		entries.append({"when": str(e.get("when", "")), "text": str(e.get("text", "")),
				"pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "radio": bool(e.get("radio", true))})
	fresh = []
