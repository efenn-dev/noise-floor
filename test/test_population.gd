extends "res://test/base_test.gd"
## W3e: population and balance on the bigger map: far idle zombies think every THINK_EVERY ticks (and still wake on
## a noise); searches find more the further out they are (data/areas.json); zombies wander the roads between the
## places; the map screen (M).

const TICK := SimWorld.TICK


func test_far_idle_zombies_think_less_often_but_keep_pace() -> void:
	var sim := SimWorld.new(12.0)
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	sim.player_pos = Vector3.ZERO
	var near := sim.horde.spawn("shambler", Vector3(0, 0, -45))  # out of sight (25 m), inside FAR_THINK
	var far := sim.horde.spawn("shambler", Vector3(0, 0, -150))
	sim.horde.lazy_skips = 0
	for i in 40:
		sim.step()
	var skips := sim.horde.lazy_skips
	check(skips >= 25 and skips <= 32, "the far zombie skipped about three thinks in four (%d of 40)" % skips)
	check(near.state == ZombieBrain.State.IDLE or near.state == ZombieBrain.State.WANDER, "the near one carries on as before")
	var before := far.state
	sim.noise.emit(far.pos + Vector3(0, 0, 5), 90.0, "test")
	for i in 30:
		sim.step()
	check(far.state == ZombieBrain.State.INVESTIGATE or far.state == ZombieBrain.State.CHASE,
			"a noise beside it still draws it (was %s, now %s)" % [before, far.state])
	var skips_after := sim.horde.lazy_skips
	for i in 8:
		sim.step()
	if far.state == ZombieBrain.State.INVESTIGATE:
		eq(sim.horde.lazy_skips, skips_after, "and once it's after something it thinks every tick")


func test_searches_find_more_further_out() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "areas.json checks out")
	near(Loot.area_loot(data, Vector3(0, 0, -50)), 1.0, "town: as before")
	near(Loot.area_loot(data, Vector3(100, 0, 60)), 1.2, "downtown: more")
	eq(WorldMap.area_at(Vector3(-226, 0, -305)), "cabin", "the cabin's clearing is the cabin, not the woods round it")
	near(Loot.area_loot(data, Vector3(-226, 0, -305)), 1.5, "the hunting cabin: the most")
	near(Loot.area_loot(data, Vector3(-100, 0, 120)), 1.0, "open country between: as before")
	for area: String in WorldMap.AREAS:
		check(str(data.areas[area]["name"]) != "", "%s has a name for the map" % area)
	var town_items := 0
	var cabin_items := 0
	for i in 60:
		var w := SimWorld.new(12.0, null, i + 1)
		w.loot.add("t_%d" % i, "industrial", Vector3(0, 1, -50))
		w.loot.add("c_%d" % i, "industrial", Vector3(-226, 1, -305))
		for id: String in ["t_%d" % i, "c_%d" % i]:
			w.reveal_container(id)
			var n := 0
			for item: String in w.loot.inventory(id).items():
				n += w.loot.inventory(id).count(item)
			if id.begins_with("t"):
				town_items += n
			else:
				cabin_items += n
	check(cabin_items > town_items * 1.2, "a crate out at the cabin holds more than one in town (%d vs %d)" % [cabin_items, town_items])


func test_zombies_wander_the_roads_between_places() -> void:
	eq(str(WorldMap.roadside_zombies(3, 8)), str(WorldMap.roadside_zombies(3, 8)), "seeded")
	for seed_value: int in [1, 2, 3, 4, 5]:
		var list := WorldMap.roadside_zombies(seed_value, 8)
		eq(list.size(), 8, "seed %d: eight of them" % seed_value)
		var runners := 0
		for i in list.size():
			var z: Dictionary = list[i]
			var p: Vector3 = z["pos"]
			runners += 1 if z["type"] == "runner" else 0
			check(Vector2(p.x, p.z).length() >= WorldMap.ROADSIDE_FROM_START, "seed %d: well away from the start (%s)" % [seed_value, p])
			check(not WorldMap.on_road(Vector2(p.x, p.z), 1.0), "seed %d: beside the road, not on it" % seed_value)
			check(float(WorldMap.nearest(Vector2(p.x, p.z))["dist"]) < 14.0, "seed %d: but close to it" % seed_value)
			check(WorldMap.area_at(p) in ["", "woods", "highway"], "seed %d: out between the places (%s)" % [seed_value, WorldMap.area_at(p)])
			for j in range(i + 1, list.size()):
				check(p.distance_to(list[j]["pos"]) >= WorldMap.ROADSIDE_APART, "seed %d: spread out" % seed_value)
		eq(runners, 1, "seed %d: one is a runner" % seed_value)


func test_map_screen_opens_draws_and_closes() -> void:
	InputSetup.register()
	var sim := SimWorld.new(12.0)
	sim.place_start_stash(Vector2i(1, 3))
	sim.player_pos = Vector3(10, 0, 20)
	var map := MapScreen.new()
	tree.root.add_child(map)
	map.setup(sim)
	check(not map.is_open(), "closed to start")
	map.open()
	check(map.is_open(), "M opens it")
	check(map.base_at.is_finite() and Vector2(map.base_at.x - 3.0, map.base_at.z - 7.0).length() < 1.5,
			"your base is where you built (the starting crate: %s)" % map.base_at)
	await tree.process_frame
	var r := MapScreen.map_rect(Vector2(1920, 1080))
	near(r.size.x / r.size.y, WorldMap.EXTENT.size.x / WorldMap.EXTENT.size.y, "the map keeps the world's shape", 0.001)
	check(MapScreen.to_map(r, WorldMap.EXTENT.position).distance_to(r.position) < 0.01, "the north-west corner at the top left")
	check(MapScreen.to_map(r, WorldMap.EXTENT.end).distance_to(r.end) < 0.01, "the south-east corner at the bottom right")
	check(MapScreen.to_map(r, Vector2(0, -400)).y < MapScreen.to_map(r, Vector2(0, 200)).y, "north is up")
	var press := InputEventAction.new()
	press.action = "map"
	press.pressed = true
	map._input(press)
	check(not map.is_open(), "M closes it again")
	map.queue_free()
	await tree.process_frame
