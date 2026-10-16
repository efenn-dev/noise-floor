class_name RuralPlan
extends RefCounted
## W3d: the countryside's buildings, seeded like TownPlan: a farm in each of WorldMap AREAS "farm_west" and
## "farm_south", built round the farm's well (an F1 resource node), and the hunting cabin in its clearing in the
## woods (AREAS "cabin"). generate(seed) gives TownPlan's shape for the farmhouses and the cabin, so
## SimWorld.place_town/place_props/spawn_house_zombies, main.gd's fridges and cupboards and a TownView (roofs)
## handle them unchanged:
##   {"pieces", "containers", "beds", "props", "houses", "zombies"}
## and, for what TownPlan has no word for:
##   "barns": [{name, rect, cells, farm}]                    walls and floor in "pieces"; roof drawn by RuralView
##   "fixtures": [{id, model, pos, facing, size, table}]     DowntownPlan-style props (barn crates, the tractor,
##                                                           hay inside, the cabin's gun locker); a table = searchable
##   "outdoor": [{kind, pos, yaw, scale}]                    CountryView-style scatter: corn, the field fences, hay
##                                                           bales and a trough in the yard
##   "yard_zombies": [{type, pos, facing}]                   in the barns and out in the fields
## Every entry (pieces, containers, beds, props, fixtures, houses, barns, zombies) carries the name of its
## "building", so without(plan, names) can leave one out: SimWorld.place_rural skips a building when an older
## save already has something built where it would stand (SimWorld.rural_skipped, saved).
## A farm: a north-south dirt drive (WorldMap "west_farm_drive" / "south_farm_drive") with the farmhouse west of
## it facing it (a TownPlan house, 8 m back like Main Street's) and the barn east of it, its big open doorway on
## the drive; a fenced cornfield past the well, with a gate toward the drive.

const FARMS := [
	{"name": "west", "drive_x": -256.0, "house_z": 100.0, "barn_cell": Vector2i(-125, 47), "field": Rect2(-322, 152, 116, 44)},
	{"name": "south", "drive_x": -60.0, "house_z": 158.0, "barn_cell": Vector2i(-27, 72), "field": Rect2(-145, 207, 120, 48)},
]
const BARN_SIZE := Vector2i(6, 10)   # cells: deep (x, away from the drive), along the drive (z)
const BARN_DOOR_ROW := 4             # the doorway's first row from the barn's north end (two rows wide)
const BARN_BACK_ROW := 7             # the back door's row
const CABIN_CELL := Vector2i(-113, -157)
const CABIN_SIZE := Vector2i(3, 4)   # x -226..-220, z -314..-306; the door is in the east wall, toward the track
const CORN_ALONG := 2.0              # corn_row sections along a row (x)
const CORN_ROWS := 2.6               # between rows (z)
const FENCE := 2.0
const GATE := 6.0                    # the field's gate, in its north fence, toward the drive
const SIZES := {"storage": Vector3(1.4, 1.0, 1.0), "tractor_wreck": Vector3(3.6, 2.7, 1.9),
		"hay_bale_round": Vector3(1.4, 1.3, 1.4), "gun_locker": Vector3(1.0, 1.9, 0.45)}


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "rural"])
	var out := {"pieces": [], "containers": [], "beds": [], "props": [], "houses": [], "zombies": [],
			"barns": [], "fixtures": [], "outdoor": [], "yard_zombies": []}
	for farm: Dictionary in FARMS:
		_add_farm(out, farm, rng)
	_add_cabin(out)
	out["zombies"] = TownPlan._house_zombies(seed_value, out, 2, "rural_zombies")
	for zd: Dictionary in out["zombies"]:
		zd["building"] = out["houses"][zd["house"]]["name"]
	_add_yard_zombies(out, rng)
	return out


