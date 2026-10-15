class_name DowntownPlan
extends RefCounted
## W3b: downtown, the shops along Market Street east of Main Street (WorldMap AREAS "downtown"). Pure and
## seeded, like TownPlan and ParkPlan: generate(seed) gives
##   {"shops": [{name, sign, cells, rect, style, north, front_z, door_cell, door_side}],
##    "pieces": [{id, cell, side, style}], "props": [{id, model, pos, facing, size, table, shop}],
##    "zombies": [{type, pos, facing, shop}], "wrecks": [{id, type, pos, yaw}], "canopy": {rect, top, posts}}
## Five shops are grid interiors like the houses: a town floor on every cell, outside walls in the shop's style,
## a door and shop windows along the front (the corners stay wall), a back door (not the police station's),
## and a window in each side wall. The police station has an inside wall between the front office and the
## armory at the back, with an open doorway. Roofs, the sign over each front, the props and the gas station's
## canopy are drawn by DowntownView; the walls, doors, windows and floors are BuildGrid pieces (saved like the
## houses, so breaking a window or a door works the same).
## Props are the world_props models (tools/art/world_props.py), solid but not pieces. One with a "table" is a
## loot container (id = prop id): grocery and hardware shelves, the pharmacy's counters and shelves, the police
## desks and gun lockers (guns), the gas station's shelves and pumps (gas), and a dumpster beside each shop.
## Benches line the sidewalks. A prop's `pos` is the middle of its foot on the floor (y = FLOOR on a shop floor,
## 0 outside); `facing` is the way its front looks (x, z), and `size` its box (x across the front, z deep).
## Shops on the north side of Market Street face south onto it; the south side faces north.

