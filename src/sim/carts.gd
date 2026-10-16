class_name Carts
extends RefCounted
## F5 (loudness as a puzzle): supply carts bring an outpost's output home, so a loud machine can work far from your
## base. A cart stop (a post you build) serves the storage crates within its `range`. One stop is home: the first
## one built, or whichever you make home (E on a stop). Every other stop is a pickup with its own cart:
##   wait: every `interval` seconds it loads up to `cap` items from the crates by its stop; with any aboard it sets off;
##   home: it drives the roads home (WorldMap.route between the stops) at `speed` m/s and unloads into the crates by
##     the home stop (each up to Factory.STORAGE_FROM_BELT_CAP; what doesn't fit rides back and goes next time);
##   back: it drives back to its stop and loads again.
## A moving cart hums at the cart stop's `loudness`, so zombies along the road hear it pass. A pickup removed gives
## back what its cart carried; the home stop removed sends every cart back to its stop to wait.
## Numbers: the cart_stop entry in data/buildables.json.

var data: GameData
var build: BuildGrid
## Set by SimWorld: (at: Vector3, reach: float) -> Array of the storage crates' Inventories within reach of `at`.
var crates_near: Callable
## The home stop's key ("" until a stop is built).
var home := ""
## Pickup stop key -> {state: "wait"|"home"|"back", d: metres along its path, cargo: {item: count}, wait: seconds}.
var carts: Dictionary = {}
## Items carts have brought home, ever (for the session log and tests).
var delivered := 0
const PARK_OFF := 1.6  # a cart waits this far from its stop's post, toward the road
const LANE := 1.6      # and drives this far right of the road's middle, like a car in its lane
var _paths: Dictionary = {}  # pickup key -> {points: Array[Vector3], length: float}; worked out when needed


func _init(p_data: GameData, p_build: BuildGrid) -> void:
	data = p_data
	build = p_build
	build.piece_added.connect(_on_added)


func cfg() -> Dictionary:
	return data.buildables["cart_stop"]


func _on_added(key: String) -> void:
	if build.kind_of(build.pieces[key]["id"]) != "cart_stop":
		return
	if home == "":
		home = key
	else:
		carts[key] = {"state": "wait", "d": 0.0, "cargo": {}, "wait": 0.0}
	_paths.clear()


## A stop came down (SimWorld calls it from its own removal hook, so it can hand the cargo to you). Returns the
## cargo that was aboard that stop's cart ({} for the home stop or an empty cart).
func removed(key: String) -> Dictionary:
	_paths.clear()
	if key == home:
		home = ""
		for k: String in carts:
			if carts[k]["state"] == "home":
				carts[k]["state"] = "back"  # nowhere to go: turn round
		return {}
	var cart: Dictionary = carts.get(key, {})
	carts.erase(key)
	return cart.get("cargo", {})


## E on a stop: make it home (the old home becomes a pickup with a cart of its own). Returns the message.
func make_home(key: String) -> String:
	if not build.pieces.has(key) or build.kind_of(build.pieces[key]["id"]) != "cart_stop":
		return ""
	if key == home:
		return "This is already the home stop: carts bring everything here"
	var cart: Dictionary = carts.get(key, {})
	carts.erase(key)
	if home != "" and build.pieces.has(home):
		carts[home] = {"state": "wait", "d": 0.0, "cargo": cart.get("cargo", {}), "wait": 0.0}
	home = key
	for k: String in carts:
		carts[k]["d"] = 0.0  # every cart starts again from its own stop
		carts[k]["state"] = "wait"
	_paths.clear()
	return "Home stop: carts bring what's by the other stops here"


func tick(dt: float) -> void:
	if home == "" or not build.pieces.has(home):
		return
	var speed := float(cfg()["speed"])
	for key: String in carts:
		var c: Dictionary = carts[key]
		match c["state"]:
			"wait":
				c["wait"] -= dt
				if c["wait"] > 0.0:
					continue
				c["wait"] = float(cfg()["interval"])
				_load(key, c)
				if not (c["cargo"] as Dictionary).is_empty():
					c["state"] = "home"
					c["d"] = 0.0
			"home":
				c["d"] += speed * dt
				if c["d"] >= path_of(key)["length"]:
					c["d"] = path_of(key)["length"]
					_unload(c)
					c["state"] = "back"
			"back":
				c["d"] -= speed * dt
				if c["d"] <= 0.0:
					c["d"] = 0.0
					c["state"] = "wait"
					c["wait"] = 0.0


func _load(key: String, c: Dictionary) -> void:
	var room := int(cfg()["cap"]) - _count(c["cargo"])
	for inv: Inventory in crates_near.call(build.piece_center(key), float(cfg()["range"])):
		for item: String in inv.items():
			if room <= 0:
				return
			var n := mini(inv.count(item), room)
			if n > 0 and inv.remove(item, n):
				c["cargo"][item] = int(c["cargo"].get(item, 0)) + n
				room -= n