## The plan less the buildings named in `names` (their pieces, containers, beds, furniture, fixtures, zombies;
## a farm's fields stay: there's nothing to land on).
static func without(plan: Dictionary, names: Array) -> Dictionary:
	if names.is_empty():
		return plan
	var gone := {}
	for n: Variant in names:
		gone[str(n)] = true
	var keep := func(e: Dictionary) -> bool: return not gone.has(str(e.get("building", "")))
	var out := plan.duplicate()
	for k: String in ["pieces", "containers", "beds", "props", "fixtures", "zombies", "yard_zombies", "houses", "barns"]:
		out[k] = (plan[k] as Array).filter(keep)
	return out


## Every BuildGrid key a building would take: its pieces, its bed, and the object spot on each of its cells.
static func building_keys(plan: Dictionary, building: String) -> Array:
	var keys: Array = []
	for p: Dictionary in plan["pieces"]:
		if p["building"] == building:
			keys.append(TownPlan.piece_key(p))
			if p["id"] == "town_floor":
				keys.append("o:%d:%d" % [p["cell"].x, p["cell"].y])
	return keys


## Every building's name, in order.
static func buildings(plan: Dictionary) -> Array:
	var names: Array = []
	for p: Dictionary in plan["pieces"]:
		if not p["building"] in names:
			names.append(p["building"])
	return names


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * BuildGrid.GRID, c.y * BuildGrid.GRID, BuildGrid.GRID, BuildGrid.GRID)


## A farm: the farmhouse (a TownPlan house west of the drive), the barn east of it, the field and the yard.
static func _add_farm(out: Dictionary, farm: Dictionary, rng: RandomNumberGenerator) -> void:
	var house_name := "farmhouse_%s" % farm["name"]
	var counts := {}
	for k: String in ["pieces", "containers", "beds", "props"]:
		counts[k] = (out[k] as Array).size()
	var plan_id: String = TownPlan.PLAN_IDS[rng.randi_range(0, TownPlan.PLAN_IDS.size() - 1)]
	var mirror := rng.randf() < 0.5
	var road_cell := roundi(float(farm["drive_x"]) / BuildGrid.GRID)
	TownPlan._add_house(out, house_name, plan_id, mirror, false, farm["house_z"], "siding" if rng.randf() < 0.6 else "brick", road_cell)
	for k: String in counts:
		for i in range(int(counts[k]), (out[k] as Array).size()):
			out[k][i]["building"] = house_name
	out["houses"][-1]["building"] = house_name
	out["houses"][-1]["road_x"] = farm["drive_x"]
	_add_barn(out, farm, rng)
	_add_field(out, farm, rng)


