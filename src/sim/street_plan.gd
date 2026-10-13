class_name StreetPlan
extends RefCounted
## A1: where the street's scenery stands. Pure and seeded, like TownPlan: generate(seed, town) gives
##   {"items": [{kind, pos, yaw, scale, color, id, house}], "markings": {dashes, dash_size, kerbs, kerb_height}}
## Kinds: "lamp_post" (on the strip beside the road, between every second lot on each side; lit at night by
## StreetView, no rule), "mailbox" (one per house by the road near its front door, its own colour), "fence"
## (2 m picket sections along the side boundary between neighbouring lots, from the house fronts back, with
## FENCE_GAP open at the back), "trash_can" (one or two behind each house, searchable: SimWorld.place_street
## registers them as "trash" containers) and "tree" (one behind most houses, a few at the road's two ends).
## `pos` is on the ground (y = 0), `yaw` in degrees (models face -Z at 0). Everything has a box collider
## COLLIDERS[kind] * scale (a tree's is its trunk), so the player and the navmesh go round it.
## Nothing stands on the road, on a house (or the factory), within DOOR_CLEAR of a door's cell or the cell
## outside it, or on the path from the road to a front door; test_street_plan.gd checks all of that, plus that
## the Director's road route stays clear. Road markings are drawn only (no colliders).

const ROAD_HALF := 4.0           # the asphalt is 8 m wide, x -4..4 (main.gd)
const ROAD_SOUTH := 10.0         # the asphalt's south end (z)
const ROAD_NORTH := -114.0       # the factory hall's south wall (z)
const FRONT_X := 8.0             # house fronts (TownPlan.EAST_FIRST_CELL cells from the road's middle)
const LAMP_X := 4.8              # lamp posts, just off the road's edge
const MAILBOX_X := 5.3
const MAILBOX_ALONG := 2.8       # a mailbox stands this far along the road from its front door's middle
const FENCE_LENGTH := 2.0        # one picket_fence model section
const FENCE_SECTIONS := 6        # from FRONT_X back to FENCE_END
const FENCE_END := FRONT_X + FENCE_SECTIONS * FENCE_LENGTH  # 20 m
const LOT_BACK := 22.0           # how far back from the road a lot runs
const FENCE_GAP := LOT_BACK - FENCE_END  # 2 m open at the back of every fence line
const DOOR_CLEAR := 1.5          # nothing within this of a door's cell or the cell outside it
const HOUSE_CLEAR := 0.4         # gap kept from a house's walls (the roof overhangs 0.35 m)
const TREE_SCALES := [0.75, 1.0, 1.25]
const TREE_CANOPY := 1.5         # canopy half-width at scale 1 (tools/art/tree.py); kept off the houses
## Trees at the two ends of the road (x, z): south past the spawn, north beside the factory but off the
## Director's road route (the north corner (-25, -106), then along z = -106 to the road).
const END_TREES := [Vector2(-7.5, 14.0), Vector2(8.5, 16.0), Vector2(-12.0, 20.0), Vector2(5.5, 24.0),
		Vector2(11.0, -103.0), Vector2(16.0, -108.0), Vector2(-13.0, -99.0)]
## The model's box (tools/art/<kind>.py finish() size, Godot order w, h, d) and the collider in the game.
const MODELS := {"lamp_post": "lamp_post", "mailbox": "mailbox", "fence": "picket_fence", "trash_can": "trash_can",
		"tree": "tree"}
const SIZES := {"lamp_post": Vector3(0.4, 4.1, 0.4), "mailbox": Vector3(0.3, 1.35, 0.55),
		"fence": Vector3(2.0, 0.95, 0.12), "trash_can": Vector3(0.66, 1.05, 0.66), "tree": Vector3(3.4, 5.0, 3.4)}
const COLLIDERS := {"lamp_post": Vector3(0.3, 4.1, 0.3), "mailbox": Vector3(0.3, 1.35, 0.55),
		"fence": Vector3(2.0, 0.95, 0.12), "trash_can": Vector3(0.62, 1.05, 0.62), "tree": Vector3(0.55, 2.6, 0.55)}