const STREET_Z := 60.0          # Market Street's middle line (WorldMap "market_street")
const FLOOR := 0.1              # a town floor's top
const SIDEWALK := 3.0           # from a shop front to the road's edge
## [name, sign, first cell (min x, min z), cells (along x, deep), north side?, style, door (cells from the west
## end), back door (cells from the west end, -1 = none), inside wall (rows back from the front, -1 = none),
## its doorway (cells from the west end)]
const SHOPS := [
	["grocery", "GROCERY", Vector2i(6, 20), Vector2i(10, 6), true, "plaster", 4, 8, -1, 0],
	["pharmacy", "PHARMACY", Vector2i(18, 21), Vector2i(6, 5), true, "brick", 2, 4, -1, 0],
	["hardware", "HARDWARE", Vector2i(34, 20), Vector2i(8, 6), true, "park_brick", 3, 6, -1, 0],
	["police", "POLICE", Vector2i(6, 34), Vector2i(8, 6), false, "brick", 3, -1, 4, 1],
	["gas_station", "GAS", Vector2i(32, 36), Vector2i(5, 4), false, "plaster", 2, 3, -1, 0],
]
## The models' boxes (world_props.py SPECS): x across the front, y up, z deep.
const SIZES := {
	"store_shelf": Vector3(2.0, 1.7, 0.9), "hardware_shelf": Vector3(2.0, 2.0, 0.6),
	"checkout_counter": Vector3(1.8, 1.05, 0.75), "pharmacy_counter": Vector3(2.0, 1.1, 0.7),
	"police_desk": Vector3(1.6, 1.2, 0.8), "gun_locker": Vector3(1.0, 1.9, 0.45),
	"gas_pump": Vector3(0.9, 1.9, 0.55), "dumpster": Vector3(1.9, 1.4, 1.1), "bench": Vector3(1.6, 0.85, 0.6),
}
## Inside each shop: [model, metres along from its west wall, metres back from its front wall, facing ("street",
## "in", "west", "east"), loot table or ""]. "wall" for the metres back means against the back wall.
const INSIDE := {
	"grocery": [
		["checkout_counter", 4.0, 2.6, "street", ""], ["checkout_counter", 14.0, 2.6, "street", ""],
		["store_shelf", 4.0, 5.6, "street", "grocery"], ["store_shelf", 6.0, 5.6, "street", "grocery"],
		["store_shelf", 14.0, 5.6, "street", "grocery"], ["store_shelf", 16.0, 5.6, "street", "grocery"],
		["store_shelf", 4.0, 8.6, "in", "grocery"], ["store_shelf", 6.0, 8.6, "in", "grocery"],
		["store_shelf", 14.0, 8.6, "in", "grocery"], ["store_shelf", 16.0, 8.6, "in", "grocery"],
		["store_shelf", 3.0, -1.0, "street", "grocery"], ["store_shelf", 5.0, -1.0, "street", "grocery"],
		["store_shelf", 7.0, -1.0, "street", "grocery"], ["store_shelf", 9.0, -1.0, "street", "grocery"],
		["store_shelf", 11.0, -1.0, "street", "grocery"], ["store_shelf", 13.0, -1.0, "street", "grocery"]],
	"pharmacy": [
		["store_shelf", 2.5, 3.6, "street", "pharmacy"], ["store_shelf", 9.0, 3.6, "street", "pharmacy"],
		["pharmacy_counter", 4.5, 6.6, "street", "pharmacy"], ["pharmacy_counter", 7.5, 6.6, "street", "pharmacy"],
		["store_shelf", 3.0, -1.0, "street", "pharmacy"], ["store_shelf", 5.0, -1.0, "street", "pharmacy"]],
	"hardware": [
		["checkout_counter", 10.5, 2.4, "street", ""],
		["hardware_shelf", 3.0, 5.0, "street", "hardware"], ["hardware_shelf", 5.0, 5.0, "street", "hardware"],
		["hardware_shelf", 11.0, 5.0, "street", "hardware"], ["hardware_shelf", 13.0, 5.0, "street", "hardware"],
		["hardware_shelf", 3.0, 8.0, "in", "hardware"], ["hardware_shelf", 5.0, 8.0, "in", "hardware"],
		["hardware_shelf", 11.0, 8.0, "in", "hardware"], ["hardware_shelf", 13.0, 8.0, "in", "hardware"],
		["hardware_shelf", 3.0, -1.0, "street", "hardware"], ["hardware_shelf", 5.0, -1.0, "street", "hardware"],
		["hardware_shelf", 7.0, -1.0, "street", "hardware"], ["hardware_shelf", 9.0, -1.0, "street", "hardware"]],
	"police": [
		["police_desk", 4.0, 4.0, "street", "police_desk"], ["police_desk", 10.5, 4.0, "street", "police_desk"],
		["gun_locker", 7.0, -1.0, "street", "gun_locker"], ["gun_locker", 8.5, -1.0, "street", "gun_locker"],
		["gun_locker", 10.0, -1.0, "street", "gun_locker"], ["gun_locker", 11.5, -1.0, "street", "gun_locker"],
		["gun_locker", 13.0, -1.0, "street", "gun_locker"]],
	"gas_station": [
		["checkout_counter", 7.5, 1.9, "street", ""],
		["store_shelf", 2.5, 4.0, "street", "gas_station"], ["store_shelf", 7.5, 4.6, "street", "gas_station"],
		["store_shelf", 2.5, -1.0, "street", "gas_station"], ["store_shelf", 4.5, -1.0, "street", "gas_station"]],
}
## The gas station's forecourt: two pumps (loot "gas_pump") under a canopy between the road and its front.
const PUMPS_Z := 68.6
const PUMPS_ALONG := [3.0, 7.0]  # metres from the station's west wall
const CANOPY_TOP := 4.4
const ZOMBIES_INSIDE := 2       # per shop (the police station's second is a brute)
const SHAMBLERS_OUT := 6
const RUNNERS_OUT := 1
const WRECK_TYPES := ["sedan", "pickup", "van"]
const WRECK_OFF := 2.6          # off the street's middle line, so the Director's route stays clear
const BENCHES := [[34.0, true], [52.0, true], [88.0, true], [31.0, false], [45.0, false]]  # [x, north side]


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "downtown"])
	var out := {"shops": [], "pieces": [], "props": [], "zombies": [], "wrecks": [], "canopy": {}}
	for s: Array in SHOPS:
		_add_shop(out, s)
	_add_forecourt(out)
	_add_street_props(out)
	_add_zombies(out, rng)
	_add_wrecks(out, rng)
	return out


