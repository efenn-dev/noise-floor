class_name TownPlan
extends RefCounted
## The town's houses, made of the same 2 m grid pieces the player builds with (W1a).
## generate() is pure: the same seed always gives the same town. It returns
##   {"pieces": [{id, cell, side, style}], "containers": [{id, table, cell, side}],
##    "beds": [{cell, side}], "props": [{id, cell, side, wall, house}],
##    "houses": [{name, cells, door_cell, door_side, plan, mirror, style}],
##    "zombies": [{house, cell, pos, facing}], "factory": {cells, pieces, crates, doorway, windows}}
## W1b: "zombies" are the houses with one zombie standing inside (about one in three, never on the first
## lot by the spawn), and "factory" is the factory hall at the road's north end, also made of pieces.
## Edge pieces use BuildGrid's canonical edges (NORTH or WEST of a cell). A container or bed `side`
## is the wall it stands against; it faces the other way, into the room.
## W1c: "props" are furniture pieces (data kind "prop": counter, table, couch, shelf, bathtub, toilet), laid by
## SimWorld.place_props like any other piece. A prop's `side` is the way it faces (BuildGrid's object side,
## into the room) and `wall` the wall behind it; "against_wall" in buildables.json stands it there.
## Nothing else in src/sim knows what a house is: SimWorld.place_town lays these pieces into the
## BuildGrid exactly as if the player had built them, so doors, damage, repair and muffling just work.

const LOTS := 6                 # houses per side of the road, as before W1a
const FIRST_LOT_Z := -10.0      # the middle of lot 0 (z in metres); each next lot is LOT_SPACING further north
const LOT_SPACING := 16.0
const EAST_FIRST_CELL := 4      # east houses start at x = 8 m; west houses end at x = -8 m (cell -5)

## W1c "props": [id, u, v, wall] furniture against the wall `wall` of cell (u, v). Rooms are 2 x 2 cells, so they
## are placed by hand, not by a search: never on a door's cell or a container's or bed's cell, each with its
## back to a wall (a counter or table may stand under a window), and each keeping the half of every cell
## away from its wall free, so a 1 m path runs through every doorway (test_town_plan.gd walks it on half cells).
## Kitchens get a counter, and a table where there's room (plan B's kitchen-living room, and plan C's living room
## next to its kitchen; plan A's kitchen is full); living rooms a couch and a shelf; bedrooms a shelf;
## bathrooms a bathtub and a toilet (plan A), or one of them where the room is two cells (B a tub, C a toilet).
## Floor plans in local cells: u = rows back from the road (0 = the front row), v = cells along the road.
## An edge is [u, v, dir]: F faces the road, B faces away, L is toward v - 1, R toward v + 1.
## Every outside edge of a house is a wall unless it's a door or a window. "walls" are the interior walls;
## an interior edge not listed is an open doorway. Every plan has an interior wall straight behind the
## front door, so you walk into a room, not through the house.
const PLANS := {
	# 4 x 4 cells (8 x 8 m): living room (front left), kitchen behind it, bedroom (front right), bathroom.
	"A": {"size": [4, 4], "missing": [],
		"front_door": [0, 0, "F"], "back_door": [3, 0, "B"],
		"windows": [[0, 3, "F"], [1, 0, "L"], [1, 3, "R"], [3, 2, "B"]],
		"walls": [[1, 0, "B"], [0, 1, "R"], [2, 1, "R"], [1, 2, "B"], [1, 3, "B"]],
		"containers": [["fridge", 3, 1, "B"], ["kitchen", 2, 0, "L"], ["bathroom", 3, 3, "R"]],
		"bed": [0, 3, "R"],
		"props": [["couch", 0, 1, "F"], ["shelf", 1, 0, "B"], ["counter", 2, 1, "R"], ["shelf", 0, 2, "F"],
				["bathtub", 2, 2, "F"], ["toilet", 2, 3, "F"]]},
	# 3 x 5 cells (6 m deep, 10 m along the road): kitchen-living room with a galley kitchen at the back,
	# bedroom, and a bathroom off the bedroom.
	"B": {"size": [3, 5], "missing": [],
		"front_door": [0, 1, "F"], "back_door": [2, 0, "B"],
		"windows": [[0, 0, "F"], [0, 4, "F"], [0, 0, "L"], [2, 4, "R"]],
		"walls": [[1, 1, "B"], [1, 2, "B"], [0, 2, "R"], [2, 2, "R"], [1, 4, "B"]],
		"containers": [["fridge", 2, 2, "B"], ["kitchen", 2, 1, "B"], ["bathroom", 2, 4, "B"]],
		"bed": [1, 4, "R"],
		"props": [["counter", 0, 2, "F"], ["table", 1, 0, "L"], ["couch", 1, 1, "B"], ["shelf", 1, 2, "B"],
				["shelf", 0, 3, "F"], ["bathtub", 2, 3, "B"]]},
	# L-shape: 4 x 5 cells without the 2 x 2 back corner. Living room, kitchen and bathroom behind it,
	# bedroom in the front wing.
	"C": {"size": [4, 5], "missing": [[2, 3], [2, 4], [3, 3], [3, 4]],
		"front_door": [0, 1, "F"], "back_door": [3, 0, "B"],
		"windows": [[0, 0, "F"], [0, 3, "F"], [1, 4, "B"], [2, 0, "L"]],
		"walls": [[1, 1, "B"], [1, 2, "B"], [2, 1, "R"], [0, 2, "R"]],
		"containers": [["fridge", 3, 1, "B"], ["kitchen", 2, 1, "R"], ["bathroom", 3, 2, "B"]],
		"bed": [0, 4, "R"],
		"props": [["counter", 2, 0, "L"], ["table", 0, 0, "L"], ["couch", 0, 2, "F"], ["shelf", 1, 0, "L"],
				["toilet", 2, 2, "F"], ["shelf", 0, 3, "L"]]},
}
const PLAN_IDS := ["A", "B", "C"]
const HOUSE_ZOMBIES := 4        # of the 12 houses (W1b); the two on lot 0, by the spawn, never get one

