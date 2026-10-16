class_name WorldMap
extends RefCounted
## W3a (Emmitt: "it needs a much bigger world", town + countryside): the map's road network and its areas.
## Pure data, the same in every game: Main Street, the way round the factory hall and the park road keep their
## exact places (saves and the town are untouched), and new roads branch off them: Main Street runs on south
## to Market Street (downtown, W3b), West and East Street (more houses, W3c), County Road West and a farm lane
## (farms, W3d), a dirt track north-west from West Street through the woods (the hunting cabin), the north road past the park,
## and the highway down the east side (wrecks; where hordes come in).
## Zombies walk it: Director waves start out of sight along a road and follow route() to the noise, and road
## hordes keep to it. RoadView draws the new roads; nothing else in src/sim knows a road's shape.
##
## Coordinates: metres, x east, z south (north is -Z), as everywhere else.

const EXTENT := Rect2(-360, -460, 720, 760)  # x -360..360, z -460..300
const LEG := 40.0  # longest stretch between route waypoints (each leg gets the lure time to walk)
const SAMPLE := 10.0  # spacing of the points spawn_points() picks from

## Every road: an id, a kind ("asphalt", "dirt", "highway"), its width in metres, its points in order, and
## whether RoadView draws it (the three old roads are drawn by main.gd and ParkView as before). Two roads meet
## where they share a point exactly.
const ROADS := [
	{"id": "main_street", "kind": "asphalt", "width": 8.0, "drawn": false,
			"points": [Vector2(0, 10), Vector2(0, -106)]},
	{"id": "factory_way", "kind": "dirt", "width": 4.0, "drawn": false,
			"points": [Vector2(0, -106), Vector2(-25, -106), Vector2(-25, -142), Vector2(0, -142)]},
	{"id": "park_road", "kind": "asphalt", "width": 8.0, "drawn": false,
			"points": [Vector2(0, -142), Vector2(0, -258)]},
	{"id": "north_road", "kind": "asphalt", "width": 6.0, "drawn": true,
			"points": [Vector2(0, -258), Vector2(0, -460)]},
	{"id": "south_road", "kind": "asphalt", "width": 8.0, "drawn": true,
			"points": [Vector2(0, 10), Vector2(0, 60), Vector2(0, 300)]},
	{"id": "market_street", "kind": "asphalt", "width": 10.0, "drawn": true,
			"points": [Vector2(-170, 60), Vector2(-60, 60), Vector2(0, 60), Vector2(60, 60), Vector2(200, 60), Vector2(262, 60)]},
	{"id": "west_street", "kind": "asphalt", "width": 7.0, "drawn": true,
			"points": [Vector2(-60, 60), Vector2(-60, -106), Vector2(-25, -106)]},
	{"id": "east_street", "kind": "asphalt", "width": 7.0, "drawn": true,
			"points": [Vector2(60, 60), Vector2(60, -40), Vector2(60, -106), Vector2(0, -106)]},
	{"id": "junkyard_lane", "kind": "dirt", "width": 5.0, "drawn": true,  # F1: out to the junkyard's scrap heaps
			"points": [Vector2(60, -40), Vector2(140, -40)]},
	{"id": "county_west", "kind": "asphalt", "width": 6.0, "drawn": true,
			"points": [Vector2(-170, 60), Vector2(-256, 60), Vector2(-360, 60)]},
	# W3d: the farms' dirt drives (RuralPlan): off County Road West to the west farm, and on south from the
	# corner of West Street and Market Street to the south farm.
	{"id": "west_farm_drive", "kind": "dirt", "width": 5.0, "drawn": true,
			"points": [Vector2(-256, 60), Vector2(-256, 125)]},
	{"id": "south_farm_drive", "kind": "dirt", "width": 5.0, "drawn": true,
			"points": [Vector2(-60, 60), Vector2(-60, 170)]},
	{"id": "farm_lane", "kind": "dirt", "width": 5.0, "drawn": true,
			"points": [Vector2(-170, 60), Vector2(-170, 300)]},
	{"id": "woods_track", "kind": "dirt", "width": 4.0, "drawn": true,
			"points": [Vector2(-60, -106), Vector2(-95, -160), Vector2(-150, -225), Vector2(-200, -300), Vector2(-200, -460)]},
	{"id": "highway", "kind": "highway", "width": 16.0, "drawn": true,
			"points": [Vector2(262, -460), Vector2(262, 60), Vector2(262, 300)]},
]

## Where roads leave the map, by name (the way a wave "comes from").
const EXITS := {
	"north": Vector2(0, -460), "north-west": Vector2(-200, -460), "west": Vector2(-360, 60),
	"south": Vector2(0, 300), "south-west": Vector2(-170, 300),
	"highway north": Vector2(262, -460), "highway south": Vector2(262, 300),
}

