class_name CountryPlan
extends RefCounted
## W3a: the countryside round the town on the bigger map, seeded like TownPlan (the same seed, the same land):
## the woods (trees about WOODS_SPACING apart over WorldMap.AREAS["woods"], with clearings), trees dotted over
## the open fields, a belt of trees along the map's edge (the world ends in forest, not a cliff), and jams of
## wrecked cars on the highway. Everything keeps clear of the roads, the old town and park, and the areas the
## next phases fill (downtown, the new streets, the farms, the hunting cabin).
## generate(seed) -> {"trees": [{pos, scale, yaw, kind}], "props": [{kind, pos, yaw, scale}], "wrecks": [{type, pos, yaw, id, table}]}
## W3d: each wreck has a searchable trunk: "highway_wreck" loot on the highway, "car_trunk" in the junkyard.
## A tree's kind is "tree" (the town's leafy tree), "pine_tree" or "pine_tree_small"; props are rocks and bushes
## in the woods and fields, guardrails down both sides of the highway (open where Market Street joins it),
## concrete barriers across every road where it leaves the map, and a road sign at each junction.

const WOODS_SPACING := 8.0
const CLEARING_CHANCE := 0.18
const FIELD_TREES := 160
const EDGE_BELT := 30.0        # the map-edge tree belt's depth
const EDGE_SPACING := 6.0
const ROAD_CLEAR := 3.5        # metres kept free either side of a road
const SCALES := [0.8, 1.0, 1.2, 1.4]
const KEEP_CLEAR := ["town", "park", "downtown", "residential_west", "residential_east", "farm_west", "farm_south",
		"highway", "cabin", "junkyard"]
const NODE_CLEAR := 8.0  # F1: metres kept free round each resource node (its spot and its model)
const JAMS := [-410.0, -170.0, 150.0, 260.0]  # where wrecks pile up along the highway (z)
const WRECKS_PER_JAM := 3
const WRECK_TYPES := ["sedan", "pickup"]
const ROCKS := 90
const BUSHES := 180
const GUARDRAIL := 4.0       # one guardrail section's length
const JUNCTION_GAP := 14.0   # the guardrails stop this far either side of Market Street
const BARRIER_INSET := 8.0   # barriers stand this far inside the map's edge


static var _keep_out: Array = []  # F1: Vector2s with nothing grown within NODE_CLEAR (set by generate)


## `keep_out`: points (x, z) to keep clear (the resource nodes).
static func generate(seed_value: int, keep_out: Array = []) -> Dictionary:
	_keep_out = keep_out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "country"])
	var trees: Array = []
	var woods: Rect2 = WorldMap.AREAS["woods"]
	var x := woods.position.x + WOODS_SPACING / 2.0
	while x < woods.end.x:
		var z := woods.position.y + WOODS_SPACING / 2.0
		while z < woods.end.y:
			var p := Vector2(x + rng.randf_range(-3, 3), z + rng.randf_range(-3, 3))
			if rng.randf() >= CLEARING_CHANCE:
				_try(trees, p, rng, false)
			z += WOODS_SPACING
		x += WOODS_SPACING
	var tries := 0
	var field := 0
	while field < FIELD_TREES and tries < FIELD_TREES * 20:
		tries += 1
		var p := Vector2(rng.randf_range(WorldMap.EXTENT.position.x, WorldMap.EXTENT.end.x),
				rng.randf_range(WorldMap.EXTENT.position.y, WorldMap.EXTENT.end.y))
		if _try(trees, p, rng, false):
			field += 1
	for p: Vector2 in _edge_points(rng):
		_try(trees, p, rng, true)
	var props := _props(rng, trees)
	var wrecks := _wrecks(rng)
	var on_highway := wrecks.size()
	_junkyard(rng, props, wrecks)
	for i in wrecks.size():  # W3d: every wreck's trunk can be searched (SimWorld.place_country)
		wrecks[i]["id"] = "country_wreck_%d" % i
		wrecks[i]["table"] = "highway_wreck" if i < on_highway else "car_trunk"
	return {"trees": trees, "props": props, "wrecks": wrecks}


