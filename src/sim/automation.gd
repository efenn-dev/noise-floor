class_name Automation
extends RefCounted
## M15: sensors and the one action each one runs, plus the pieces those actions use. No programming:
## sensor -> action, picked in a small screen (E on the sensor).
##   Motion sensor: sees a living zombie within its range with nothing solid between (built walls and
##     closed doors block it; barricades and windows don't).
##   Noise sensor: hears a one-off sound within its range at threshold or more (walls muffle as usual).
##     It ignores continuous hums (your own machines) and the noisemakers' blare, so a decoy can't keep
##     setting itself off.
##   A tripwire bell that rings sets off every sensor within trigger_radius, whatever it watches.
## A sensor is "on" while it senses something and for its action's hold after that. Actions (defense.json):
##   quiet: every machine and generator on the sensor's power network is switched off while it's on.
##   floodlights: every floodlight within radius is on while it's on (they only light, and draw power, at night).
##   decoy: when it comes on, every charged, powered noisemaker within radius blares (a one-off at its loudness
##     every pulse for `blare` seconds, then `recharge` seconds before it can go again).
##   lock_doors: every door within radius is shut when it comes on and stays shut (E can't open it) while it's on.
## Floodlights can also be set to light every night on their own (E on one).

var data: GameData
var build: BuildGrid
var power: PowerGrid
var noise: NoiseField
var base_log: BaseLog
## key -> {action: String, on: bool, hold: float (seconds left after it stops sensing), bell: bool}
var sensors: Dictionary = {}
## key -> {night: bool (always on at night), on: bool (wanted this tick), lit: bool}
var floodlights: Dictionary = {}
## key -> {blare: float, recharge: float, pulse: float}
var noisemakers: Dictionary = {}
## Door keys a lock-doors sensor is holding shut.
var locked: Dictionary = {}
var _check := 0.0
var _night := false


func _init(p_data: GameData, p_build: BuildGrid, p_power: PowerGrid, p_noise: NoiseField) -> void:
	data = p_data
	build = p_build
	power = p_power
	noise = p_noise
	build.piece_added.connect(_on_added)
	build.piece_removed.connect(_on_removed)


func cfg() -> Dictionary:
	return data.defense


func _on_added(key: String) -> void:
	match build.kind_of(build.pieces[key]["id"]):
		"sensor":
			sensors[key] = {"action": cfg()["action_order"][0], "on": false, "hold": 0.0, "bell": false}
		"floodlight":
			floodlights[key] = {"night": false, "on": false, "lit": false}
		"noisemaker":
			noisemakers[key] = {"blare": 0.0, "recharge": 0.0, "pulse": 0.0}


func _on_removed(key: String, _piece: Dictionary) -> void:
	sensors.erase(key)
	floodlights.erase(key)
	noisemakers.erase(key)
	locked.erase(key)
	power.switched_off.erase(key)
	power.wants.erase(key)


## Picks a sensor's action ("quiet", "floodlights", "decoy", "lock_doors"). "" or why not.
func set_action(key: String, action: String) -> String:
	if not sensors.has(key):
		return "Not a sensor"
	if not cfg()["actions"].has(action):
		return "Unknown action"
	var was_on: bool = sensors[key]["on"]
	sensors[key] = {"action": action, "on": false, "hold": 0.0, "bell": false}
	if was_on:
		_apply()
	return ""


func action_name(action: String) -> String:
	return cfg()["actions"][action]["name"]


## E on a floodlight: sensor-only, or on every night too. Returns the message.
func toggle_floodlight(key: String) -> String:
	if not floodlights.has(key):
		return ""
	floodlights[key]["night"] = not floodlights[key]["night"]
	_apply()
	return "Floodlight: on every night" if floodlights[key]["night"] else "Floodlight: only when a sensor turns it on"


## Lit floodlights' positions (the world draws lights there; zombies see you further near them).
func lit_positions() -> Array:
	var out := []
	for key: String in floodlights:
		if floodlights[key]["lit"]:
			out.append(build.piece_center(key))
	return out