## The factory hall (W1b): FACTORY_SIZE cells from FACTORY_CELL (its north-west corner), where the old solid
## block stood. Its south wall faces the end of the road and has a doorway FACTORY_DOOR cells wide
## (empty edges, no door) centred on the road. A few windows down the long sides; three supply crates inside.
const FACTORY_CELL := Vector2i(-8, -69)
const FACTORY_SIZE := Vector2i(15, 12)
const FACTORY_DOOR := [-1, 0]   # cell x of the doorway's two edges in the south wall
## M17a: the same two cells are open in the north wall too, onto the park road (ParkPlan).
const FACTORY_NORTH_DOOR := [-1, 0]
const FACTORY_WINDOWS := [-67, -64, -61]  # cell z of the windows in the west and east walls
const FACTORY_PETE := Vector2i(-1, -62)  # M13: where Old Pete stands, between the crates
const FACTORY_CRATES := [Vector2i(-5, -60), Vector2i(0, -64), Vector2i(4, -60)]
## W1c: two shelves against the north wall and a table against the east wall, well away from the doorway.
const FACTORY_PROPS := [["shelf", Vector2i(-6, -69), BuildGrid.Side.NORTH], ["shelf", Vector2i(3, -69), BuildGrid.Side.NORTH],
		["table", Vector2i(6, -66), BuildGrid.Side.EAST]]


static func generate(seed_value: int, _data: GameData = null) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "town"])
	var out := {"pieces": [], "containers": [], "beds": [], "props": [], "houses": []}
	for i in LOTS:
		for east in [false, true]:
			var plan_id: String = PLAN_IDS[rng.randi_range(0, PLAN_IDS.size() - 1)]
			var mirror := rng.randf() < 0.5
			# Every third house is brick, the rest painted siding (the same pattern as the old boxes).
			var style := "brick" if (i * 2 + (1 if east else 0)) % 3 == 0 else "siding"
			_add_house(out, "house_%d_%s" % [i, "e" if east else "w"], plan_id, mirror, east, lot_z(i), style)
	out["zombies"] = _house_zombies(seed_value, out)
	out["factory"] = factory()
	return out