static func shop(plan: Dictionary, shop_name: String) -> Dictionary:
	for s: Dictionary in plan["shops"]:
		if s["name"] == shop_name:
			return s
	return {}


## A shop's position for props: (x, z) of a spot `along` metres from its west wall and `back` metres in from its
## front wall (negative = that far in front of it, on the sidewalk).
static func shop_point(s: Dictionary, along: float, back: float) -> Vector2:
	var r: Rect2 = s["rect"]
	var z: float = s["front_z"] - back if s["north"] else s["front_z"] + back
	return Vector2(r.position.x + along, z)


static func _add_shop(out: Dictionary, spec: Array) -> void:
	var shop_name: String = spec[0]
	var c0: Vector2i = spec[2]
	var n: Vector2i = spec[3]
	var north: bool = spec[4]
	var style: String = spec[5]
	var g := BuildGrid.GRID
	var cells: Array = []
	for x in range(c0.x, c0.x + n.x):
		for z in range(c0.y, c0.y + n.y):
			cells.append(Vector2i(x, z))
			out["pieces"].append({"id": "town_floor", "cell": Vector2i(x, z), "side": BuildGrid.Side.NORTH, "style": "floor"})
	var front_row := c0.y + n.y - 1 if north else c0.y
	var back_row := c0.y if north else c0.y + n.y - 1
	var front_side := BuildGrid.Side.SOUTH if north else BuildGrid.Side.NORTH
	var back_side := BuildGrid.Side.NORTH if north else BuildGrid.Side.SOUTH
	var edge := func(cell: Vector2i, side: int, id: String, st: String) -> void:
		var e := BuildGrid.canonical_edge(cell, side)
		out["pieces"].append({"id": id, "cell": e[0], "side": e[1], "style": st})
	for i in n.x:
		var x := c0.x + i
		var front_id := "door" if i == spec[6] else ("town_wall" if i == 0 or i == n.x - 1 else "window")
		edge.call(Vector2i(x, front_row), front_side, front_id, style)
		edge.call(Vector2i(x, back_row), back_side, "door" if i == spec[7] else "town_wall", style)
	var mid_row := c0.y + n.y / 2
	for z in range(c0.y, c0.y + n.y):
		var id := "window" if z == mid_row else "town_wall"
		edge.call(Vector2i(c0.x, z), BuildGrid.Side.WEST, id, style)
		edge.call(Vector2i(c0.x + n.x - 1, z), BuildGrid.Side.EAST, id, style)
	var wall_rows: int = spec[8]
	if wall_rows > 0:  # the police armory: an inside wall `wall_rows` rows back, with an open doorway
		var row := front_row - wall_rows if north else front_row + wall_rows
		var side := BuildGrid.Side.SOUTH if north else BuildGrid.Side.NORTH
		for i in n.x:
			if i != spec[9]:
				edge.call(Vector2i(c0.x + i, row), side, "town_wall", "plaster")
	var rect := Rect2(c0.x * g, c0.y * g, n.x * g, n.y * g)
	var front_z := rect.end.y if north else rect.position.y
	var s := {"name": shop_name, "sign": spec[1], "cells": cells, "rect": rect, "style": style, "north": north,
			"front_z": front_z, "door_cell": Vector2i(c0.x + int(spec[6]), front_row), "door_side": front_side,
			"back_door_cell": Vector2i(c0.x + int(spec[7]), back_row) if int(spec[7]) >= 0 else Vector2i(-9999, -9999),
			"inside_wall": wall_rows, "inside_doorway": int(spec[9])}
	out["shops"].append(s)
	var street := Vector2(0, 1) if north else Vector2(0, -1)
	var k := 0
	for p: Array in INSIDE[shop_name]:
		var size: Vector3 = SIZES[p[0]]
		var facing: Vector2 = {"street": street, "in": -street, "west": Vector2(-1, 0), "east": Vector2(1, 0)}[p[3]]
		var back: float = p[2]
		if back < 0.0:  # against the back wall: its own depth plus the wall's half and a gap
			back = rect.size.y - 0.1 - size.z / 2.0 - 0.05
		var at := shop_point(s, p[1], back)
		var table: String = p[4]
		out["props"].append({"id": "%s_%s_%d" % [shop_name, p[0], k], "model": p[0], "pos": Vector3(at.x, FLOOR, at.y),
				"facing": facing, "size": size, "table": table, "shop": shop_name})
		k += 1
	# A dumpster beside the shop's east wall (the gas station's west), near the back, its lid toward the side.
	var dsize: Vector3 = SIZES["dumpster"]
	var east := shop_name != "gas_station"
	var dx := rect.end.x + 0.3 + dsize.z / 2.0 if east else rect.position.x - 0.3 - dsize.z / 2.0
	var dz := rect.position.y + 1.6 if north else rect.end.y - 1.6
	out["props"].append({"id": "%s_dumpster" % shop_name, "model": "dumpster", "pos": Vector3(dx, 0.0, dz),
			"facing": Vector2(1, 0) if east else Vector2(-1, 0), "size": dsize, "table": "trash", "shop": shop_name})