const LAMP_HEIGHT := 3.57        # the lantern's middle above the ground
## Twelve mailbox colours, shuffled over the houses by the seed, so no two houses share one.
const MAILBOX_COLORS := [Color(0.55, 0.08, 0.06), Color(0.08, 0.22, 0.45), Color(0.12, 0.35, 0.14), Color(0.75, 0.62, 0.12),
		Color(0.85, 0.85, 0.82), Color(0.08, 0.08, 0.09), Color(0.45, 0.25, 0.10), Color(0.35, 0.12, 0.40),
		Color(0.70, 0.35, 0.08), Color(0.25, 0.55, 0.60), Color(0.50, 0.50, 0.52), Color(0.60, 0.30, 0.35)]
const DASH := Vector3(0.15, 0.01, 3.0)  # centre line dashes, every DASH_EVERY metres
const DASH_EVERY := 6.0
const KERB := Vector2(0.25, 0.12)       # kerb width and height, along both road edges


static func generate(seed_value: int, town: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "street"])
	var out := {"items": [], "markings": markings()}
	var blocked := _blocked(town)
	var sides := _houses_by_side(town)
	_add_lamps(out, sides)
	_add_mailboxes(out, town, rng, blocked)
	_add_fences(out, sides)
	_add_trash(out, town, rng, blocked)
	_add_trees(out, town, sides, rng, blocked)
	return out


## The road's dashed centre line and its two kerbs: drawn by StreetView, no colliders, no rules.
static func markings() -> Dictionary:
	var dashes: Array = []
	var z := ROAD_SOUTH - 4.0
	while z > ROAD_NORTH + 6.0:
		dashes.append(Vector3(0.0, 0.0, z))
		z -= DASH_EVERY
	var kerbs: Array = []
	for sx: float in [-1.0, 1.0]:
		kerbs.append(Rect2(sx * ROAD_HALF - KERB.x / 2.0, ROAD_NORTH, KERB.x, ROAD_SOUTH - ROAD_NORTH))
	return {"dashes": dashes, "dash_size": DASH, "kerbs": kerbs, "kerb_height": KERB.y}


## An item's collider footprint on the ground (x, z), allowing for a quarter-turned yaw.
static func footprint(item: Dictionary) -> Rect2:
	var size: Vector3 = COLLIDERS[item["kind"]] * float(item.get("scale", 1.0))
	var turned := absf(fposmod(float(item["yaw"]), 180.0) - 90.0) < 1.0
	var w := size.z if turned else size.x
	var d := size.x if turned else size.z
	var p: Vector3 = item["pos"]
	return Rect2(p.x - w / 2.0, p.z - d / 2.0, w, d)


static func road_rect() -> Rect2:
	return Rect2(-ROAD_HALF, ROAD_NORTH, ROAD_HALF * 2.0, ROAD_SOUTH - ROAD_NORTH)


## Each house's cells as one rectangle per cell (plan C is an L, so not one box per house).
static func house_rects(town: Dictionary) -> Array:
	var out: Array = []
	for h: Dictionary in town["houses"]:
		for c: Vector2i in h["cells"]:
			out.append(_cell_rect(c))
	return out


## For every door in the town (front and back): its cell and the cell outside it.
static func door_zones(town: Dictionary) -> Array:
	var doors := {}
	for p: Dictionary in town["pieces"]:
		if p["id"] == "door":
			doors[TownPlan.piece_key(p)] = true
	var out: Array = []
	for h: Dictionary in town["houses"]:
		for c: Vector2i in h["cells"]:
			for side in 4:
				if doors.has(BuildGrid.key_for_wall_edge(c, side)):
					out.append(_cell_rect(c))
					out.append(_cell_rect(c + _step(side)))
	return out


## The strip from the road's edge to each front door, as wide as the door's cell.
static func door_paths(town: Dictionary) -> Array:
	var out: Array = []
	for h: Dictionary in town["houses"]:
		var c: Vector2i = h["door_cell"]
		var z0 := c.y * BuildGrid.GRID
		if h["east"]:
			out.append(Rect2(ROAD_HALF, z0, FRONT_X - ROAD_HALF, BuildGrid.GRID))
		else:
			out.append(Rect2(-FRONT_X, z0, FRONT_X - ROAD_HALF, BuildGrid.GRID))
	return out