## Is `at` within light_radius of a lit floodlight?
func in_light(at: Vector3) -> bool:
	var r := float(cfg()["floodlight"]["light_radius"])
	for key: String in floodlights:
		if floodlights[key]["lit"]:
			var c := build.piece_center(key)
			if Vector2(c.x - at.x, c.z - at.z).length() <= r:
				return true
	return false


## One tick. `bells`: where tripwires rang this tick.
func tick(dt: float, horde: Horde, night: bool, bells: Array) -> void:
	_night = night
	for key: String in noisemakers:
		_tick_noisemaker(key, dt)
	for at: Vector3 in bells:
		for key: String in sensors:
			if _flat(build.piece_center(key), at) <= float(cfg()["tripwire"]["trigger_radius"]):
				sensors[key]["bell"] = true
	_check -= dt
	for key: String in sensors:
		sensors[key]["hold"] = maxf(0.0, sensors[key]["hold"] - dt)
	var due := _check <= 0.0
	if not due and bells.is_empty():
		return
	if due:
		_check = float(cfg()["sensors"]["check_every"])
	var keys := sensors.keys()
	keys.sort()
	for key: String in keys:
		var s: Dictionary = sensors[key]
		var what := sense(key, horde)
		if s["bell"]:
			what = "the tripwire bell"
			s["bell"] = false
		if what != "":
			s["hold"] = float(cfg()["actions"][s["action"]]["hold"])
		var on: bool = what != "" or s["hold"] > 0.0
		if on and not s["on"]:
			s["on"] = true
			_fire(key, what)
		elif not on:
			s["on"] = false
	_apply()


## What sensor `key` notices right now ("" if nothing): "zombies" (motion) or the loudest sound's kind (noise).
func sense(key: String, horde: Horde) -> String:
	var b: Dictionary = data.buildables[build.pieces[key]["id"]]
	var at := build.piece_center(key)
	var reach: float = b["range"]
	if b["sense"] == "motion":
		var n := 0
		for id: int in horde.zombies:
			var z: ZombieBrain = horde.zombies[id]
			if z.is_dead() or _flat(z.pos, at) > reach:
				continue
			if noise.walls_between(at, z.pos, true) == 0:
				n += 1
		return "" if n == 0 else ("a zombie" if n == 1 else "%d zombies" % n)
	var ignore: Array = cfg()["sensors"]["noise_ignore"]
	var threshold := float(cfg()["sensors"]["noise_threshold"])
	for s: Dictionary in noise.recent:
		if s["age"] >= NoiseField.HEAR_WINDOW or s["kind"] in ignore:
			continue
		var d := _flat(s["pos"], at)
		if d > reach:
			continue
		if NoiseField.heard_level(s["loudness"], d, noise.walls_between(s["pos"], at)) >= threshold:
			return "a noise (%s)" % String(s["kind"]).replace("_", " ")
	return ""


## A sensor just came on: say so, and a decoy sets off the noisemakers.
func _fire(key: String, what: String) -> void:
	var s: Dictionary = sensors[key]
	var who := base_log.thing_name(key) if base_log != null else "Sensor"
	var at := build.piece_center(key)
	if s["action"] == "decoy":
		var fired := 0
		for nk: String in noisemakers:
			if _flat(build.piece_center(nk), at) <= float(cfg()["actions"]["decoy"]["radius"]) and fire_noisemaker(nk):
				fired += 1
		_say("%s: %s, decoy: %s" % [who, what, ("%d noisemaker%s going off" % [fired, "" if fired == 1 else "s"]) if fired > 0 else "no noisemaker ready"], at)
		return
	_say("%s: %s, %s on" % [who, what, action_name(s["action"]).to_lower()], at)


## Sets off one noisemaker if it's charged and its network has power for it. Returns true if it went off.
func fire_noisemaker(key: String) -> bool:
	var n: Dictionary = noisemakers[key]
	if n["blare"] > 0.0 or n["recharge"] > 0.0 or not power.is_powered(key):
		return false
	n["blare"] = float(cfg()["noisemaker"]["blare"])
	n["pulse"] = 0.0
	power.wants[key] = true
	_say("%s going off" % (base_log.thing_name(key) if base_log != null else "Noisemaker"), build.piece_center(key))
	return true