## The areas later phases fill (rectangles in x/z).
const AREAS := {
	"town": Rect2(-25, -142, 50, 152),          # Main Street, the factory hall (as before)
	"park": Rect2(-36, -260, 72, 122),          # the industrial park (as before)
	"downtown": Rect2(10, 40, 185, 40),         # W3b: shops along Market Street east of Main Street
	"residential_west": Rect2(-95, -100, 70, 150),  # W3c
	"residential_east": Rect2(25, -100, 70, 150),   # W3c
	"farm_west": Rect2(-330, 80, 130, 120),     # W3d
	"farm_south": Rect2(-150, 140, 130, 120),   # W3d
	"woods": Rect2(-360, -460, 300, 260),       # W3d: dense trees round the track
	"cabin": Rect2(-245, -325, 38, 40),         # W3d: the hunting cabin, in a clearing west of the track
	"highway": Rect2(246, -460, 32, 760),
	"junkyard": Rect2(140, -70, 70, 60),        # F1: scrap heaps (resource nodes)
}

static var _graph: Dictionary = {}  # built once: {"nodes": [Vector2], "adj": [[ [node, length], ... ]]}


## The road graph: every road point is a node (shared points join roads); each road segment is an edge.
static func graph() -> Dictionary:
	if not _graph.is_empty():
		return _graph
	var nodes: Array = []
	var index := {}
	var adj: Array = []
	for road: Dictionary in ROADS:
		var prev := -1
		for p: Vector2 in road["points"]:
			var key := "%d,%d" % [roundi(p.x * 10.0), roundi(p.y * 10.0)]
			if not index.has(key):
				index[key] = nodes.size()
				nodes.append(p)
				adj.append([])
			var n: int = index[key]
			if prev >= 0 and prev != n:
				var length: float = (nodes[prev] as Vector2).distance_to(p)
				(adj[prev] as Array).append([n, length])
				(adj[n] as Array).append([prev, length])
			prev = n
	_graph = {"nodes": nodes, "adj": adj}
	return _graph


## The nearest point on any road to `at` (x/z), with the segment it lies on: {point, a, b, dist}.
static func nearest(at: Vector2) -> Dictionary:
	var g := graph()
	var best := {"dist": INF}
	for a in (g["nodes"] as Array).size():
		for e: Array in g["adj"][a]:
			var b: int = e[0]
			if b < a:
				continue
			var q := Geometry2D.get_closest_point_to_segment(at, g["nodes"][a], g["nodes"][b])
			var d := at.distance_to(q)
			if d < float(best["dist"]) - 1e-6:
				best = {"point": q, "a": a, "b": b, "dist": d}
	return best


## Whether `at` (x/z) is on a road's surface, `margin` metres either side counted too.
static func on_road(at: Vector2, margin: float = 0.0) -> bool:
	for road: Dictionary in ROADS:
		var pts: Array = road["points"]
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1])
			if at.distance_to(q) <= float(road["width"]) / 2.0 + margin:
				return true
	return false


## Road distances from the road point nearest `at` to every node, and the step back toward it from each:
## {"dist": [float], "next": [int], "start": nearest(at)}. next[n] is the neighbour one step closer (-1 at the
## two ends of the start segment, whose next step is the start point itself).
static func distances_from(at: Vector2) -> Dictionary:
	var g := graph()
	var count: int = (g["nodes"] as Array).size()
	var start := nearest(at)
	var dist: Array = []
	var next: Array = []
	dist.resize(count)
	next.resize(count)
	dist.fill(INF)
	next.fill(-1)
	var open: Array = []
	for end: int in [start["a"], start["b"]]:
		var d: float = (start["point"] as Vector2).distance_to(g["nodes"][end])
		if d < float(dist[end]):
			dist[end] = d
			open.append(end)
	while not open.is_empty():  # Dijkstra; the graph is a few dozen nodes, so a plain scan is plenty
		var best_i := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best_i]]):
				best_i = i
		var n: int = open[best_i]
		open.remove_at(best_i)
		for e: Array in g["adj"][n]:
			var m: int = e[0]
			var nd: float = float(dist[n]) + float(e[1])
			if nd < float(dist[m]) - 1e-6:
				dist[m] = nd
				next[m] = n
				if not open.has(m):
					open.append(m)
	return {"dist": dist, "next": next, "start": start}


## The way along the roads from `from` to the road point nearest `to`, as waypoints (Vector3, y = 0) at most
## LEG apart, starting at the road point nearest `from`. Walk it, then turn off the road to `to` itself.
static func route(from: Vector3, to: Vector3) -> Array:
	var g := graph()
	var field := distances_from(Vector2(to.x, to.z))
	var target: Vector2 = field["start"]["point"]
	var here := nearest(Vector2(from.x, from.z))
	var path: Array = [here["point"]]
	var a: int = here["a"]
	var b: int = here["b"]
	var same_segment := (a == int(field["start"]["a"]) and b == int(field["start"]["b"])) \
			or (a == int(field["start"]["b"]) and b == int(field["start"]["a"]))
	if not same_segment:
		var da: float = (here["point"] as Vector2).distance_to(g["nodes"][a]) + float(field["dist"][a])
		var db: float = (here["point"] as Vector2).distance_to(g["nodes"][b]) + float(field["dist"][b])
		var n: int = a if da <= db else b
		var guard := 0
		while n >= 0 and guard < 200:
			path.append(g["nodes"][n])
			n = field["next"][n]
			guard += 1
	path.append(target)
	return _legs(path)