## The barn: a floor on every cell, barn-red walls, a two-cell open doorway facing the drive (west), a back door,
## two windows in each end wall. Inside: the tractor, three crates against the back wall, round hay bales.
static func _add_barn(out: Dictionary, farm: Dictionary, rng: RandomNumberGenerator) -> void:
	var bname := "barn_%s" % farm["name"]
	var c0: Vector2i = farm["barn_cell"]
	var x1 := c0.x + BARN_SIZE.x - 1
	var z1 := c0.y + BARN_SIZE.y - 1
	var cells: Array = []
	var edge := func(cell: Vector2i, side: int, id: String) -> void:
		var e := BuildGrid.canonical_edge(cell, side)
		out["pieces"].append({"id": id, "cell": e[0], "side": e[1], "style": "barn", "building": bname})
	for x in range(c0.x, x1 + 1):
		for z in range(c0.y, z1 + 1):
			cells.append(Vector2i(x, z))
			out["pieces"].append({"id": "town_floor", "cell": Vector2i(x, z), "side": BuildGrid.Side.NORTH, "style": "floor", "building": bname})
	for z in range(c0.y, z1 + 1):
		var row := z - c0.y
		if row != BARN_DOOR_ROW and row != BARN_DOOR_ROW + 1:
			edge.call(Vector2i(c0.x, z), BuildGrid.Side.WEST, "town_wall")
		edge.call(Vector2i(x1, z), BuildGrid.Side.EAST, "door" if row == BARN_BACK_ROW else "town_wall")
	for x in range(c0.x, x1 + 1):
		var id := "window" if x == c0.x + 1 or x == x1 - 1 else "town_wall"
		edge.call(Vector2i(x, c0.y), BuildGrid.Side.NORTH, id)
		edge.call(Vector2i(x, z1), BuildGrid.Side.SOUTH, id)
	var g := BuildGrid.GRID
	var r := Rect2(c0.x * g, c0.y * g, BARN_SIZE.x * g, BARN_SIZE.y * g)
	out["barns"].append({"name": bname, "rect": r, "cells": cells, "farm": farm["name"], "building": bname})
	var west := Vector2(-1, 0)
	var add := func(model: String, at: Vector2, facing: Vector2, table: String, k: int) -> void:
		out["fixtures"].append({"id": "%s_%s_%d" % [bname, model, k], "model": model, "pos": Vector3(at.x, 0.1, at.y),
				"facing": facing, "size": SIZES[model], "table": table, "building": bname})
	add.call("tractor_wreck", Vector2(r.position.x + 7.0, r.position.y + 6.5), west, "tractor", 0)
	var back_x := r.end.x - 0.1 - SIZES["storage"].z / 2.0 - 0.05
	var k := 0
	for dz: float in [2.5, 5.0, 18.0]:
		add.call("storage", Vector2(back_x, r.position.y + dz), west, "barn", k)
		k += 1
	for i in 3:
		var bale_z := r.end.y - 0.1 - SIZES["hay_bale_round"].z / 2.0 - 0.1
		add.call("hay_bale_round", Vector2(r.position.x + 4.0 + 1.6 * i, bale_z), Vector2(0, -1), "", i)
	# In the yard: a trough by the barn's door and a few round bales and a stack of square ones by its south end.
	out["outdoor"].append({"kind": "water_trough", "pos": Vector3(r.position.x - 1.2, 0, r.position.y + BARN_DOOR_ROW * g - 2.5),
			"yaw": PI / 2.0, "scale": 1.0})
	for i in 3:
		out["outdoor"].append({"kind": "hay_bale_round", "pos": Vector3(r.position.x + 2.5 + 2.2 * i + rng.randf_range(-0.3, 0.3), 0, r.end.y + 2.5),
				"yaw": rng.randf_range(0.0, TAU), "scale": 1.0})
	for i in 4:
		out["outdoor"].append({"kind": "hay_bale_square", "pos": Vector3(r.end.x - 2.0 - 1.05 * i, 0, r.end.y + 1.2), "yaw": 0.0, "scale": 1.0})


