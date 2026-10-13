class_name ParkPlan
extends RefCounted
## M17a: the industrial park, the second area, north of the factory hall. Pure and seeded, like TownPlan:
## generate(seed) gives
##   {"warehouses": [{name, cells, rect, style, east, doorway: [edge keys], back_door: edge key}],
##    "pieces": [{id, cell, side, style}], "crates": [{id, table, cell, side, warehouse}],
##    "zombies": [{type, pos, facing, warehouse}], "wrecks": [{id, type, pos, yaw}],
##    "fences": [{pos, yaw}], "tower": {pos, rect}}
## Four warehouses (two each side of the park road) are grid interiors like the houses: a floor on every cell,
## outside walls in brick or corrugated metal, a big open doorway (DOOR_WIDTH cells, no door) facing the road,
## a one-cell back doorway, two windows in each end wall; TownView-like roofs are drawn by ParkView. Each holds
## CRATES_MIN..CRATES_MAX supply crates (loot table "industrial"). Zombies stand inside and between them from
## the start. Two or three wrecked cars sit on the park road (wrecks only). A wire fence (grey picket sections)
## runs along the park's west, east and north edges and the two ends of its south edge, with gaps. The water
## tower stands at TOWER_POS, east of the road between the two east warehouses.
## The road runs north from the factory hall's north wall (ROAD_SOUTH_Z) to ROAD_NORTH_Z; the Director's north
## road end is just past it (Director.EDGES[0]).

const ROAD_SOUTH_Z := -138.0   # the factory hall's north wall
const ROAD_NORTH_Z := -258.0   # the park road's north end
const ROAD_HALF := 4.0
const ENTRANCE := Vector3(0, 0, -143)  # the park's south entrance, just outside the hall's north doorway
const FENCE_X := 36.0          # the west and east fence lines (x = -36 and 36)
const FENCE_NORTH_Z := -256.0
const FENCE_SOUTH_Z := -142.0
const FENCE_ROAD_GAP := 6.0    # the north fence stops this far either side of the road's middle
## The south edge only has fence at its two ends: the factory hall fills the middle, and the Director's road
## route comes round the hall's west side at x = -25 (Director.NORTH_VIA), so the west run stops at x = -30.
const FENCE_SOUTH_RUNS := [[-36.0, -30.0], [18.0, 36.0]]
const FENCE_LENGTH := 2.0
const SIZE := Vector2i(6, 10)  # warehouse cells: 6 deep (x, away from the road), 10 along the road (z)
const WEST_CELL_X := -11       # west warehouses span x cells -11..-6 (x -22..-10 m)
const EAST_CELL_X := 5         # east warehouses span x cells 5..10 (x 10..22 m)
const SLOT_Z := [-84, -112]    # each slot's north-most cell row (z -168 and -224 m), jittered by one cell
const DOOR_WIDTH := 2
const CRATES_MIN := 3
const CRATES_MAX := 5
const STYLES := ["park_brick", "corrugated"]
const SHAMBLERS := 10
const RUNNERS := 2
const INSIDE_PER_WAREHOUSE := 2  # the other zombies stand outside, between the warehouses
const TOWER_POS := Vector3(15, 0, -186)
const TOWER_HALF := 3.0        # the tower's footprint is 6 x 6 m
const WRECK_TYPES := ["sedan", "pickup", "van"]
const WRECK_X := 2.6           # off the road's middle, so the Director's route line stays clear


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "park"])
	var out := {"warehouses": [], "pieces": [], "crates": [], "zombies": [], "wrecks": [], "fences": [],
			"tower": {"pos": TOWER_POS, "rect": tower_rect()}}
	var n := 0
	for slot in SLOT_Z.size():
		for east in [false, true]:
			_add_warehouse(out, rng, "warehouse_%d" % n, east, SLOT_Z[slot] + rng.randi_range(-1, 1))
			n += 1
	_add_zombies(out, rng)
	_add_wrecks(out, rng)
	_add_fences(out, rng)
	return out


## The whole park on the ground (x, z): inside the fence line, north of the factory hall.
static func area() -> Rect2:
	return Rect2(-FENCE_X, FENCE_NORTH_Z, 2.0 * FENCE_X, FENCE_SOUTH_Z - FENCE_NORTH_Z)


## The park road's asphalt (x, z).
static func road_rect() -> Rect2:
	return Rect2(-ROAD_HALF, ROAD_NORTH_Z, 2.0 * ROAD_HALF, ROAD_SOUTH_Z - ROAD_NORTH_Z)


static func tower_rect() -> Rect2:
	return Rect2(TOWER_POS.x - TOWER_HALF, TOWER_POS.z - TOWER_HALF, 2.0 * TOWER_HALF, 2.0 * TOWER_HALF)


static func cell_rect(c: Vector2i) -> Rect2:
	var g := BuildGrid.GRID
	return Rect2(c.x * g, c.y * g, g, g)


