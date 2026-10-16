class_name SuburbPlan
extends RefCounted
## W3c: more streets of houses. West Street and East Street (WorldMap "west_street" and "east_street", AREAS
## "residential_west" and "residential_east") get a row of houses down both sides. The houses are the town's
## own (TownPlan._add_house: its floor plans, furniture, containers and beds, in brick or siding), so
## SimWorld.place_town, place_props and spawn_house_zombies, main.gd's fridges and cabinets, and a second
## TownView (the roofs) handle them unchanged. generate(seed) gives TownPlan's shape without the factory, every
## entry tagged with the name of its house ("house"):
##   {"pieces", "containers", "beds", "props", "houses", "zombies", "items"}
## A lot stands empty now and then (VACANT); about one house in ZOMBIE_SHARE has a zombie inside. "items" are
## StreetPlan-style scenery for a StreetView: a mailbox beside each house's front path, a trash can behind it
## (searchable, "trash", via SimWorld.place_street) and a tree behind about half of them.
## without(plan, names) is the plan less those houses and everything in them: SimWorld.place_suburbs skips a
## house when an older save already has something built where it would stand (SimWorld.suburbs_skipped, saved).

## [name, the road's middle (x, m), the first and last lot middles (z), lot middles to leave empty on a side].
const STREETS := [
	{"name": "west", "road_x": -60.0, "z_from": -92.0, "z_to": 42.0, "skip": {}},
	# The junkyard lane leaves East Street eastward at z = -40, and downtown starts at z = 40.
	{"name": "east", "road_x": 60.0, "z_from": -92.0, "z_to": 23.0, "skip": {"e": [-46.0, -26.0]}},
]
const LOT_SPACING := 19.0
const VACANT := 0.2
const ROAD_HALF := 3.5          # West and East Street are 7 m wide (WorldMap)
const ZOMBIE_SHARE := 3
const MAILBOX_X := 5.3          # from the road's middle, like StreetPlan's
const TRASH_OUT := 0.85         # a trash can's middle, out from the back wall
const TREE_BACK := 2.0          # a tree's canopy keeps this clear of the back wall


static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "suburbs"])
	var out := {"pieces": [], "containers": [], "beds": [], "props": [], "houses": [], "zombies": [], "items": []}
	for street: Dictionary in STREETS:
		var road_cell := roundi(float(street["road_x"]) / BuildGrid.GRID)
		for east in [false, true]:
			var skip: Array = (street["skip"] as Dictionary).get("e" if east else "w", [])
			var lot := 0
			var z: float = street["z_from"]
			while z <= float(street["z_to"]) + 0.01:
				# Every lot draws the same numbers, built or not, so one lot's luck never moves another's house.
				var vacant := rng.randf() < VACANT
				var plan_id: String = TownPlan.PLAN_IDS[rng.randi_range(0, TownPlan.PLAN_IDS.size() - 1)]
				var mirror := rng.randf() < 0.5
				var style := "brick" if rng.randf() < 0.35 else "siding"
				if not vacant and (skip.is_empty() or z < float(skip[0]) or z > float(skip[1])):
					_house(out, "%s_%d_%s" % [street["name"], lot, "e" if east else "w"], plan_id, mirror, east, z, style,
							road_cell)
				lot += 1
				z += LOT_SPACING
	out["zombies"] = TownPlan._house_zombies(seed_value, out, out["houses"].size() / ZOMBIE_SHARE, "suburb_zombies")
	for zd: Dictionary in out["zombies"]:
		zd["house_name"] = out["houses"][zd["house"]]["name"]
	_add_items(out, rng)
	return out


## The plan less the houses named in `names` (their pieces, containers, bed, furniture, zombie and scenery).
static func without(plan: Dictionary, names: Array) -> Dictionary:
	if names.is_empty():
		return plan
	var gone := {}
	for n: Variant in names:
		gone[str(n)] = true
	var keep := func(e: Dictionary) -> bool: return not gone.has(str(e.get("house", "")))
	var out := {}
	for k: String in ["pieces", "containers", "beds", "props"]:
		out[k] = (plan[k] as Array).filter(keep)
	out["houses"] = (plan["houses"] as Array).filter(func(h: Dictionary) -> bool: return not gone.has(str(h["name"])))
	out["zombies"] = (plan["zombies"] as Array).filter(func(zd: Dictionary) -> bool: return not gone.has(str(zd["house_name"])))
	out["items"] = (plan["items"] as Array).filter(func(it: Dictionary) -> bool:
		return not gone.has(str(plan["houses"][it["house"]]["name"])))
	return out