## The gap between two rectangles (0 if they touch or overlap).
static func gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dz := maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return Vector2(dx, dz).length()


## True if `rect` is clear of the road, the houses, the factory, the doors and their paths, and other items.
static func is_clear(rect: Rect2, blocked: Dictionary, items: Array, house_rect := Rect2()) -> bool:
	if rect.intersects(road_rect()) or rect.intersects(blocked["factory"]):
		return false
	var check_house := house_rect if house_rect.has_area() else rect
	for r: Rect2 in blocked["houses"]:
		if gap(check_house, r) < HOUSE_CLEAR:
			return false
	for r: Rect2 in blocked["doors"]:
		if gap(rect, r) < DOOR_CLEAR:
			return false
	for r: Rect2 in blocked["paths"]:
		if rect.intersects(r):
			return false
	for it: Dictionary in items:
		if gap(rect, footprint(it)) < 0.3:
			return false
	return true


static func _blocked(town: Dictionary) -> Dictionary:
	return {"houses": house_rects(town), "doors": door_zones(town), "paths": door_paths(town),
			"factory": TownPlan.factory_rect()}


## West and east houses, each list ordered from lot 0 (south) to lot 5 (north), as [house index, rect].
static func _houses_by_side(town: Dictionary) -> Dictionary:
	var out := {"w": [], "e": []}
	for i in town["houses"].size():
		var h: Dictionary = town["houses"][i]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c: Vector2i in h["cells"]:
			var r := _cell_rect(c)
			lo = Vector2(minf(lo.x, r.position.x), minf(lo.y, r.position.y))
			hi = Vector2(maxf(hi.x, r.end.x), maxf(hi.y, r.end.y))
		out["e" if h["east"] else "w"].append([i, Rect2(lo, hi - lo)])
	for k: String in out:
		out[k].sort_custom(func(a: Array, b: Array) -> bool: return a[1].position.y > b[1].position.y)
	return out


## The z between lot n's house and lot n + 1's on one side (n = -1: just south of lot 0).
static func _boundary(side: Array, n: int) -> float:
	if n < 0:
		return side[0][1].end.y + (TownPlan.LOT_SPACING - side[0][1].size.y) / 2.0
	return (side[n][1].position.y + side[n + 1][1].end.y) / 2.0


static func _add_lamps(out: Dictionary, sides: Dictionary) -> void:
	# Staggered: west after lots 0, 2 and 4; east south of lot 0 and after lots 1 and 3.
	for n: int in [0, 2, 4]:
		out["items"].append({"kind": "lamp_post", "pos": Vector3(-LAMP_X, 0, _boundary(sides["w"], n)), "yaw": 0.0, "scale": 1.0})
	for n: int in [-1, 1, 3]:
		out["items"].append({"kind": "lamp_post", "pos": Vector3(LAMP_X, 0, _boundary(sides["e"], n)), "yaw": 0.0, "scale": 1.0})