static func _add_warehouse(out: Dictionary, rng: RandomNumberGenerator, wh_name: String, east: bool, z0: int) -> void:
	var x0 := EAST_CELL_X if east else WEST_CELL_X
	var x1 := x0 + SIZE.x - 1
	var z1 := z0 + SIZE.y - 1
	var style: String = STYLES[rng.randi_range(0, STYLES.size() - 1)]
	var cells: Array = []
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			cells.append(Vector2i(x, z))
			out["pieces"].append({"id": "town_floor", "cell": Vector2i(x, z), "side": BuildGrid.Side.NORTH, "style": "floor"})
	# The road side: west wall for an east warehouse, east wall for a west one. The doorway's first cell
	# along the road is seeded (rows 3..5 of 10), the back doorway is somewhere in the far wall's middle.
	var road_x := x0 if east else x1
	var road_side := BuildGrid.Side.WEST if east else BuildGrid.Side.EAST
	var back_x := x1 if east else x0
	var back_side := BuildGrid.Side.EAST if east else BuildGrid.Side.WEST
	var door_z := z0 + rng.randi_range(3, 5)
	var back_z := z0 + rng.randi_range(2, 7)
	var doorway: Array = []
	var edge := func(cell: Vector2i, side: int, id: String) -> void:
		var e := BuildGrid.canonical_edge(cell, side)
		out["pieces"].append({"id": id, "cell": e[0], "side": e[1], "style": style})
	for z in range(z0, z1 + 1):
		if z >= door_z and z < door_z + DOOR_WIDTH:
			doorway.append(BuildGrid.key_for_wall_edge(Vector2i(road_x, z), road_side))
		else:
			edge.call(Vector2i(road_x, z), road_side, "town_wall")
		if z != back_z:
			edge.call(Vector2i(back_x, z), back_side, "town_wall")
	for x in range(x0, x1 + 1):  # the two end walls, a window either side of the middle
		var id := "window" if x == x0 + 1 or x == x1 - 1 else "town_wall"
		edge.call(Vector2i(x, z0), BuildGrid.Side.NORTH, id)
		edge.call(Vector2i(x, z1), BuildGrid.Side.SOUTH, id)
	var g := BuildGrid.GRID
	var wh := {"name": wh_name, "cells": cells, "style": style, "east": east, "doorway": doorway,
			"back_door": BuildGrid.key_for_wall_edge(Vector2i(back_x, back_z), back_side),
			"rect": Rect2(x0 * g, z0 * g, SIZE.x * g, SIZE.y * g),
			"door_cells": [Vector2i(road_x, door_z), Vector2i(road_x, door_z + 1)], "back_cell": Vector2i(back_x, back_z)}
	out["warehouses"].append(wh)
	# Crates: against an outside wall, never in a doorway's cell or the cells just inside it.
	var keep_clear := {}
	for c: Vector2i in wh["door_cells"] + [wh["back_cell"]]:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				keep_clear[c + Vector2i(dx, dz)] = true
	var spots: Array = []  # [cell, side of the wall it stands against]
	for z in range(z0 + 1, z1):
		spots.append([Vector2i(back_x, z), back_side])
	for x in range(x0, x1 + 1):
		spots.append([Vector2i(x, z0), BuildGrid.Side.NORTH])
		spots.append([Vector2i(x, z1), BuildGrid.Side.SOUTH])
	spots = spots.filter(func(s: Array) -> bool: return not keep_clear.has(s[0]))
	var used := {}
	var count := rng.randi_range(CRATES_MIN, CRATES_MAX)
	var k := 0
	while k < count and not spots.is_empty():
		var s: Array = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		if used.has(s[0]):
			continue
		used[s[0]] = true
		out["crates"].append({"id": "%s_crate_%d" % [wh_name, k], "table": "industrial", "cell": s[0], "side": s[1],
				"warehouse": wh_name})
		k += 1


