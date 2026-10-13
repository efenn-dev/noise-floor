class_name Projects
extends RefCounted
## M17a: big projects (data/projects.json), the first being the water tower in the industrial park.
## A project stands at a site (SimWorld.place_park adds it) and has phases done in order. Each phase:
##   1. deliver its items (deliver(): from your pockets or a storage crate within deliver_range of the site;
##      part at a time is fine, what's delivered stays delivered),
##   2. start the work (start_work(), E / the Start Work button), then
##   3. work_hours of game time accrue while you stand within work_radius of the site (alive, on foot, awake).
##      Walk off and it pauses; come back and it carries on, no need to press anything again. While it runs it
##      is a continuous noise source at the phase's loudness (zombies hear it, the Director heats up).
##      A phase with "watts" also needs that much spare power on a network the site is on (a pole within its
##      reach of the site): the pump is a PowerGrid external load, so the generator runs for it, noise and all.
## The last phase done puts the project in `done` (saved; M17b will open the next area from it) and turns
## on its reward: rain_mult (every rain collector fills that much faster) and unlocks (buildables that need it).
## Nothing here knows about nodes; SimWorld ticks it and turns its events into HUD messages and base log lines.

const EXTERNAL_PREFIX := "project:"

var data: GameData
var sites: Dictionary = {}  # project id -> Vector3 (the middle of its footprint, on the ground)
## project id -> {phase: phases done so far, delivered: {item: n} for the current phase, progress: 0..1 of its
## work, working: the work has been started}
var state: Dictionary = {}
var done: Array = []  # ids of finished projects (saved as "projects_done")
var _sources: Array = []  # this tick's noise: [{pos, loudness, key, kind}]
var _was_running: Dictionary = {}  # id -> the work ran last tick (to say "paused" once)


func _init(p_data: GameData) -> void:
	data = p_data


func add_site(id: String, pos: Vector3) -> void:
	sites[id] = pos
	if not state.has(id):
		state[id] = _fresh()


static func _fresh() -> Dictionary:
	return {"phase": 0, "delivered": {}, "progress": 0.0, "working": false}


func cfg(id: String) -> Dictionary:
	return data.projects.get(id, {})


func phases(id: String) -> Array:
	return cfg(id).get("phases", [])


## How many phases are done.
func phase(id: String) -> int:
	return int(state.get(id, _fresh())["phase"])


func is_done(id: String) -> bool:
	return done.has(id)


## The phase being worked on now ({} once the project is done).
func current(id: String) -> Dictionary:
	var p := phase(id)
	var all := phases(id)
	return all[p] if p < all.size() else {}


## What the current phase still needs delivered: {item: n}.
func missing(id: String) -> Dictionary:
	var out := {}
	var ph := current(id)
	var got: Dictionary = state.get(id, _fresh())["delivered"]
	for item: String in ph.get("needs", {}):
		var n := int(ph["needs"][item]) - int(got.get(item, 0))
		if n > 0:
			out[item] = n
	return out


func is_working(id: String) -> bool:
	return bool(state.get(id, {}).get("working", false))


## Is the work running right now (started, and the player close enough, and powered if it needs power)?
func is_running(id: String) -> bool:
	return bool(_was_running.get(id, false))


## Delivers what the current phase still needs from `stock` (as much as there is). Returns {item: n} moved.
func deliver(id: String, stock: Variant) -> Dictionary:
	var moved := {}
	if not sites.has(id) or is_done(id):
		return moved
	var got: Dictionary = state[id]["delivered"]
	var need := missing(id)
	for item: String in need:
		var n := mini(int(stock.count(item)), int(need[item]))
		if n > 0 and stock.take_all({item: n}):
			got[item] = int(got.get(item, 0)) + n
			moved[item] = n
	return moved


## Starts the current phase's work. Returns "" or why not.
func start_work(id: String) -> String:
	if not sites.has(id):
		return "Nothing to work on"
	if is_done(id):
		return "%s is done" % cfg(id).get("name", id)
	if is_working(id):
		return "Already working: stay within %d m" % int(cfg(id)["work_radius"])
	if not missing(id).is_empty():
		return "Deliver what it needs first"
	state[id]["working"] = true
	return ""


## Seconds of work the current phase takes.
func work_seconds(id: String, seconds_per_hour: float) -> float:
	return float(current(id).get("work_hours", 1.0)) * seconds_per_hour


