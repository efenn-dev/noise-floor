class_name Vehicles
extends RefCounted
## The town's cars: where each one is, its fuel (in gas cans, the same gas G siphons), its damage, and
## whether it's a wreck. The player can drive one; the world runs the physics and reports back with
## moved(). A running engine is a loud continuous noise source, and fuel burns with distance and idling.
## Types and their numbers are in data/vehicles.json.

var data: GameData
## id -> {type, pos: Vector3, yaw: float (radians), fuel: float (cans), hp: float, wreck: String ("" = drivable),
##        running: bool, speed: float (m/s), lights: bool,
##        key_in: where its key is ("ignition", "glovebox", "house" or "lost"), hotwired: bool}
var cars: Dictionary = {}
## Co-op A: which player `driving`, `hotwire_left`, enter() and exit() mean (SimWorld sets it with its active
## player); each player may be in a car of their own.
var actor := 0
var _driving: Dictionary = {}  # actor -> the car they're in
var _hotwire: Dictionary = {}  # actor -> seconds of hotwiring to go
var driving: String:  # id of the car the actor is in, or ""
	get: return str(_driving.get(actor, ""))
	set(v):
		if v == "":
			_driving.erase(actor)
		else:
			_driving[actor] = v
var hotwire_left: float:  # seconds of hotwiring to go in the car the actor is in; 0 = not hotwiring
	get: return float(_hotwire.get(actor, 0.0))
	set(v):
		if v <= 0.0:
			_hotwire.erase(actor)
		else:
			_hotwire[actor] = v


func _init(p_data: GameData) -> void:
	data = p_data


func add(id: String, type: String, pos: Vector3, yaw: float, fuel: float, wreck: String, key_in: String = "ignition") -> void:
	var s: Dictionary = data.vehicles[type]
	cars[id] = {"type": type, "pos": pos, "yaw": yaw, "fuel": minf(fuel, float(s["tank"])), "hp": float(s["hp"]),
			"wreck": wreck, "running": false, "speed": 0.0, "lights": false, "key_in": key_in, "hotwired": false,
			"fresh": 0.0, "stale": false}


## The item id of this car's key.
static func key_item(id: String) -> String:
	return GameData.CAR_KEY + id


## True if you can start it: its key is in the ignition or your pockets, or you've hotwired it.
func can_start(id: String, pockets: Inventory) -> bool:
	var c: Dictionary = cars[id]
	return c["key_in"] == "ignition" or c["hotwired"] or pockets.count(key_item(id)) > 0


## What the look-at prompt says about a car you have no key for.
const NO_KEY_HINT := "No key: search the trunk (E at the back) or the nearest house"


## The one line a player needs about starting `id`: "" if it starts (key in the ignition or your pockets,
## or hotwired); for a wreck, what's wrong with it and that it can still be searched and siphoned;
## otherwise where to look for the key.
func start_hint(id: String, pockets: Inventory) -> String:
	var why := why_not(id)
	if why != "":
		return "%s. It won't drive, but you can still search the trunk and siphon its gas" % why
	if can_start(id, pockets):
		return ""
	return NO_KEY_HINT


## Where to stand to search the trunk: the back of the car (+Z in the car's own frame).
func trunk_pos(id: String) -> Vector3:
	var c: Dictionary = cars[id]
	return c["pos"] + Basis(Vector3.UP, c["yaw"]) * Vector3(0.0, 0.0, float(stats(id)["size"][2]) / 2.0)


func stats(id: String) -> Dictionary:
	return data.vehicles[cars[id]["type"]]


## Why `id` can't be driven, or "" if it can.
func why_not(id: String) -> String:
	if not cars.has(id):
		return "No car"
	var c: Dictionary = cars[id]
	if c["wreck"] != "":
		return c["wreck"]
	if c["hp"] <= 0.0:
		return "Too smashed up to drive"
	return ""


## Gets in. The engine starts if there's gas. Returns "" or why not (a message for the HUD otherwise).
func enter(id: String) -> String:
	if driving != "":
		return "Already driving"
	if driver_of(id) != -1:
		return "Someone's already in it"  # co-op A
	var why := why_not(id)
	if why != "":
		return why
	driving = id
	cars[id]["running"] = cars[id]["fuel"] > 0.0
	return ""


## Gets out: the engine stops and the car is parked where it is.
func exit() -> String:
	var id := driving
	hotwire_left = 0.0
	if id != "":
		cars[id]["running"] = false
		cars[id]["speed"] = 0.0
		cars[id]["lights"] = false
	driving = ""
	return id


## Co-op A: the player in car `id`, or -1; `car_of(who)` the car player `who` is in ("" if none).
func driver_of(id: String) -> int:
	for who: int in _driving:
		if str(_driving[who]) == id:
			return who
	return -1


func car_of(who: int) -> String:
	return str(_driving.get(who, ""))


## Where you stand after getting out: beside the driver's door (the car's left, -X side).
func exit_pos(id: String) -> Vector3:
	var c: Dictionary = cars[id]
	var width: float = stats(id)["size"][0]
	return c["pos"] + Basis(Vector3.UP, c["yaw"]) * Vector3(-(width / 2.0 + 0.7), 0.0, -0.3)