## SHAMBLERS + RUNNERS zombies: INSIDE_PER_WAREHOUSE standing in each warehouse (on a free cell, away from
## the crates and doorways, facing the doorway), the rest outside between the warehouses (off the road and the
## tower, inside the fence). One runner stands in a warehouse, the other outside.
static func _add_zombies(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g := BuildGrid.GRID
	var busy := {}
	for c: Dictionary in out["crates"]:
		busy[c["cell"]] = true
	var inside: Array = []
	for wi in out["warehouses"].size():
		var wh: Dictionary = out["warehouses"][wi]
		var free: Array = []
		for c: Vector2i in wh["cells"]:
			if busy.has(c) or c in wh["door_cells"] or c == wh["back_cell"]:
				continue
			free.append(c)
		for i in INSIDE_PER_WAREHOUSE:
			var cell: Vector2i = free.pop_at(rng.randi_range(0, free.size() - 1))
			busy[cell] = true
			var pos := Vector3((cell.x + 0.5) * g, 0.1, (cell.y + 0.5) * g)
			var door: Vector2i = wh["door_cells"][0]
			var facing := Vector3(door.x - cell.x, 0, door.y - cell.y)
			inside.append({"type": "shambler", "pos": pos,
					"facing": facing.normalized() if facing.length_squared() > 0.01 else Vector3.FORWARD, "warehouse": wi})
	inside[rng.randi_range(0, inside.size() - 1)]["type"] = "runner"
	var outside: Array = []
	var total := SHAMBLERS + RUNNERS
	var tries := 0
	while inside.size() + outside.size() < total and tries < 1000:
		tries += 1
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := Vector3(side * rng.randf_range(ROAD_HALF + 1.5, 30.0), 0.0, rng.randf_range(-250.0, -150.0))
		if not is_open_ground(out, Vector2(p.x, p.z), 1.5):
			continue
		var too_close := false
		for o: Dictionary in outside:
			too_close = too_close or Vector2(o["pos"].x - p.x, o["pos"].z - p.z).length() < 6.0
		if too_close:
			continue
		var to_road := Vector3(-side, 0, 0)
		outside.append({"type": "shambler", "pos": p, "facing": to_road, "warehouse": -1})
	if not outside.is_empty():
		outside[rng.randi_range(0, outside.size() - 1)]["type"] = "runner"
	out["zombies"] = inside + outside


## Two or three wrecks on the park road, off its middle line, at least 15 m apart.
static func _add_wrecks(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 3)
	var tries := 0
	while out["wrecks"].size() < count and tries < 200:
		tries += 1
		var z := rng.randf_range(-245.0, -155.0)
		var clash := false
		for w: Dictionary in out["wrecks"]:
			clash = clash or absf(w["pos"].z - z) < 15.0
		if clash:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var yaw := deg_to_rad(rng.randf_range(-15.0, 15.0)) + (PI if rng.randf() < 0.5 else 0.0)
		var type: String = WRECK_TYPES[rng.randi_range(0, WRECK_TYPES.size() - 1)]
		out["wrecks"].append({"id": "park_car_%d" % out["wrecks"].size(), "type": type,
				"pos": Vector3(side * WRECK_X, 0.0, z), "yaw": yaw})


## Fence sections (FENCE_LENGTH m each, pos = the middle on the ground, yaw in degrees: 0 runs along x, 90
## along z). Every run of eight sections has a two-section gap at a seeded place, so there's a way through
## at least every 16 m.
static func _add_fences(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var lines: Array = []  # [start (x, z), step (x, z), sections, yaw]
	var along_z := roundi((FENCE_SOUTH_Z - FENCE_NORTH_Z) / FENCE_LENGTH)
	lines.append([Vector2(-FENCE_X, FENCE_NORTH_Z), Vector2(0, FENCE_LENGTH), along_z, 90.0])
	lines.append([Vector2(FENCE_X, FENCE_NORTH_Z), Vector2(0, FENCE_LENGTH), along_z, 90.0])
	var north := roundi((FENCE_X - FENCE_ROAD_GAP) / FENCE_LENGTH)
	lines.append([Vector2(-FENCE_X, FENCE_NORTH_Z), Vector2(FENCE_LENGTH, 0), north, 0.0])
	lines.append([Vector2(FENCE_ROAD_GAP, FENCE_NORTH_Z), Vector2(FENCE_LENGTH, 0), north, 0.0])
	for run: Array in FENCE_SOUTH_RUNS:
		lines.append([Vector2(run[0], FENCE_SOUTH_Z), Vector2(FENCE_LENGTH, 0), roundi((run[1] - run[0]) / FENCE_LENGTH), 0.0])
	for line: Array in lines:
		var gap := rng.randi_range(1, 5)
		for i in int(line[2]):
			if line[2] >= 6 and (i % 8 == gap or i % 8 == gap + 1):
				continue
			var mid: Vector2 = line[0] + line[1] * (i + 0.5)
			out["fences"].append({"pos": Vector3(mid.x, 0, mid.y), "yaw": line[3]})


## Is (x, z) clear ground in the park: inside the fence, off the road, not in a warehouse or the tower's
## footprint (with `margin` metres to spare)?
static func is_open_ground(plan: Dictionary, p: Vector2, margin: float) -> bool:
	if not area().grow(-margin).has_point(p) or road_rect().grow(margin).has_point(p):
		return false
	if tower_rect().grow(margin).has_point(p):
		return false
	for wh: Dictionary in plan["warehouses"]:
		if (wh["rect"] as Rect2).grow(margin).has_point(p):
			return false
	return true


## Which warehouse (index) has `cell`, or -1.
static func warehouse_at(plan: Dictionary, cell: Vector2i) -> int:
	for i in plan["warehouses"].size():
		if cell in plan["warehouses"][i]["cells"]:
			return i
	return -1
