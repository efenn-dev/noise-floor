extends "res://test/base_test.gd"
## F1 (Emmitt: building "more like Satisfactory"): resource nodes on the map that only a machine can work. An
## extractor goes on its kind's yellow spot (no foundation), makes its resource with no input, at the node's
## purity, and is as loud as a machine should be.

const TICK := SimWorld.TICK


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 3, "normal")
	sim.power.free = true
	return sim


func _node(sim: SimWorld, kind: String, purity: String = "") -> Dictionary:
	for n: Dictionary in sim.resource_nodes:
		if n["kind"] == kind and (purity == "" or n["purity"] == purity):
			return n
	return {}


func test_the_data_and_the_nodes() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "resources.json and the extractors check out")
	var sim := _sim()
	eq(sim.resource_nodes.size(), (data.resources["nodes"] as Array).size(), "every node from the data is on the map")
	var kinds := {}
	for n: Dictionary in sim.resource_nodes:
		kinds[n["kind"]] = true
		eq(sim.build.nodes.get(n["cell"], ""), n["kind"], "%s: its spot is marked in the build grid" % n["id"])
		eq(sim.node_at(n["cell"])["id"], n["id"], "%s: found by its cell" % n["id"])
		check(WorldMap.EXTENT.has_point(Vector2(n["pos"].x, n["pos"].z)), "%s is on the map" % n["id"])
		check(not WorldMap.on_road(Vector2(n["pos"].x, n["pos"].z), 1.0), "%s: its spot is off the road" % n["id"])
		check(not WorldMap.on_road(Vector2(n["prop_pos"].x, n["prop_pos"].z), 1.5), "%s: its model is off the road" % n["id"])
		check(WorldMap.area_at(n["pos"]) not in ["town", "park"], "%s: out in the new world" % n["id"])
	for kind: String in ["scrap_heap", "well", "fuel_tank", "timber"]:
		check(kinds.has(kind), "there is a %s to work" % kind)
	check(not _node(sim, "scrap_heap", "rich").is_empty() and not _node(sim, "scrap_heap", "poor").is_empty(),
			"some nodes are rich, some poor")


func test_an_extractor_goes_only_on_its_spot_and_needs_no_foundation() -> void:
	var sim := _sim()
	var heap := _node(sim, "scrap_heap")
	var inv := Inventory.new()
	inv.give_all({"metal_plate": 100, "nails": 100, "scrap_metal": 100, "plank": 100})
	var off := (heap["cell"] as Vector2i) + Vector2i(3, 0)
	check(sim.build.can_place("salvager", off, BuildGrid.Side.NORTH, inv).begins_with("Build it on a scrap heap"),
			"off the spot: it says where it goes")
	var well := _node(sim, "well")
	check(sim.build.can_place("salvager", well["cell"], BuildGrid.Side.NORTH, inv) != "", "not on a different kind of node")
	eq(sim.build.can_place("salvager", heap["cell"], BuildGrid.Side.NORTH, inv), "", "on its spot, with no foundation")
	eq(sim.build.place("salvager", heap["cell"], BuildGrid.Side.NORTH, inv), "", "built")
	var centre := sim.build.piece_center("o:%d:%d" % [heap["cell"].x, heap["cell"].y]) if sim.build.pieces.has("o:%d:%d" % [heap["cell"].x, heap["cell"].y]) else Vector3.ZERO
	if centre != Vector3.ZERO:
		near(centre.y, float(sim.data.buildables["salvager"]["size"][1]) / 2.0, "standing on the ground, not on a missing foundation", 0.01)
	check(sim.build.can_place("smelter", heap["cell"] + Vector2i(0, 4), BuildGrid.Side.NORTH, inv) == "Needs a foundation",
			"ordinary machines still need a foundation")


func test_extractors_make_their_resource_at_the_nodes_purity() -> void:
	var sim := _sim()
	var made := {}
	for pair: Array in [["scrap_heap", "salvager", "scrap_metal"], ["well", "water_pump", "dirty_water"],
			["fuel_tank", "fuel_pump", "gas_can"], ["timber", "sawmill", "plank"]]:
		var n := _node(sim, pair[0])
		var inv := Inventory.new()
		inv.give_all({"metal_plate": 100, "nails": 100, "scrap_metal": 100})
		eq(sim.build.place(pair[1], n["cell"], BuildGrid.Side.NORTH, inv), "", "a %s on a %s" % [pair[1], pair[0]])
		var m: Factory.Machine = sim.factory.machines.get(n["cell"])
		check(m != null, "%s runs as a machine" % pair[1])
		if m != null:
			near(m.node_rate, float(n["rate"]), "%s works at the node's purity" % pair[1])
			made[pair[1]] = [m, pair[2], n]
	for i in roundi(100.0 / TICK):
		sim.step()
	for ex: String in made:
		var m: Factory.Machine = made[ex][0]
		var item: String = made[ex][1]
		check(int(m.output.get(item, 0)) > 0, "%s made %s with nothing put in (%d)" % [ex, item, int(m.output.get(item, 0))])
	# A rich node runs twice as fast as a normal one.
	var rich := _node(sim, "scrap_heap", "rich")
	var normal := _node(sim, "scrap_heap", "normal")
	var fast: Factory.Machine = sim.factory.add_machine("salvager", rich["cell"] + Vector2i(40, 40), 0)
	fast.node_rate = float(rich["rate"])
	var slow: Factory.Machine = sim.factory.add_machine("salvager", normal["cell"] + Vector2i(40, 40), 0)
	slow.node_rate = float(normal["rate"])
	near(fast.craft_time() * 2.0, slow.craft_time(), "rich: twice the speed of normal", 0.01)


func test_extractors_are_loud() -> void:
	var data := GameData.load_default()
	for ex: String in ["salvager", "sawmill"]:
		check(float(data.buildables[ex]["loudness"]) >= 70.0, "%s is loud (%d): an outpost draws zombies" % [ex, data.buildables[ex]["loudness"]])


func test_nothing_grows_on_a_node() -> void:
	var sim := _sim()
	var keep: Array = []
	for n: Dictionary in sim.resource_nodes:
		keep.append(Vector2(n["pos"].x, n["pos"].z))
		keep.append(Vector2(n["prop_pos"].x, n["prop_pos"].z))
	var plan := CountryPlan.generate(1, keep)
	var bad := 0
	for t: Dictionary in plan["trees"]:
		for k: Vector2 in keep:
			if Vector2(t["pos"].x, t["pos"].z).distance_to(k) < CountryPlan.NODE_CLEAR - 0.01:
				bad += 1
	eq(bad, 0, "no tree stands on a resource node or its model")