## One sim tick. `can_work`: the player is alive, on foot and awake. Returns events:
## [{kind: "started" | "finished" | "done" | "paused" | "no_power", id, phase (index), text}].
func tick(dt: float, player_pos: Vector3, can_work: bool, seconds_per_hour: float, power: PowerGrid) -> Array:
	var events: Array = []
	_sources = []
	for id: String in sites:
		var st: Dictionary = state[id]
		var ph := current(id)
		var ext := EXTERNAL_PREFIX + id
		var watts := float(ph.get("watts", 0.0))
		if power != null:
			if watts > 0.0 and st["working"]:
				power.external[ext] = {"pos": sites[id], "watts": watts, "on": false}
			else:
				power.external.erase(ext)
		if ph.is_empty() or not st["working"]:
			_was_running[id] = false
			continue
		var close: bool = can_work and _flat(player_pos, sites[id]) <= float(cfg(id)["work_radius"])
		var powered: bool = watts <= 0.0 or (power != null and (power.free or power.external_on.get(ext, false)))
		if power != null and watts > 0.0:
			power.external[ext]["on"] = close  # asks for power while you're there; the grid answers next tick
		var running: bool = close and powered
		if running and not _was_running.get(id, false) and float(st["progress"]) == 0.0:
			events.append({"kind": "started", "id": id, "phase": phase(id), "text": str(ph.get("start", ""))})
		elif close and not powered and power != null and power.external_spare.has(ext) \
				and float(power.external_spare[ext]) + 1e-6 < watts and not st.get("told_power", false):
			st["told_power"] = true
			events.append({"kind": "no_power", "id": id, "phase": phase(id),
					"text": "The pump needs %d W spare on a power network: put a pole within reach of the tower" % roundi(watts)})
		elif not running and _was_running.get(id, false):
			events.append({"kind": "paused", "id": id, "phase": phase(id), "text": "Work on the %s paused" % str(cfg(id)["name"]).to_lower()})
		_was_running[id] = running
		if not running:
			continue
		st.erase("told_power")
		_sources.append({"pos": sites[id] + Vector3(0, 1, 0), "loudness": float(ph["loudness"]), "key": ext,
				"kind": str(ph.get("sound", "project"))})
		st["progress"] = float(st["progress"]) + dt / maxf(0.001, work_seconds(id, seconds_per_hour))
		if st["progress"] < 1.0 - 1e-9:
			continue
		var finished := phase(id)
		events.append({"kind": "finished", "id": id, "phase": finished, "text": str(ph.get("done", ""))})
		state[id] = _fresh()
		state[id]["phase"] = finished + 1
		_was_running[id] = false
		if power != null:
			power.external.erase(ext)
		if finished + 1 >= phases(id).size() and not done.has(id):
			done.append(id)
			events.append({"kind": "done", "id": id, "phase": finished, "text": ""})
	return events


## The noise the projects made this tick (continuous sources, like machines).
func noise_sources() -> Array:
	return _sources


## How much faster rain collectors fill: every done project's reward rain_mult, multiplied.
func rain_mult() -> float:
	var m := 1.0
	for id: String in done:
		m *= float(cfg(id).get("reward", {}).get("rain_mult", 1.0))
	return m


## Is buildable `id` allowed (its needs_project, if any, is done)?
func unlocked(buildable: String) -> bool:
	var need: String = data.buildables.get(buildable, {}).get("needs_project", "")
	return need == "" or done.has(need)


func to_dict() -> Dictionary:
	var out := {}
	for id: String in state:
		var st: Dictionary = state[id]
		out[id] = {"phase": st["phase"], "delivered": st["delivered"].duplicate(), "progress": st["progress"],
				"working": st["working"]}
	return out


func load_dict(d: Dictionary, done_list: Array) -> void:
	for id: String in d:
		if not data.projects.has(id):
			continue
		var s: Dictionary = d[id]
		var delivered := {}
		for item: String in s.get("delivered", {}):
			delivered[item] = int(s["delivered"][item])
		state[id] = {"phase": clampi(int(s.get("phase", 0)), 0, phases(id).size()), "delivered": delivered,
				"progress": clampf(float(s.get("progress", 0.0)), 0.0, 1.0), "working": bool(s.get("working", false))}
	done = []
	for id: Variant in done_list:
		if data.projects.has(str(id)) and not done.has(str(id)):
			done.append(str(id))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