static func _legs(path: Array) -> Array:
	var out: Array = []
	for i in path.size():
		var p: Vector2 = path[i]
		if i > 0:
			var from: Vector2 = path[i - 1]
			var legs := maxi(1, ceili(from.distance_to(p) / LEG))
			for k in range(1, legs):
				var mid := from.lerp(p, float(k) / legs)
				out.append(Vector3(mid.x, 0, mid.y))
		var v := Vector3(p.x, 0, p.y)
		if out.is_empty() or v.distance_to(out.back()) > 3.0:
			out.append(v)
	return out


## Points on the roads (every SAMPLE metres) whose road distance from the road point nearest `at` is between
## `min_d` and `max_d`: where a wave can start out of sight and still arrive soon. Each is {pos: Vector3, dist}.
static func spawn_points(at: Vector3, min_d: float, max_d: float) -> Array:
	var g := graph()
	var field := distances_from(Vector2(at.x, at.z))
	var out: Array = []
	for a in (g["nodes"] as Array).size():
		for e: Array in g["adj"][a]:
			var b: int = e[0]
			if b < a:
				continue
			var pa: Vector2 = g["nodes"][a]
			var pb: Vector2 = g["nodes"][b]
			var length: float = e[1]
			var steps := maxi(1, floori(length / SAMPLE))
			for k in steps + 1:
				var t := float(k) / steps
				var d := minf(float(field["dist"][a]) + t * length, float(field["dist"][b]) + (1.0 - t) * length)
				if d >= min_d and d <= max_d:
					var p := pa.lerp(pb, t)
					out.append({"pos": Vector3(p.x, 0, p.y), "dist": d})
	return out


## W3e: zombies wandering the roads between the places, so a trip across the map isn't empty: `count` spots
## beside the roads (2.5-4.5 m off the edge), out in the open (no area but the woods or the highway), at least
## ROADSIDE_FROM_START from where a new game starts and ROADSIDE_APART from each other; one is a runner. Seeded.
## [{type, pos, facing}] for SimWorld.spawn_park_zombies.
const ROADSIDE_FROM_START := 120.0
const ROADSIDE_APART := 40.0


static func roadside_zombies(seed_value: int, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "roadside"])
	var spots: Array = []
	for pt: Dictionary in spawn_points(Vector3.ZERO, ROADSIDE_FROM_START, INF):
		var at: Vector3 = pt["pos"]
		if area_at(at) in ["", "woods", "highway"] and EXTENT.grow(-20.0).has_point(Vector2(at.x, at.z)):
			spots.append(at)
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < 400 and not spots.is_empty():
		tries += 1
		var at: Vector3 = spots[rng.randi_range(0, spots.size() - 1)]
		var near: Dictionary = nearest(Vector2(at.x, at.z))
		var g := graph()
		var road: Vector2 = (g["nodes"][near["b"]] as Vector2) - (g["nodes"][near["a"]] as Vector2)
		var side := Vector2(-road.y, road.x).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
		var off := side * (_width_at(Vector2(at.x, at.z)) / 2.0 + rng.randf_range(2.5, 4.5))
		var p := Vector3(at.x + off.x, 0.0, at.z + off.y)
		var crowded := false
		for o: Dictionary in out:
			crowded = crowded or (o["pos"] as Vector3).distance_to(p) < ROADSIDE_APART
		if crowded or on_road(Vector2(p.x, p.z), 1.0) or Vector2(p.x, p.z).length() < ROADSIDE_FROM_START \
				or not area_at(p) in ["", "woods", "highway"]:
			continue
		out.append({"type": "shambler", "pos": p, "facing": Vector3(-side.x, 0, -side.y)})
	if not out.is_empty():
		out[rng.randi_range(0, out.size() - 1)]["type"] = "runner"
	return out


## The width of the road nearest to `at` (m).
static func _width_at(at: Vector2) -> float:
	var best := INF
	var width := 6.0
	for road: Dictionary in ROADS:
		var pts: Array = road["points"]
		for i in pts.size() - 1:
			var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1]))
			if d < best:
				best = d
				width = float(road["width"])
	return width


## The compass word for the way from `from` to `to` ("north", "south-east", ...), for messages.
static func direction_name(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 1.0:
		return "nearby"
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var angle := atan2(d.x, -d.y)  # 0 = north (-Z), clockwise
	return names[posmod(roundi(angle / (TAU / 8.0)), 8)]


## The area `at` is in ("" for open country).
static func area_at(at: Vector3) -> String:
	var best := ""
	var best_size := INF
	for id: String in AREAS:  # W3e: the smallest area holding the spot (the cabin's clearing is in the woods)
		var r: Rect2 = AREAS[id]
		if r.has_point(Vector2(at.x, at.z)) and r.get_area() < best_size:
			best = id
			best_size = r.get_area()
	return best
