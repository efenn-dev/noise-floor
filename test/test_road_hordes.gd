extends "res://test/base_test.gd"
## W1b: groups and hordes come down the road. They spawn at the north or south road end, walk the road
## to the road point nearest the noise, then turn toward it. Wanderers still come straight from any edge.

const TICK := SimWorld.TICK
const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## A working smelter east of the road at cell (10, -25): centre (21, -49).
func _smelter_east(hour: float, seed_value: int) -> SimWorld:
	var sim := SimWorld.new(hour, null, seed_value)
	sim.director.first_night_warning_sent = true  # V29: these are about heat-driven road hordes, not the first-night wave
	sim.director.first_night_wave_sent = true
	sim.power.free = true
	sim.give_debug_kit()
	sim.inventory.add("plank", 50)
	sim.build.place("foundation", Vector2i(10, -25), N, sim.inventory)
	sim.build.place("smelter", Vector2i(10, -25), E, sim.inventory)
	sim.factory.machines[Vector2i(10, -25)].input["scrap_metal"] = 20
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func test_road_route_follows_the_road() -> void:
	var lure := Vector3(21, 1, -49)
	var north := Director.road_route("north", lure)
	eq(north[0], Vector3(0, 0, -258), "M17a: from the north: the park road's north end first")
	var bypass := north.find(Vector3(-25, 0, -106))
	check(north.find(Vector3(-25, 0, -142)) == bypass - 1 and bypass > 0, "then round the factory's west side")
	eq(north[bypass + 1], Vector3(0, 0, -106), "then onto the town road at its north end")
	eq(north.back(), Vector3(0, 0, -49), "and down it to the road point nearest the noise")
	var south := Director.road_route("south", lure)
	eq(south[0], Vector3(0, 0, 10), "from the south: onto the road at its south end")
	eq(south.back(), Vector3(0, 0, -49), "and up it to the same road point")
	for route: Array in [north, south]:
		for i in range(1, route.size()):
			check(route[i].distance_to(route[i - 1]) <= Director.ROAD_LEG + 0.01, "legs no longer than %d m" % Director.ROAD_LEG)
			if i > bypass + 1 or route == south:
				eq(route[i].x, 0.0, "on the road")
	eq(Director.road_route("south", Vector3(3, 0, 0)), [Vector3(0, 0, 10), Vector3(0, 0, 0)], "a noise by the spawn: the road end, then the point by it")
	eq(Director.road_route("south", Vector3(3, 0, 8)), [Vector3(0, 0, 10)], "no extra point right next to the road end")


func test_a_north_wave_walks_the_road_then_turns_to_the_noise() -> void:
	var lure := Vector3(21, 1, -49)
	var z := ZombieBrain.new(1, "shambler", GameData.load_default().zombies["shambler"], Vector3(-25, 0, -145), 7)
	var route := Director.road_route("north", lure)
	z.hear_via(route.slice(route.find(Vector3(-25, 0, -106))), lure, "o:10:-25", 120.0)  # M17a: from the hall's west side on
	eq(z.state_name(), "investigate", "on its way")
	eq(z.target_pos, Vector3(-25, 0, -106), "heading for the first waypoint, not the noise")
	var road_point := Vector3(0, 0, -49)
	var reached_road := -1.0
	var reached_lure := -1.0
	var off_road := 0
	var t := 0.0
	while t < 400.0 and reached_lure < 0.0:
		z.think(TICK, Vector3(0, 0, 500), false, false, {})
		var to := Vector3(z.target_pos.x - z.pos.x, 0, z.target_pos.z - z.pos.z)
		if to.length() > 0.05:
			z.pos += to.normalized() * minf(to.length(), z.move_speed() * TICK)
		t += TICK
		if reached_road < 0.0 and Vector2(z.pos.x - road_point.x, z.pos.z - road_point.z).length() < 2.0:
			reached_road = t
		if reached_road < 0.0 and z.pos.z > -100.0 and absf(z.pos.x) > 3.5:
			off_road += 1
		if Vector2(z.pos.x - lure.x, z.pos.z - lure.z).length() < 2.5:
			reached_lure = t
		if z.state_name() != "investigate":
			break
	check(reached_road > 0.0, "reached the road point (%.0f s)" % reached_road)
	check(reached_lure > reached_road, "then the noise (%.0f s)" % reached_lure)
	eq(off_road, 0, "it kept to the asphalt (8 m wide) on the way down")
	# Hearing the same machine again on the way doesn't make it cut across.
	var z2 := ZombieBrain.new(2, "shambler", GameData.load_default().zombies["shambler"], Vector3(-25, 0, -145), 8)
	z2.hear_via(route.slice(route.find(Vector3(-25, 0, -106))), lure, "o:10:-25", 120.0)
	z2.hear(lure, "o:10:-25")
	eq(z2.target_pos, Vector3(-25, 0, -106), "the same noise again: it keeps to the route")
	z2.hear(Vector3(-20, 0, -120), "")
	eq(z2.target_pos, Vector3(-20, 0, -120), "a new noise: it goes for that instead")
	check(z2.route.is_empty(), "and drops the route")


func test_waves_by_road_match_their_edge() -> void:
	var seen := {}
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var sim := _smelter_east(23.0, seed_value)
		sim.director.heat = 100.0
		var before := sim.horde.zombies.size()
		var wave := {}
		for i in roundi(30.1 / TICK):
			sim.step()
			if not sim.messages.is_empty() and wave.is_empty():
				wave = {"text": sim.messages.back()["text"]}
		eq(sim.horde.zombies.size() - before, 8, "seed %d: a horde of 8 at night" % seed_value)
		var edge := "north" if wave["text"].ends_with("north...") else ("south" if wave["text"].ends_with("south...") else "?")
		check(edge != "?", "seed %d: the HUD says where from (%s)" % [seed_value, wave["text"]])
		seen[edge] = true
		for z: ZombieBrain in sim.horde.zombies.values():
			if edge == "north":
				check(z.home.z < -135.0, "seed %d: spawned at the north end (z %.0f)" % [seed_value, z.home.z])
			else:
				check(z.home.z > 25.0, "seed %d: spawned at the south end (z %.0f)" % [seed_value, z.home.z])
			check(not z.route.is_empty(), "seed %d: has a road to walk" % seed_value)
			eq(z.route.back(), Vector3(0, 0, -49), "seed %d: ending at the road point by the smelter" % seed_value)
			check(z.sound_pos.distance_to(Vector3(21, 1, -49)) < 0.01, "seed %d: then the smelter" % seed_value)
	eq(seen.size(), 2, "both road ends get used")


func test_wanderers_still_come_straight() -> void:
	var sim := _smelter_east(10.0, 3)
	sim.director.heat = 120.0
	_run(sim, 30.1)
	eq(sim.horde.zombies.size(), 2, "by day: 2 wanderers")
	for z: ZombieBrain in sim.horde.zombies.values():
		check(z.route.is_empty(), "no road to walk")
		check(z.target_pos.distance_to(Vector3(21, 1, -49)) < 0.01, "straight for the smelter")