## The pumps in front of the gas station and the canopy over them (a roof on four posts, drawn by DowntownView).
static func _add_forecourt(out: Dictionary) -> void:
	var s := shop(out, "gas_station")
	var r: Rect2 = s["rect"]
	for i in PUMPS_ALONG.size():
		out["props"].append({"id": "gas_station_pump_%d" % i, "model": "gas_pump",
				"pos": Vector3(r.position.x + PUMPS_ALONG[i], 0.0, PUMPS_Z), "facing": Vector2(0, -1),
				"size": SIZES["gas_pump"], "table": "gas_pump", "shop": "gas_station"})
	var canopy := Rect2(r.position.x + 0.5, PUMPS_Z - 2.5, r.size.x - 1.0, 5.0)
	var posts: Array = []
	for px in [canopy.position.x + 0.4, canopy.end.x - 0.4]:
		for pz in [canopy.position.y + 0.4, canopy.end.y - 0.4]:
			posts.append(Vector3(px, 0.0, pz))
	out["canopy"] = {"rect": canopy, "top": CANOPY_TOP, "posts": posts}


static func _add_street_props(out: Dictionary) -> void:
	var size: Vector3 = SIZES["bench"]
	for i in BENCHES.size():
		var north: bool = BENCHES[i][1]
		var road_edge := STREET_Z - 5.0 if north else STREET_Z + 5.0
		var z := road_edge - 1.2 if north else road_edge + 1.2
		out["props"].append({"id": "downtown_bench_%d" % i, "model": "bench", "pos": Vector3(BENCHES[i][0], 0.0, z),
				"facing": Vector2(0, 1) if north else Vector2(0, -1), "size": size, "table": "", "shop": ""})