func _unload(c: Dictionary) -> void:
	for inv: Inventory in crates_near.call(build.piece_center(home), float(cfg()["range"])):
		var space := Factory.STORAGE_FROM_BELT_CAP - _total(inv)
		for item: String in (c["cargo"] as Dictionary).keys():
			if space <= 0:
				break
			var n := mini(int(c["cargo"][item]), space)
			inv.add(item, n)
			delivered += n
			space -= n
			c["cargo"][item] = int(c["cargo"][item]) - n
			if int(c["cargo"][item]) <= 0:
				c["cargo"].erase(item)


static func _count(cargo: Dictionary) -> int:
	var n := 0
	for item: String in cargo:
		n += int(cargo[item])
	return n


static func _total(inv: Inventory) -> int:
	var n := 0
	for item: String in inv.items():
		n += inv.count(item)
	return n


## The way a pickup's cart drives: from its stop onto the roads, along them (WorldMap.route) and off them to the home
## stop. {points: Array[Vector3], length: float}. Worked out once per stop until a stop is built or removed.
func path_of(key: String) -> Dictionary:
	if not _paths.has(key):
		var from := build.piece_center(key)
		var to := build.piece_center(home) if home != "" and build.pieces.has(home) else from
		var pts: Array[Vector3] = [Vector3(from.x, 0.0, from.z)]
		if from.distance_to(to) > 1.0:
			for p: Vector3 in WorldMap.route(from, to):
				pts.append(Vector3(p.x, 0.0, p.z))
		pts.append(Vector3(to.x, 0.0, to.z))
		if pts.size() >= 2:  # park beside the posts, not in them
			pts[0] = pts[0].move_toward(pts[1], minf(PARK_OFF, pts[0].distance_to(pts[1]) / 2.0))
			var n := pts.size()
			pts[n - 1] = pts[n - 1].move_toward(pts[n - 2], minf(PARK_OFF, pts[n - 1].distance_to(pts[n - 2]) / 2.0))
		var length := 0.0
		for i in range(1, pts.size()):
			length += pts[i - 1].distance_to(pts[i])
		_paths[key] = {"points": pts, "length": length}
	return _paths[key]


## Where a pickup's cart is: {pos: Vector3 (in the right-hand lane), yaw: float (radians, facing the way it drives),
## moving: bool}.
func cart_at(key: String) -> Dictionary:
	var c: Dictionary = carts[key]
	var path := path_of(key)
	var pts: Array = path["points"]
	var d := clampf(float(c["d"]), 0.0, float(path["length"]))
	var dir := Vector3.FORWARD
	var at: Vector3 = pts[0]
	for i in range(1, pts.size()):
		var seg: float = (pts[i - 1] as Vector3).distance_to(pts[i])
		if seg <= 0.001:
			continue
		dir = ((pts[i] as Vector3) - pts[i - 1]).normalized()
		if d <= seg or i == pts.size() - 1:
			at = (pts[i - 1] as Vector3) + dir * minf(d, seg)
			break
		d -= seg
	if c["state"] == "back":
		dir = -dir
	at += Vector3(-dir.z, 0.0, dir.x) * LANE  # keep to the right
	return {"pos": at, "yaw": atan2(-dir.x, -dir.z), "moving": c["state"] != "wait"}


## Moving carts, as noise sources: {pos, loudness, key (its stop), kind "cart"}.
func noise_sources() -> Array:
	var out := []
	if home == "" or not build.pieces.has(home):
		return out
	for key: String in carts:
		if carts[key]["state"] != "wait":
			out.append({"pos": cart_at(key)["pos"] + Vector3(0, 0.8, 0), "loudness": float(cfg()["loudness"]),
					"key": key, "kind": "cart"})
	return out


## A stop's state in a few words, for the look-at line.
func status(key: String) -> String:
	if key == home:
		return "home stop · carts bring everything here (crates within %d m)" % int(cfg()["range"])
	if not carts.has(key):
		return ""
	var c: Dictionary = carts[key]
	if home == "" or not build.pieces.has(home):
		return "pickup · no home stop yet: build one at your base"
	var aboard := _count(c["cargo"])
	match c["state"]:
		"home":
			return "pickup · cart driving home with %d item%s" % [aboard, "" if aboard == 1 else "s"]
		"back":
			return "pickup · cart on its way back"
	return "pickup · cart waiting for something in the crates here (within %d m)" % int(cfg()["range"])


func to_dict() -> Dictionary:
	return {"home": home, "carts": carts.duplicate(true), "delivered": delivered}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	var saved_home := str(d.get("home", ""))
	if saved_home != "" and build.pieces.has(saved_home):
		if home != "" and home != saved_home and not carts.has(home):
			carts[home] = {"state": "wait", "d": 0.0, "cargo": {}, "wait": 0.0}  # it was a pickup in the save
		carts.erase(saved_home)
		home = saved_home
	var saved: Dictionary = d.get("carts", {})
	for key: String in saved:
		if carts.has(key):
			var c: Dictionary = saved[key]
			var cargo := {}
			for item: String in c.get("cargo", {}):
				cargo[item] = int(c["cargo"][item])
			carts[key] = {"state": str(c.get("state", "wait")), "d": float(c.get("d", 0.0)), "cargo": cargo,
					"wait": float(c.get("wait", 0.0))}
	delivered = int(d.get("delivered", 0))
	_paths.clear()