func _tick_noisemaker(key: String, dt: float) -> void:
	var n: Dictionary = noisemakers[key]
	if n["blare"] > 0.0:
		n["pulse"] -= dt
		if n["pulse"] <= 0.0:  # a one-off every pulse, so every zombie in earshot hears it (and comes to wreck it)
			n["pulse"] = float(cfg()["noisemaker"]["pulse"])
			noise.emit(build.piece_center(key), data.buildables[build.pieces[key]["id"]]["loudness"], "noisemaker", key)
		n["blare"] = maxf(0.0, n["blare"] - dt)
		if n["blare"] <= 0.0:
			n["recharge"] = float(cfg()["noisemaker"]["recharge"])
	elif n["recharge"] > 0.0 and power.is_powered(key):
		n["recharge"] = maxf(0.0, n["recharge"] - dt)
	power.wants[key] = n["blare"] > 0.0 or n["recharge"] > 0.0


## Applies what the sensors that are on want: quiet mode, floodlights, locked doors.
func _apply() -> void:
	var off := {}
	var lit_by := {}
	var keep_shut := {}
	for key: String in sensors:
		var s: Dictionary = sensors[key]
		if not s["on"]:
			continue
		var at := build.piece_center(key)
		match s["action"]:
			"quiet":
				for k: String in power.network_of(key).get("keys", []):
					if build.kind_of(build.pieces[k]["id"]) in ["machine", "generator"]:
						off[k] = true
			"floodlights":
				for fk: String in floodlights:
					if _flat(build.piece_center(fk), at) <= float(cfg()["actions"]["floodlights"]["radius"]):
						lit_by[fk] = true
			"lock_doors":
				var r := float(cfg()["actions"]["lock_doors"]["radius"])
				for dk: String in build.pieces:
					if build.kind_of(build.pieces[dk]["id"]) == "door" and _flat(build.piece_center(dk), at) <= r:
						keep_shut[dk] = true
	power.switched_off = off
	for dk: String in keep_shut:
		if build.pieces[dk].get("open", false):
			build.toggle_door(dk)  # shut it (the world hears piece_changed)
	locked = keep_shut
	for fk: String in floodlights:
		var f: Dictionary = floodlights[fk]
		f["on"] = (f["night"] or lit_by.has(fk)) and _night
		power.wants[fk] = f["on"]
		f["lit"] = f["on"] and power.is_powered(fk)


## Is this door held shut by a sensor?
func is_locked(key: String) -> bool:
	return locked.has(key)


func _say(text: String, at: Vector3) -> void:
	if base_log != null:
		base_log.add(text, at)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func to_dict() -> Dictionary:
	return {"sensors": sensors.duplicate(true), "floodlights": floodlights.duplicate(true),
			"noisemakers": noisemakers.duplicate(true), "locked": locked.keys()}


func load_dict(d: Dictionary) -> void:
	for key: String in d.get("sensors", {}):
		if sensors.has(key):
			var s: Dictionary = d["sensors"][key]
			var action := str(s.get("action", sensors[key]["action"]))
			sensors[key] = {"action": action if cfg()["actions"].has(action) else sensors[key]["action"],
					"on": bool(s.get("on", false)), "hold": float(s.get("hold", 0.0)), "bell": false}
	for key: String in d.get("floodlights", {}):
		if floodlights.has(key):
			floodlights[key]["night"] = bool(d["floodlights"][key].get("night", false))
	for key: String in d.get("noisemakers", {}):
		if noisemakers.has(key):
			var n: Dictionary = d["noisemakers"][key]
			noisemakers[key] = {"blare": float(n.get("blare", 0.0)), "recharge": float(n.get("recharge", 0.0)), "pulse": 0.0}
	locked = {}
	for key: String in d.get("locked", []):
		if build.pieces.has(key):
			locked[key] = true