## Adds a tree at `p` unless something must stay clear there. Returns whether it did.
static func _try(trees: Array, p: Vector2, rng: RandomNumberGenerator, edge: bool) -> bool:
	if not WorldMap.EXTENT.has_point(p) or WorldMap.on_road(p, ROAD_CLEAR) or _near_node(p):
		return false
	for id: String in KEEP_CLEAR:
		if (WorldMap.AREAS[id] as Rect2).grow(4.0).has_point(p):
			return false
	if not edge and WorldMap.EXTENT.grow(-EDGE_BELT).has_point(p) == false:
		return false  # the belt is laid on its own
	var in_woods := (WorldMap.AREAS["woods"] as Rect2).has_point(p)
	var roll := rng.randf()
	var kind := "tree"
	if edge or (in_woods and roll < 0.8) or (not in_woods and roll < 0.3):
		kind = "pine_tree_small" if rng.randf() < 0.3 else "pine_tree"
	trees.append({"pos": Vector3(p.x, 0, p.y), "scale": float(SCALES[rng.randi_range(0, SCALES.size() - 1)]),
			"yaw": rng.randf_range(0, TAU), "kind": kind})
	return true


static func _edge_points(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var e := WorldMap.EXTENT
	var x := e.position.x + 4.0
	while x < e.end.x - 4.0:
		for z0: float in [e.position.y + 4.0, e.end.y - EDGE_BELT]:
			var z := z0
			while z < z0 + EDGE_BELT - 4.0:
				out.append(Vector2(x + rng.randf_range(-2.5, 2.5), z + rng.randf_range(-2.5, 2.5)))
				z += EDGE_SPACING
		x += EDGE_SPACING
	var z := e.position.y + EDGE_BELT
	while z < e.end.y - EDGE_BELT:
		for x0: float in [e.position.x + 4.0, e.end.x - EDGE_BELT]:
			var xx := x0
			while xx < x0 + EDGE_BELT - 4.0:
				out.append(Vector2(xx + rng.randf_range(-2.5, 2.5), z + rng.randf_range(-2.5, 2.5)))
				xx += EDGE_SPACING
		z += EDGE_SPACING
	return out


static func _props(rng: RandomNumberGenerator, trees: Array) -> Array:
	var out: Array = []
	var taken := {}  # 4 m cells with a tree in them, to keep rocks and bushes off trunks
	for t: Dictionary in trees:
		taken[Vector2i(floori(t["pos"].x / 4.0), floori(t["pos"].z / 4.0))] = true
	for want: Array in [["rock", ROCKS], ["bush", BUSHES]]:
		var placed := 0
		var tries := 0
		while placed < int(want[1]) and tries < int(want[1]) * 20:
			tries += 1
			var p := Vector2(rng.randf_range(WorldMap.EXTENT.position.x, WorldMap.EXTENT.end.x),
					rng.randf_range(WorldMap.EXTENT.position.y, WorldMap.EXTENT.end.y))
			if not _clear(p) or taken.has(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))):
				continue
			out.append({"kind": want[0], "pos": Vector3(p.x, 0, p.y), "yaw": rng.randf_range(0, TAU),
					"scale": rng.randf_range(0.7, 1.4)})
			placed += 1
	var hw: Dictionary = WorldMap.ROADS.filter(func(r: Dictionary) -> bool: return r["id"] == "highway")[0]
	var hx: float = (hw["points"][0] as Vector2).x
	var junction_z: float = (hw["points"][1] as Vector2).y
	var half: float = float(hw["width"]) / 2.0 + 0.6
	var z := WorldMap.EXTENT.position.y + BARRIER_INSET + 4.0
	while z < WorldMap.EXTENT.end.y - BARRIER_INSET - 4.0:
		if absf(z - junction_z) > JUNCTION_GAP:
			for side: float in [-1.0, 1.0]:
				out.append({"kind": "guardrail", "pos": Vector3(hx + side * half, 0, z), "yaw": PI / 2.0, "scale": 1.0})
		z += GUARDRAIL
	for road: Dictionary in WorldMap.ROADS:
		var pts: Array = road["points"]
		for end: int in [0, pts.size() - 1]:
			var at: Vector2 = pts[end]
			if WorldMap.EXTENT.grow(-1.0).has_point(at):
				continue  # not at the map's edge
			var inward: Vector2 = ((pts[1] if end == 0 else pts[end - 1]) as Vector2 - at).normalized()
			var across := Vector2(-inward.y, inward.x)
			var c := at + inward * BARRIER_INSET
			var n := ceili(float(road["width"]) / 2.0) + 1
			for k in range(-n / 2, n / 2 + 1):
				var bp := c + across * (k * 2.05)
				out.append({"kind": "concrete_barrier", "pos": Vector3(bp.x, 0, bp.y), "yaw": atan2(-across.y, across.x),
						"scale": 1.0})
	var g := WorldMap.graph()
	for n in (g["nodes"] as Array).size():
		if (g["adj"][n] as Array).size() >= 3:  # a junction
			var at: Vector2 = g["nodes"][n]
			var spot := at + Vector2(7.5, 7.5)
			if _clear(spot):
				out.append({"kind": "road_sign", "pos": Vector3(spot.x, 0, spot.y), "yaw": rng.randf_range(0, TAU), "scale": 1.0})
	return out


