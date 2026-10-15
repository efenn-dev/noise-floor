extends "res://test/base_test.gd"
## W3a (Emmitt: "it needs a much bigger world"): the bigger map's road network (WorldMap). The old roads keep
## their places; the new ones branch off them, stay on the map, reach every exit, and run clear of the town's
## houses, the factory hall and the industrial park.


func test_the_map_is_much_bigger() -> void:
	var area := WorldMap.EXTENT.size.x * WorldMap.EXTENT.size.y
	var old := 70.0 * 270.0  # one street, the hall and the park
	check(area / old > 15.0, "the map is %.0fx the old one" % (area / old))


func test_every_road_is_on_the_map_and_joined_up() -> void:
	var g := WorldMap.graph()
	var nodes: Array = g["nodes"]
	for n: Vector2 in nodes:
		check(WorldMap.EXTENT.grow(0.01).has_point(n), "road point %s is on the map" % n)
	var seen := {0: true}
	var todo: Array = [0]
	while not todo.is_empty():
		var n: int = todo.pop_back()
		for e: Array in g["adj"][n]:
			if not seen.has(e[0]):
				seen[e[0]] = true
				todo.append(e[0])
	eq(seen.size(), nodes.size(), "every road joins the network")
	for name: String in WorldMap.EXITS:
		var exit: Vector2 = WorldMap.EXITS[name]
		check(nodes.has(exit), "the %s exit is a road end" % name)
		var on_edge := is_equal_approx(exit.x, WorldMap.EXTENT.position.x) or is_equal_approx(exit.x, WorldMap.EXTENT.end.x) \
				or is_equal_approx(exit.y, WorldMap.EXTENT.position.y) or is_equal_approx(exit.y, WorldMap.EXTENT.end.y)
		check(on_edge, "the %s exit is at the map's edge" % name)


func test_the_old_roads_keep_their_places() -> void:
	var main_street: Dictionary = WorldMap.ROADS.filter(func(r: Dictionary) -> bool: return r["id"] == "main_street")[0]
	eq(main_street["points"], [Vector2(0, 10), Vector2(0, -106)], "Main Street where it was")
	check(not main_street["drawn"], "and still drawn by the town, as before")
	var park: Dictionary = WorldMap.ROADS.filter(func(r: Dictionary) -> bool: return r["id"] == "park_road")[0]
	eq(park["points"][1], Vector2(0, ParkPlan.ROAD_NORTH_Z), "the park road ends where it did")


func test_new_roads_run_clear_of_houses_the_hall_and_the_park() -> void:
	var town := TownPlan.generate(1)
	var blocked: Array = []  # Rect2s
	for house: Dictionary in town["houses"]:
		for c: Vector2i in house["cells"]:
			blocked.append(Rect2(c.x * 2.0, c.y * 2.0, 2.0, 2.0))
	blocked.append(TownPlan.factory_rect())
	var park := ParkPlan.area()
	var bad: Array = []
	for road: Dictionary in WorldMap.ROADS:
		if not road["drawn"]:
			continue
		var pts: Array = road["points"]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var steps := ceili(a.distance_to(b) / 1.0)
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				var half := float(road["width"]) / 2.0
				var foot := Rect2(p - Vector2(half, half), Vector2(2.0 * half, 2.0 * half))
				for r: Rect2 in blocked:
					if r.intersects(foot):
						bad.append("%s at %s" % [road["id"], p])
				# the north road leaves from the park road's end, through the gap in the north fence
				if park.intersects(foot) and not (road["id"] == "north_road" and absf(p.x) < 0.01):
					bad.append("%s crosses the park at %s" % [road["id"], p])
	check(bad.is_empty(), "no new road runs through a house, the hall or the park %s" % [bad.slice(0, 3)])


func test_routes_and_spawn_points() -> void:
	var lure := Vector3(21, 1, -49)
	var points := WorldMap.spawn_points(lure, 110.0, 180.0)
	check(points.size() > 20, "plenty of places a wave can start (%d)" % points.size())
	for p: Dictionary in points:
		check(float(p["dist"]) >= 110.0 and float(p["dist"]) <= 180.0, "each at the right road distance")
		check(WorldMap.on_road(Vector2(p["pos"].x, p["pos"].z), 0.05), "and on a road")
	eq(WorldMap.direction_name(Vector3.ZERO, Vector3(0, 0, -50)), "north", "north is -Z")
	eq(WorldMap.direction_name(Vector3.ZERO, Vector3(50, 0, 50)), "south-east", "and so on round")
	eq(WorldMap.area_at(Vector3(100, 0, 60)), "downtown", "Market Street east of Main Street is downtown")
	eq(WorldMap.area_at(Vector3(0, 0, -50)), "town", "Main Street is the old town")
