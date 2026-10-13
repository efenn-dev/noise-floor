class_name TownPlan
extends RefCounted
## The town's houses, made of the same 2 m grid pieces the player builds with (W1a).
## generate() is pure: the same seed always gives the same town. It returns
##   {"pieces": [{id, cell, side, style}], "containers": [{id, table, cell, side}],
##    "beds": [{cell, side}], "houses": [{name, cells, door_cell, door_side, plan, mirror, style}]}
## Edge pieces use BuildGrid's canonical edges (NORTH or WEST of a cell). A container or bed `side`
## is the wall it stands against; it faces the other way, into the room.
## Nothing else in src/sim knows what a house is: SimWorld.place_town lays these pieces into the
## BuildGrid exactly as if the player had built them, so doors, damage, repair and muffling just work.

const LOTS := 6                 # houses per side of the road, as before W1a
const FIRST_LOT_Z := -10.0      # the middle of lot 0 (z in metres); each next lot is LOT_SPACING further north
const LOT_SPACING := 16.0
const EAST_FIRST_CELL := 4      # east houses start at x = 8 m; west houses end at x = -8 m (cell -5)

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
		"bed": [0, 3, "R"]},
	# 3 x 5 cells (6 m deep, 10 m along the road): kitchen-living room with a galley kitchen at the back,
	# bedroom, and a bathroom off the bedroom.
	"B": {"size": [3, 5], "missing": [],
		"front_door": [0, 1, "F"], "back_door": [2, 0, "B"],
		"windows": [[0, 0, "F"], [0, 4, "F"], [0, 0, "L"], [2, 4, "R"]],
		"walls": [[1, 1, "B"], [1, 2, "B"], [0, 2, "R"], [2, 2, "R"], [1, 4, "B"]],
		"containers": [["fridge", 2, 2, "B"], ["kitchen", 2, 1, "B"], ["bathroom", 2, 4, "B"]],
		"bed": [1, 4, "R"]},
	# L-shape: 4 x 5 cells without the 2 x 2 back corner. Living room, kitchen and bathroom behind it,
	# bedroom in the front wing.
	"C": {"size": [4, 5], "missing": [[2, 3], [2, 4], [3, 3], [3, 4]],
		"front_door": [0, 1, "F"], "back_door": [3, 0, "B"],
		"windows": [[0, 0, "F"], [0, 3, "F"], [1, 4, "B"], [2, 0, "L"]],
		"walls": [[1, 1, "B"], [1, 2, "B"], [2, 1, "R"], [0, 2, "R"]],
		"containers": [["fridge", 3, 1, "B"], ["kitchen", 2, 1, "R"], ["bathroom", 3, 2, "B"]],
		"bed": [0, 4, "R"]},
}
const PLAN_IDS := ["A", "B", "C"]


static func generate(seed_value: int, _data: GameData = null) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "town"])
	var out := {"pieces": [], "containers": [], "beds": [], "houses": []}
	for i in LOTS:
		for east in [false, true]:
			var plan_id: String = PLAN_IDS[rng.randi_range(0, PLAN_IDS.size() - 1)]
			var mirror := rng.randf() < 0.5
			# Every third house is brick, the rest painted siding (the same pattern as the old boxes).
			var style := "brick" if (i * 2 + (1 if east else 0)) % 3 == 0 else "siding"
			_add_house(out, "house_%d_%s" % [i, "e" if east else "w"], plan_id, mirror, east, lot_z(i), style)
	return out


## Where lot `i` is centred along the road (metres).
static func lot_z(i: int) -> float:
	return FIRST_LOT_Z - i * LOT_SPACING


static func _add_house(out: Dictionary, house_name: String, plan_id: String, mirror: bool, east: bool,
		z_mid: float, style: String) -> void:
	var plan: Dictionary = PLANS[plan_id]
	var depth: int = plan["size"][0]
	var length: int = plan["size"][1]
	var v0 := floori(z_mid / BuildGrid.GRID) - floori(length / 2.0)
	var place := func(u: int, v: int) -> Vector2i:
		var vv := (length - 1 - v) if mirror else v
		return Vector2i(EAST_FIRST_CELL + u if east else -EAST_FIRST_CELL - 1 - u, v0 + vv)
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