## The world reports where the car is each physics step while you drive. Fuel burns with distance.
func moved(id: String, pos: Vector3, yaw: float, speed: float) -> void:
	var c: Dictionary = cars[id]
	var dist := Vector2(pos.x - c["pos"].x, pos.z - c["pos"].z).length()
	if c["running"]:
		_burn(id, dist / float(stats(id)["metres_per_can"]))
	c["pos"] = pos
	c["yaw"] = yaw
	c["speed"] = speed


## Idling burns a little gas too.
func tick(dt: float) -> void:
	for id: String in cars:
		if cars[id]["running"]:
			_burn(id, float(stats(id)["idle_cans_per_minute"]) * dt / 60.0)


func _burn(id: String, cans: float) -> void:
	var c: Dictionary = cars[id]
	c["fuel"] = maxf(0.0, c["fuel"] - cans)
	c["fresh"] = minf(c["fresh"], c["fuel"])
	if c["fuel"] <= 0.0:
		c["running"] = false  # out of gas: it rolls to a stop


func is_running(id: String) -> bool:
	return cars.has(id) and cars[id]["running"]


## Takes every whole gas can's worth out of the tank. Returns how many cans.
func siphon(id: String) -> int:
	var n := floori(cars[id]["fuel"])
	cars[id]["fuel"] -= n
	cars[id]["fresh"] = minf(cars[id]["fresh"], cars[id]["fuel"])
	return n


## Pours gas cans from `inv` into the tank (only whole cans that fit). Returns a message.
func refuel(id: String, inv: Inventory) -> String:
	var c: Dictionary = cars[id]
	var room := floori(float(stats(id)["tank"]) - c["fuel"] + 0.001)
	if room <= 0:
		return "The tank is full"
	var n := mini(room, inv.count("gas_can"))
	if n <= 0:
		return "No gas cans"
	inv.remove("gas_can", n)
	c["fuel"] += n
	c["fresh"] += n  # your gas, fresh: it doesn't go stale
	return "Poured in %d gas can%s" % [n, "s" if n > 1 else ""]


## Hitting a zombie at `speed` m/s hurts the zombie (returned) and dents the car a little.
func ram(id: String, speed: float) -> float:
	damage(id, speed * 0.5)
	return speed * float(stats(id)["ram_damage"])


## Damage to the car (zombies hitting it while you're inside, crashes). A wrecked car stalls.
func damage(id: String, amount: float) -> void:
	var c: Dictionary = cars[id]
	c["hp"] = maxf(0.0, c["hp"] - amount)
	if c["hp"] <= 0.0:
		c["running"] = false


## Fixes a quarter of the car's damage for a metal plate and 4 nails from `stock`. Returns "" or why not.
func repair(id: String, stock: Variant) -> String:
	var c: Dictionary = cars[id]
	var full := float(stats(id)["hp"])
	if c["hp"] >= full:
		return "Not damaged"
	if c["wreck"] != "":
		return "Beyond repair"
	var cost := {"metal_plate": 1, "nails": 4}
	if not stock.take_all(cost):
		return "Needs a metal plate and 4 nails"
	c["hp"] = minf(full, c["hp"] + full * 0.25)
	return ""


## Running engines, for the noise system: as loud as data/vehicles.json says.
func noise_sources() -> Array:
	var out := []
	for id: String in cars:
		if cars[id]["running"]:
			out.append({"pos": cars[id]["pos"] + Vector3(0, 1.0, 0), "loudness": float(stats(id)["loudness"]),
					"key": "car:" + id, "kind": "car"})
	return out


func to_dict() -> Dictionary:
	var out := {}
	for id: String in cars:
		var c: Dictionary = cars[id]
		out[id] = {"type": c["type"], "pos": [c["pos"].x, c["pos"].y, c["pos"].z], "yaw": c["yaw"],
				"fuel": c["fuel"], "hp": c["hp"], "wreck": c["wreck"], "key_in": c["key_in"], "hotwired": c["hotwired"],
				"fresh": c["fresh"], "stale": c["stale"]}
	return out


## Lays saved cars over the ones the town just made (same ids). Nobody is driving after a load.
func load_dict(d: Dictionary) -> void:
	for id: String in d:
		if not cars.has(id):
			continue
		var s: Dictionary = d[id]
		var c: Dictionary = cars[id]
		c["pos"] = Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
		c["yaw"] = float(s["yaw"])
		c["fuel"] = float(s["fuel"])
		c["hp"] = float(s["hp"])
		c["wreck"] = String(s["wreck"])
		c["key_in"] = String(s.get("key_in", c["key_in"]))
		c["hotwired"] = bool(s.get("hotwired", false))
		c["fresh"] = float(s.get("fresh", 0.0))
		c["stale"] = bool(s.get("stale", false))
	_driving.clear()
	_hotwire.clear()


## About three weeks in, the gas left in the town's tanks has gone stale: only the gas you poured in
## yourself is any good. Returns how many cars lost gas.
func go_stale() -> int:
	var lost := 0
	for id: String in cars:
		var c: Dictionary = cars[id]
		if c["stale"]:
			continue
		c["stale"] = true
		if c["fuel"] > c["fresh"]:
			lost += 1
		c["fuel"] = c["fresh"]
		if c["fuel"] <= 0.0:
			c["running"] = false
	return lost