static func _add_mailboxes(out: Dictionary, town: Dictionary, rng: RandomNumberGenerator, blocked: Dictionary) -> void:
	var colors: Array = MAILBOX_COLORS.duplicate()
	for i in range(colors.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Color = colors[i]
		colors[i] = colors[j]
		colors[j] = t
	for i in town["houses"].size():
		var h: Dictionary = town["houses"][i]
		var sx := 1.0 if h["east"] else -1.0
		var door_z: float = (h["door_cell"].y + 0.5) * BuildGrid.GRID
		var first := -1.0 if rng.randf() < 0.5 else 1.0
		for along: float in [first, -first]:
			var item := {"kind": "mailbox", "pos": Vector3(sx * MAILBOX_X, 0, door_z + along * MAILBOX_ALONG),
					"yaw": 90.0 * sx, "scale": 1.0, "color": colors[i % colors.size()], "house": i}
			if is_clear(footprint(item), blocked, out["items"]):
				out["items"].append(item)
				break


static func _add_fences(out: Dictionary, sides: Dictionary) -> void:
	for k: String in ["w", "e"]:
		var sx := 1.0 if k == "e" else -1.0
		for n in sides[k].size() - 1:
			var z := _boundary(sides[k], n)
			for s in FENCE_SECTIONS:
				var x := sx * (FRONT_X + FENCE_LENGTH * (s + 0.5))
				out["items"].append({"kind": "fence", "pos": Vector3(x, 0, z), "yaw": 0.0, "scale": 1.0,
						"house": sides[k][n][0]})


## One or two cans behind each house, a little out from its back wall, clear of the back door.
static func _add_trash(out: Dictionary, town: Dictionary, rng: RandomNumberGenerator, blocked: Dictionary) -> void:
	var n := 0
	for i in town["houses"].size():
		var h: Dictionary = town["houses"][i]
		var back := BuildGrid.Side.EAST if h["east"] else BuildGrid.Side.WEST
		var cells := {}
		for c: Vector2i in h["cells"]:
			cells[c] = true
		var spots: Array = []
		var sorted_cells: Array = h["cells"].duplicate()
		sorted_cells.sort()
		for c: Vector2i in sorted_cells:
			if cells.has(c + _step(back)):
				continue
			var wall_x := (c.x + 1) * BuildGrid.GRID if h["east"] else c.x * BuildGrid.GRID
			var sx := 1.0 if h["east"] else -1.0
			spots.append(Vector3(wall_x + sx * 0.85, 0, (c.y + 0.5) * BuildGrid.GRID + rng.randf_range(-0.4, 0.4)))
		for j in range(spots.size() - 1, 0, -1):
			var r := rng.randi_range(0, j)
			var t: Vector3 = spots[j]
			spots[j] = spots[r]
			spots[r] = t
		var want := 1 if rng.randf() < 0.5 else 2
		for p: Vector3 in spots:
			if want == 0:
				break
			var item := {"kind": "trash_can", "pos": p, "yaw": 0.0, "scale": 1.0, "id": "trash_%d" % n, "house": i}
			if is_clear(footprint(item), blocked, out["items"]):
				out["items"].append(item)
				n += 1
				want -= 1


## One tree behind most houses (a few tries each), then the trees at the ends of the road.
static func _add_trees(out: Dictionary, town: Dictionary, sides: Dictionary, rng: RandomNumberGenerator,
		blocked: Dictionary) -> void:
	for k: String in ["w", "e"]:
		var sx := 1.0 if k == "e" else -1.0
		for entry: Array in sides[k]:
			var rect: Rect2 = entry[1]
			var scale: float = TREE_SCALES[rng.randi_range(0, TREE_SCALES.size() - 1)]
			for attempt in 6:
				var pos := Vector3(sx * rng.randf_range(18.6, 21.0), 0, rect.get_center().y + rng.randf_range(-3.5, 3.5))
				var item := {"kind": "tree", "pos": pos, "yaw": 90.0 * rng.randi_range(0, 3), "scale": scale, "house": entry[0]}
				if _tree_clear(item, blocked, out["items"], sides):
					out["items"].append(item)
					break
	for p: Vector2 in END_TREES:
		var item := {"kind": "tree", "pos": Vector3(p.x, 0, p.y), "yaw": 0.0,
				"scale": TREE_SCALES[rng.randi_range(0, TREE_SCALES.size() - 1)]}
		if _tree_clear(item, blocked, out["items"], sides):
			out["items"].append(item)


## A tree's trunk must be clear like anything else, its canopy must stay off the roofs, and the trunk keeps
## 2 m from the fence lines so the gap at the back of each fence stays open.
static func _tree_clear(item: Dictionary, blocked: Dictionary, items: Array, sides: Dictionary) -> bool:
	var half := TREE_CANOPY * float(item["scale"])
	var p: Vector3 = item["pos"]
	var canopy := Rect2(p.x - half, p.z - half, half * 2.0, half * 2.0)
	if not is_clear(footprint(item), blocked, items, canopy):
		return false
	for it: Dictionary in items:
		if it["kind"] == "fence" and absf(it["pos"].z - p.z) < 2.0 and signf(it["pos"].x) == signf(p.x):
			return false
	return true


static func _cell_rect(c: Vector2i) -> Rect2:
	var g := BuildGrid.GRID
	return Rect2(c.x * g, c.y * g, g, g)


static func _step(side: int) -> Vector2i:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][side]