static func _near_node(p: Vector2) -> bool:
	for k: Vector2 in _keep_out:
		if k.distance_to(p) < NODE_CLEAR:
			return true
	return false


static func _clear(p: Vector2) -> bool:
	if not WorldMap.EXTENT.grow(-6.0).has_point(p) or WorldMap.on_road(p, ROAD_CLEAR) or _near_node(p):
		return false
	for id: String in KEEP_CLEAR:
		if (WorldMap.AREAS[id] as Rect2).grow(4.0).has_point(p):
			return false
	return true


## F1: the junkyard (WorldMap.AREAS["junkyard"]): a wooden fence round it, open where the lane comes in, and
## wrecked cars piled inside, clear of the scrap heaps' spots.
static func _junkyard(rng: RandomNumberGenerator, props: Array, wrecks: Array) -> void:
	var yard: Rect2 = WorldMap.AREAS["junkyard"]
	var gate_z := -40.0  # the junkyard lane comes in on the west side here
	var x := yard.position.x + 1.0
	while x < yard.end.x:
		for z: float in [yard.position.y, yard.end.y]:
			props.append({"kind": "farm_fence", "pos": Vector3(x, 0, z), "yaw": 0.0, "scale": 1.0})
		x += 2.0
	var z := yard.position.y + 1.0
	while z < yard.end.y:
		if absf(z - gate_z) > 4.0:
			props.append({"kind": "farm_fence", "pos": Vector3(yard.position.x, 0, z), "yaw": PI / 2.0, "scale": 1.0})
		props.append({"kind": "farm_fence", "pos": Vector3(yard.end.x, 0, z), "yaw": PI / 2.0, "scale": 1.0})
		z += 2.0
	var placed := 0
	var tries := 0
	while placed < 7 and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(yard.position.x + 5, yard.end.x - 5), rng.randf_range(yard.position.y + 5, yard.end.y - 5))
		if _near_node(p) or WorldMap.on_road(p, 3.0):
			continue
		var clash := false
		for w: Dictionary in wrecks:
			if Vector2(w["pos"].x, w["pos"].z).distance_to(p) < 6.0:
				clash = true
		if clash:
			continue
		wrecks.append({"type": WRECK_TYPES[rng.randi_range(0, WRECK_TYPES.size() - 1)], "pos": Vector3(p.x, 0, p.y),
				"yaw": rng.randf_range(0, TAU)})
		placed += 1


static func _wrecks(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var hw: Dictionary = WorldMap.ROADS.filter(func(r: Dictionary) -> bool: return r["id"] == "highway")[0]
	var x0: float = (hw["points"][0] as Vector2).x
	var half: float = float(hw["width"]) / 2.0 - 2.0
	for jz: float in JAMS:
		for i in WRECKS_PER_JAM:
			out.append({"type": WRECK_TYPES[rng.randi_range(0, WRECK_TYPES.size() - 1)],
					"pos": Vector3(x0 + rng.randf_range(-half, half), 0, jz + rng.randf_range(-12, 12)),
					"yaw": rng.randf_range(-0.7, 0.7) + (PI if rng.randf() < 0.5 else 0.0)})
	return out