## ZOMBIES_INSIDE in each shop on free floor (away from the props and the doors, facing the front door), and
## SHAMBLERS_OUT + RUNNERS_OUT along the sidewalks and the street.
static func _add_zombies(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g := BuildGrid.GRID
	for s: Dictionary in out["shops"]:
		var free: Array = []
		for c: Vector2i in s["cells"]:
			var mid := Vector2((c.x + 0.5) * g, (c.y + 0.5) * g)
			if c == s["door_cell"] or c == s["back_door_cell"] or not is_clear(out, mid, 0.6):
				continue
			free.append(c)
		for i in ZOMBIES_INSIDE:
			if free.is_empty():
				break
			var cell: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
			var door: Vector2i = s["door_cell"]
			var facing := Vector3(door.x - cell.x, 0, door.y - cell.y)
			out["zombies"].append({"type": "brute" if s["name"] == "police" and i == 1 else "shambler",
					"pos": Vector3((cell.x + 0.5) * g, FLOOR, (cell.y + 0.5) * g),
					"facing": facing.normalized() if facing.length_squared() > 0.01 else Vector3.FORWARD, "shop": s["name"]})
	var outside: Array = []
	var tries := 0
	while outside.size() < SHAMBLERS_OUT + RUNNERS_OUT and tries < 1000:
		tries += 1
		var p := Vector2(rng.randf_range(14.0, 190.0), STREET_Z + rng.randf_range(-7.5, 7.5))
		if not is_open_ground(out, p, 1.0):
			continue
		var close := false
		for o: Dictionary in outside:
			close = close or Vector2(o["pos"].x, o["pos"].z).distance_to(p) < 6.0
		if close:
			continue
		outside.append({"type": "shambler", "pos": Vector3(p.x, 0.0, p.y),
				"facing": Vector3(0, 0, -1) if p.y > STREET_Z else Vector3(0, 0, 1), "shop": ""})
	for i in RUNNERS_OUT:
		if i < outside.size():
			outside[rng.randi_range(0, outside.size() - 1)]["type"] = "runner"
	out["zombies"] += outside


## Two or three wrecked cars on Market Street east of the shops, off its middle, at least 15 m apart.
static func _add_wrecks(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 3)
	var tries := 0
	while out["wrecks"].size() < count and tries < 200:
		tries += 1
		var x := rng.randf_range(95.0, 185.0)
		var clash := false
		for w: Dictionary in out["wrecks"]:
			clash = clash or absf(w["pos"].x - x) < 15.0
		if clash:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var yaw := deg_to_rad(90.0 + rng.randf_range(-15.0, 15.0)) + (PI if rng.randf() < 0.5 else 0.0)
		out["wrecks"].append({"id": "downtown_car_%d" % out["wrecks"].size(),
				"type": WRECK_TYPES[rng.randi_range(0, WRECK_TYPES.size() - 1)],
				"pos": Vector3(x, 0.0, STREET_Z + side * WRECK_OFF), "yaw": yaw})


## A prop's footprint on the ground (x, z), its box turned to its facing.
static func prop_rect(p: Dictionary) -> Rect2:
	var size: Vector3 = p["size"]
	var f: Vector2 = p["facing"]
	var across := size.z if absf(f.x) > 0.5 else size.x  # turned to face east or west, it's deep along x
	var deep := size.x if absf(f.x) > 0.5 else size.z
	return Rect2(p["pos"].x - across / 2.0, p["pos"].z - deep / 2.0, across, deep)


## Is (x, z) clear of every prop (with `margin` metres to spare)?
static func is_clear(plan: Dictionary, p: Vector2, margin: float) -> bool:
	for pr: Dictionary in plan["props"]:
		if prop_rect(pr).grow(margin).has_point(p):
			return false
	return true


## Is (x, z) open ground downtown: outside every shop and the canopy's posts, and clear of the props?
static func is_open_ground(plan: Dictionary, p: Vector2, margin: float) -> bool:
	for s: Dictionary in plan["shops"]:
		if (s["rect"] as Rect2).grow(margin).has_point(p):
			return false
	return is_clear(plan, p, margin)


## Which shop (index) has `cell`, or -1.
static func shop_at(plan: Dictionary, cell: Vector2i) -> int:
	for i in plan["shops"].size():
		if cell in plan["shops"][i]["cells"]:
			return i
	return -1