## W1b: which houses have a zombie standing inside, and where. Its own random stream, so the houses
## themselves don't change. HOUSE_ZOMBIES of the houses past lot 0; each stands next to the fridge or the
## kitchen cabinet (in the same room, no wall between), so searching the kitchen is close enough to wake it.
static func _house_zombies(seed_value: int, town: Dictionary, count: int = HOUSE_ZOMBIES, salt: String = "house_zombies") -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, salt])
	var pick: Array = []
	for i in town["houses"].size():
		if not town["houses"][i]["name"].begins_with("house_0_"):
			pick.append(i)
	for i in range(pick.size() - 1, 0, -1):  # a seeded shuffle
		var j := rng.randi_range(0, i)
		var t: int = pick[i]
		pick[i] = pick[j]
		pick[j] = t
	pick = pick.slice(0, count)
	pick.sort()
	var edges := {}
	for p: Dictionary in town["pieces"]:
		if p["id"] != "town_floor":
			edges[piece_key(p)] = true
	var out: Array = []
	for i: int in pick:
		var house: Dictionary = town["houses"][i]
		var busy := {house["door_cell"]: true}
		var kitchen: Array = []
		for c: Dictionary in town["containers"]:
			if c["id"].begins_with(house["name"] + "_"):
				busy[c["cell"]] = true
				if c["table"] != "bathroom":
					kitchen.append(c["cell"])
		for b: Dictionary in town["beds"]:
			if b["cell"] in house["cells"]:
				busy[b["cell"]] = true
		for p: Dictionary in town["props"]:
			if p["house"] == house["name"]:
				busy[p["cell"]] = true  # W1c: not inside the furniture
		var spots: Array = []
		for k: Vector2i in kitchen:
			for side in 4:
				var n: Vector2i = k + [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
				if n in house["cells"] and not busy.has(n) and not spots.has(n) 						and not edges.has(BuildGrid.key_for_wall_edge(k, side)):
					spots.append(n)
		if spots.is_empty():  # no open cell by the kitchen: anywhere free in the house
			for c: Vector2i in house["cells"]:
				if not busy.has(c):
					spots.append(c)
		var cell: Vector2i = spots[rng.randi_range(0, spots.size() - 1)]
		var g := BuildGrid.GRID
		var pos := Vector3((cell.x + 0.5) * g, 0.1, (cell.y + 0.5) * g)
		var door: Vector2i = house["door_cell"]
		var facing := Vector3((door.x - cell.x) * g, 0, (door.y - cell.y) * g)
		out.append({"house": i, "cell": cell, "pos": pos,
				"facing": facing.normalized() if facing.length_squared() > 0.01 else Vector3.FORWARD})
	return out


## W1b: the factory hall. Floor on every cell, brick town walls all round ("factory" style) except the
## doorway's empty edges and a few windows. M17a: a second doorway in the north wall ("north_doorway") opens
## onto the park road. Pure and seed-free: the factory is the same in every town.
static func factory() -> Dictionary:
	var out := {"cells": [], "pieces": [], "crates": FACTORY_CRATES.duplicate(), "doorway": [], "north_doorway": [], "windows": 0,
			# M13: Old Pete stands in the middle of the hall, facing the doorway. Q4: he guards the hall ("guard":
			# his home area, the hall's footprint), so he never leaves it (ZombieBrain.set_guard).
			"pete": {"cell": FACTORY_PETE, "pos": Vector3((FACTORY_PETE.x + 0.5) * BuildGrid.GRID, 0.1,
					(FACTORY_PETE.y + 0.5) * BuildGrid.GRID), "facing": Vector3(0, 0, 1), "guard": factory_rect()}}
	out["props"] = []
	for fp: Array in FACTORY_PROPS:
		out["props"].append({"id": fp[0], "cell": fp[1], "wall": fp[2], "side": (fp[2] + 2) % 4, "house": "factory"})
	var x0 := FACTORY_CELL.x
	var z0 := FACTORY_CELL.y
	var x1 := x0 + FACTORY_SIZE.x - 1
	var z1 := z0 + FACTORY_SIZE.y - 1
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			out["cells"].append(Vector2i(x, z))
			out["pieces"].append({"id": "town_floor", "cell": Vector2i(x, z), "side": BuildGrid.Side.NORTH, "style": "floor"})
	var edge := func(cell: Vector2i, side: int, id: String) -> void:
		var e := BuildGrid.canonical_edge(cell, side)
		out["pieces"].append({"id": id, "cell": e[0], "side": e[1], "style": "factory"})
	for x in range(x0, x1 + 1):
		if x in FACTORY_NORTH_DOOR:
			out["north_doorway"].append(BuildGrid.key_for_wall_edge(Vector2i(x, z0), BuildGrid.Side.NORTH))
		else:
			edge.call(Vector2i(x, z0), BuildGrid.Side.NORTH, "town_wall")
		if x in FACTORY_DOOR:
			out["doorway"].append(BuildGrid.key_for_wall_edge(Vector2i(x, z1), BuildGrid.Side.SOUTH))
		else:
			edge.call(Vector2i(x, z1), BuildGrid.Side.SOUTH, "town_wall")
	for z in range(z0, z1 + 1):
		var id := "window" if z in FACTORY_WINDOWS else "town_wall"
		edge.call(Vector2i(x0, z), BuildGrid.Side.WEST, id)
		edge.call(Vector2i(x1, z), BuildGrid.Side.EAST, id)
		if id == "window":
			out["windows"] += 2
	return out


## The factory's footprint on the ground (x, z) in metres.
static func factory_rect() -> Rect2:
	var g := BuildGrid.GRID
	return Rect2(FACTORY_CELL.x * g, FACTORY_CELL.y * g, FACTORY_SIZE.x * g, FACTORY_SIZE.y * g)


## Where lot `i` is centred along the road (metres).
static func lot_z(i: int) -> float:
	return FIRST_LOT_Z - i * LOT_SPACING


## W3c: `road_cell` is the road's middle in cells (0 = Main Street; SuburbPlan's West and East Streets).
static func _add_house(out: Dictionary, house_name: String, plan_id: String, mirror: bool, east: bool,
		z_mid: float, style: String, road_cell: int = 0) -> void:
	var plan: Dictionary = PLANS[plan_id]
	var depth: int = plan["size"][0]
	var length: int = plan["size"][1]
	var v0 := floori(z_mid / BuildGrid.GRID) - floori(length / 2.0)
	var place := func(u: int, v: int) -> Vector2i:
		var vv := (length - 1 - v) if mirror else v
		return Vector2i(road_cell + EAST_FIRST_CELL + u if east else road_cell - EAST_FIRST_CELL - 1 - u, v0 + vv)
	var missing := {}
	for m: Array in plan["missing"]:
		missing[Vector2i(m[0], m[1])] = true
	var cells: Array = []
	var local_cells := {}
	for u in depth:
		for v in length:
			if not missing.has(Vector2i(u, v)):
				local_cells[Vector2i(u, v)] = true
				cells.append(place.call(u, v))
	for c: Vector2i in cells:
		out["pieces"].append({"id": "town_floor", "cell": c, "side": BuildGrid.Side.NORTH, "style": "floor"})
	# Outside edges: wall, unless the plan puts a door or a window there.
	var special := {}  # world edge key -> piece id
	var front: Array = plan["front_door"]
	var back: Array = plan["back_door"]
	special[_edge_key(place.call(front[0], front[1]), _side(front[2], east, mirror))] = "door"
	special[_edge_key(place.call(back[0], back[1]), _side(back[2], east, mirror))] = "door"
	for w: Array in plan["windows"]:
		special[_edge_key(place.call(w[0], w[1]), _side(w[2], east, mirror))] = "window"
	for lc: Vector2i in local_cells:
		for dir: String in ["F", "B", "L", "R"]:
			if local_cells.has(lc + _step(dir)):
				continue  # an inside edge
			var side := _side(dir, east, mirror)
			var key := _edge_key(place.call(lc.x, lc.y), side)
			_add_edge(out, special.get(key, "town_wall"), place.call(lc.x, lc.y), side, style)
	for w: Array in plan["walls"]:
		_add_edge(out, "town_wall", place.call(w[0], w[1]), _side(w[2], east, mirror), "plaster")
	for c: Array in plan["containers"]:
		out["containers"].append({"id": "%s_%s" % [house_name, c[0]], "table": c[0],
				"cell": place.call(c[1], c[2]), "side": _side(c[3], east, mirror)})
	for pr: Array in plan["props"]:
		var wall := _side(pr[3], east, mirror)
		out["props"].append({"id": pr[0], "cell": place.call(pr[1], pr[2]), "side": (wall + 2) % 4, "wall": wall,
				"house": house_name})
	var bed: Array = plan["bed"]
	out["beds"].append({"cell": place.call(bed[0], bed[1]), "side": _side(bed[2], east, mirror)})
	out["houses"].append({"name": house_name, "cells": cells, "plan": plan_id, "mirror": mirror, "style": style,
			"east": east, "door_cell": place.call(front[0], front[1]), "door_side": _side(front[2], east, mirror)})


static func _add_edge(out: Dictionary, id: String, cell: Vector2i, side: int, style: String) -> void:
	var edge := BuildGrid.canonical_edge(cell, side)
	out["pieces"].append({"id": id, "cell": edge[0], "side": edge[1], "style": style})


static func _step(dir: String) -> Vector2i:
	return {"F": Vector2i(-1, 0), "B": Vector2i(1, 0), "L": Vector2i(0, -1), "R": Vector2i(0, 1)}[dir]


## A local direction as a grid side. East houses face the road to the west, west houses to the east;
## L is north (-Z) unless the plan is mirrored along the road.
static func _side(dir: String, east: bool, mirror: bool) -> int:
	match dir:
		"F":
			return BuildGrid.Side.WEST if east else BuildGrid.Side.EAST
		"B":
			return BuildGrid.Side.EAST if east else BuildGrid.Side.WEST
		"L":
			return BuildGrid.Side.SOUTH if mirror else BuildGrid.Side.NORTH
	return BuildGrid.Side.NORTH if mirror else BuildGrid.Side.SOUTH


static func _edge_key(cell: Vector2i, side: int) -> String:
	return BuildGrid.key_for_wall_edge(cell, side)


## The BuildGrid key for one of the plan's pieces.
static func piece_key(p: Dictionary) -> String:
	if p["id"] == "town_floor":
		return "f:%d:%d" % [p["cell"].x, p["cell"].y]
	return BuildGrid.key_for_wall_edge(p["cell"], p["side"])


## Which house (index into plan["houses"]) has `cell`, or -1.
static func house_at(plan: Dictionary, cell: Vector2i) -> int:
	for i in plan["houses"].size():
		if cell in plan["houses"][i]["cells"]:
			return i
	return -1