## The cornfield: rows of corn (walk-through, a good place to hide) inside a farm fence with a gate in its north
## side toward the drive.
static func _add_field(out: Dictionary, farm: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Rect2 = farm["field"]
	var gate_x: float = clampf(farm["drive_x"], f.position.x + GATE, f.end.x - GATE)
	var z := f.position.y + 2.0
	while z < f.end.y - 1.5:
		var x := f.position.x + 2.0
		while x < f.end.x - 1.5:
			if rng.randf() > 0.06:  # the odd gap, as if trampled
				out["outdoor"].append({"kind": "corn_row", "pos": Vector3(x, 0, z), "yaw": 0.0, "scale": rng.randf_range(0.9, 1.1)})
			x += CORN_ALONG
		z += CORN_ROWS
	var x := f.position.x + FENCE / 2.0
	while x < f.end.x:
		if absf(x - gate_x) > GATE / 2.0:
			out["outdoor"].append({"kind": "farm_fence", "pos": Vector3(x, 0, f.position.y), "yaw": 0.0, "scale": 1.0})
		out["outdoor"].append({"kind": "farm_fence", "pos": Vector3(x, 0, f.end.y), "yaw": 0.0, "scale": 1.0})
		x += FENCE
	z = f.position.y + FENCE / 2.0
	while z < f.end.y:
		for fx: float in [f.position.x, f.end.x]:
			out["outdoor"].append({"kind": "farm_fence", "pos": Vector3(fx, 0, z), "yaw": PI / 2.0, "scale": 1.0})
		z += FENCE


## The hunting cabin: one room, a floor, dark wood walls, the door in the east wall (toward the woods track),
## windows in the north and west walls; a bed, a hunter's cupboard and a gun locker.
static func _add_cabin(out: Dictionary) -> void:
	var bname := "hunting_cabin"
	var c0 := CABIN_CELL
	var x1 := c0.x + CABIN_SIZE.x - 1
	var z1 := c0.y + CABIN_SIZE.y - 1
	var door := Vector2i(x1, c0.y + 1)
	var cells: Array = []
	var edge := func(cell: Vector2i, side: int, id: String) -> void:
		var e := BuildGrid.canonical_edge(cell, side)
		out["pieces"].append({"id": id, "cell": e[0], "side": e[1], "style": "cabin", "building": bname})
	for x in range(c0.x, x1 + 1):
		for z in range(c0.y, z1 + 1):
			cells.append(Vector2i(x, z))
			out["pieces"].append({"id": "town_floor", "cell": Vector2i(x, z), "side": BuildGrid.Side.NORTH, "style": "floor", "building": bname})
	for z in range(c0.y, z1 + 1):  # windows north (middle) and west (between the bed and the cupboard)
		edge.call(Vector2i(x1, z), BuildGrid.Side.EAST, "door" if Vector2i(x1, z) == door else "town_wall")
		edge.call(Vector2i(c0.x, z), BuildGrid.Side.WEST, "window" if z == c0.y + 1 else "town_wall")
	for x in range(c0.x, x1 + 1):  # the gun locker stands against the south wall
		edge.call(Vector2i(x, c0.y), BuildGrid.Side.NORTH, "window" if x == c0.x + 1 else "town_wall")
		edge.call(Vector2i(x, z1), BuildGrid.Side.SOUTH, "town_wall")
	out["beds"].append({"cell": Vector2i(c0.x, c0.y), "side": BuildGrid.Side.WEST, "building": bname})
	out["containers"].append({"id": "hunting_cabin_cupboard", "table": "hunter", "cell": Vector2i(c0.x, c0.y + 2),
			"side": BuildGrid.Side.WEST, "building": bname})
	var g := BuildGrid.GRID
	var locker_z := (z1 + 1) * g - 0.1 - SIZES["gun_locker"].z / 2.0 - 0.05
	out["fixtures"].append({"id": "hunting_cabin_gun_locker", "model": "gun_locker", "pos": Vector3((c0.x + 1.5) * g, 0.1, locker_z),
			"facing": Vector2(0, -1), "size": SIZES["gun_locker"], "table": "hunting_cabin", "building": bname})
	out["houses"].append({"name": bname, "cells": cells, "plan": "cabin", "mirror": false, "style": "cabin", "east": false,
			"door_cell": door, "door_side": BuildGrid.Side.EAST, "building": bname, "road_x": -200.0})


## One zombie in each barn (on a free spot, facing the doorway), two out in each field, and one by the cabin.
static func _add_yard_zombies(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g := BuildGrid.GRID
	for barn: Dictionary in out["barns"]:
		var r: Rect2 = barn["rect"]
		var spot := Vector2(r.position.x + 3.0, r.position.y + 12.0 + rng.randf_range(0.0, 3.0))
		out["yard_zombies"].append({"type": "shambler", "pos": Vector3(spot.x, 0.1, spot.y), "facing": Vector3(-1, 0, 0),
				"building": barn["name"]})
	for i in FARMS.size():
		var f: Rect2 = FARMS[i]["field"]
		for k in 2:
			var p := Vector2(rng.randf_range(f.position.x + 6.0, f.end.x - 6.0), rng.randf_range(f.position.y + 4.0, f.end.y - 4.0))
			out["yard_zombies"].append({"type": "runner" if i == 1 and k == 1 else "shambler", "pos": Vector3(p.x, 0.0, p.y),
					"facing": Vector3(0, 0, -1), "building": ""})
	var door_x := (CABIN_CELL.x + CABIN_SIZE.x) * g
	out["yard_zombies"].append({"type": "shambler", "pos": Vector3(door_x + 6.0, 0.0, (CABIN_CELL.y + 3) * g),
			"facing": Vector3(1, 0, 0), "building": ""})