## Every BuildGrid key a house would take: its pieces, its bed, and the object spot on each of its cells.
static func house_keys(plan: Dictionary, house_name: String) -> Array:
	var keys: Array = []
	for p: Dictionary in plan["pieces"]:
		if p["house"] == house_name:
			keys.append(TownPlan.piece_key(p))
	for h: Dictionary in plan["houses"]:
		if h["name"] == house_name:
			for c: Vector2i in h["cells"]:
				keys.append("o:%d:%d" % [c.x, c.y])
	return keys


## The house's footprint on the ground (x, z).
static func house_rect(h: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for c: Vector2i in h["cells"]:
		var cr := Rect2(c.x * BuildGrid.GRID, c.y * BuildGrid.GRID, BuildGrid.GRID, BuildGrid.GRID)
		r = cr if first else r.merge(cr)
		first = false
	return r


static func _house(out: Dictionary, house_name: String, plan_id: String, mirror: bool, east: bool, z: float,
		style: String, road_cell: int) -> void:
	var counts := {}
	for k: String in ["pieces", "containers", "beds"]:
		counts[k] = (out[k] as Array).size()
	TownPlan._add_house(out, house_name, plan_id, mirror, east, z, style, road_cell)
	for k: String in counts:
		for i in range(int(counts[k]), (out[k] as Array).size()):
			out[k][i]["house"] = house_name
	out["houses"][-1]["road_x"] = road_cell * BuildGrid.GRID


## A mailbox by each house's front path, a trash can behind it (not by its back door), and a tree further back
## behind about half of them.
static func _add_items(out: Dictionary, rng: RandomNumberGenerator) -> void:
	var g := BuildGrid.GRID
	var colors: Array = StreetPlan.MAILBOX_COLORS
	var doors := {}
	for p: Dictionary in out["pieces"]:
		if p["id"] == "door":
			doors[TownPlan.piece_key(p)] = true
	var trash := 0
	for i in out["houses"].size():
		var h: Dictionary = out["houses"][i]
		var sx := 1.0 if h["east"] else -1.0
		var door_z: float = (h["door_cell"].y + 0.5) * g
		var along := -1.0 if rng.randf() < 0.5 else 1.0
		out["items"].append({"kind": "mailbox", "pos": Vector3(float(h["road_x"]) + sx * MAILBOX_X, 0, door_z + along * StreetPlan.MAILBOX_ALONG),
				"yaw": 90.0 * sx, "scale": 1.0, "color": colors[i % colors.size()], "house": i})
		var back := BuildGrid.Side.EAST if h["east"] else BuildGrid.Side.WEST
		var cells := {}
		for c: Vector2i in h["cells"]:
			cells[c] = true
		var sorted: Array = (h["cells"] as Array).duplicate()
		sorted.sort()
		var spots: Array = []
		for c: Vector2i in sorted:
			if cells.has(c + Factory.DIRS[back]) or doors.has(BuildGrid.key_for_wall_edge(c, back)):
				continue
			var wall_x := (c.x + 1) * g if h["east"] else c.x * g
			spots.append(Vector3(wall_x + sx * TRASH_OUT, 0, (c.y + 0.5) * g + rng.randf_range(-0.4, 0.4)))
		if not spots.is_empty():
			out["items"].append({"kind": "trash_can", "pos": spots[rng.randi_range(0, spots.size() - 1)], "yaw": 0.0,
					"scale": 1.0, "id": "suburb_trash_%d" % trash, "house": i})
			trash += 1
		var wants_tree := rng.randf() < 0.5
		var sc: float = StreetPlan.TREE_SCALES[rng.randi_range(0, StreetPlan.TREE_SCALES.size() - 1)]
		var r := house_rect(h)
		var tz := rng.randf_range(r.position.y + 1.0, r.end.y - 1.0)
		if wants_tree:
			var back_x := r.end.x if h["east"] else r.position.x
			out["items"].append({"kind": "tree", "pos": Vector3(back_x + sx * (TREE_BACK + StreetPlan.TREE_CANOPY * sc), 0, tz),
					"yaw": rng.randf_range(0.0, 360.0), "scale": sc, "house": i})
