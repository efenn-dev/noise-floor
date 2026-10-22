extends "res://test/base_test.gd"
## Co-op A (docs/COOP_PLAN.md): the sim holds two players. Each has their own pockets, gear, skills, hunger, messages
## and search; zombies go for the nearer living one; a car holds one driver; the save carries everyone and an older
## one-player save still loads.

const N := BuildGrid.Side.NORTH


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 6, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	return sim


func _town(sim: SimWorld) -> void:
	sim.loot.add("car_0", "car_trunk", Vector3(0, 0, -15))
	sim.add_car("car_0")
	sim.loot.add("house_0_e", "kitchen", Vector3(6.6, 0.8, -10))
	sim.loot.add("house_1_e", "kitchen", Vector3(40.0, 0.8, 30.0))


func test_a_second_player_has_their_own_everything() -> void:
	var sim := _sim()
	eq(sim.players.size(), 1, "a sim starts with one player, the host")
	eq(sim.active, 0, "and acts as them")
	var k := sim.add_player("Kid")
	eq(k, 1, "the second player is slot 1")
	eq(sim.players[1].name, "Kid", "by name")
	check(sim.players[1].inventory != sim.players[0].inventory and sim.players[1].gear != sim.players[0].gear
			and sim.players[1].skills != sim.players[0].skills and sim.players[1].stats != sim.players[0].stats,
			"with pockets, gear, skills and a body of their own")
	eq(sim.players[1].gear.weapon_class(), "blunt", "and the starting pipe")
	sim.inventory.add("plank", 5)
	sim.as_player(1, func() -> void: sim.inventory.add("nails", 7))
	eq(sim.players[0].inventory.count("plank"), 5, "the host's planks are the host's")
	eq(sim.players[0].inventory.count("nails"), 0, "not the nails")
	eq(sim.players[1].inventory.count("nails"), 7, "which are Kid's")
	eq(sim.active, 0, "as_player puts the active player back")
	sim.as_player(1, func() -> void: sim.add_message("hello"))
	eq(sim.players[1].messages.size(), 1, "a message said as Kid is on Kid's HUD")
	eq(sim.messages.size(), 0, "not the host's")
	sim.as_player(1, func() -> void: sim.player.food = 10.0)
	near(sim.player.food, 100.0, "the host is still fed")
	near(sim.players[1].stats.food, 10.0, "Kid is hungry")
	for i in SimWorld.TICK_RATE * 5:
		sim.step()
	check(sim.players[1].stats.food < 10.0 and sim.players[0].stats.food < 100.0, "both tick (%.2f, %.2f)" % [sim.players[0].stats.food, sim.players[1].stats.food])
	eq(sim.active, 0, "and the host is active again after a tick")


func test_each_player_searches_and_builds_on_their_own() -> void:
	var sim := _sim()
	_town(sim)
	var k := sim.add_player("Kid")
	sim.player_pos = Vector3(6.6, 0, -9)
	sim.as_player(k, func() -> void: sim.player_pos = Vector3(40.0, 0, 29.0))
	eq(sim.loot.start("house_0_e", sim.player_pos), "", "the host starts on one fridge")
	sim.as_player(k, func() -> void: eq(sim.loot.start("house_1_e", sim.player_pos), "", "Kid on another"))
	eq(sim.loot.active, "house_0_e", "the host's search is the host's")
	sim.as_player(k, func() -> void: eq(sim.loot.active, "house_1_e", "Kid's is Kid's"))
	var ticks := int(ceil(sim.loot.search_time() / SimWorld.TICK)) + 2
	for i in ticks:
		sim.step()
	check(sim.loot.containers["house_0_e"]["searched"] and sim.loot.containers["house_1_e"]["searched"], "both finish")
	var host_said: Array = sim.players[0].messages.filter(func(m: Dictionary) -> bool: return String(m["text"]).begins_with("Found") or String(m["text"]).begins_with("Nothing useful"))
	var kid_said: Array = sim.players[1].messages.filter(func(m: Dictionary) -> bool: return String(m["text"]).begins_with("Found") or String(m["text"]).begins_with("Nothing useful"))
	eq(host_said.size(), 1, "the host hears about the host's search (%s)" % [sim.players[0].messages])
	eq(kid_said.size(), 1, "Kid about his (%s)" % [sim.players[1].messages])
	# Building draws from the builder's pockets.
	sim.as_player(k, func() -> void: sim.inventory.give_all({"plank": 10}))
	eq(sim.build.place("foundation", Vector2i(20, 20), N, sim.inventory), "Not enough materials", "the host has no planks")
	sim.as_player(k, func() -> void: eq(sim.build.place("foundation", Vector2i(20, 20), N, sim.inventory), "", "Kid does"))
	eq(sim.players[1].inventory.count("plank"), 6, "and paid")


func test_zombies_go_for_the_nearer_living_player() -> void:
	var sim := _sim()
	var k := sim.add_player("Kid")
	sim.player_pos = Vector3(0, 0, 0)
	sim.as_player(k, func() -> void: sim.player_pos = Vector3(30, 0, 0))
	var z := sim.horde.spawn("shambler", Vector3(30.6, 0, 0))  # within arm's reach: the world walks zombies, the sim alone doesn't
	z.facing = Vector3(-1, 0, 0)
	z.los_clear = true  # (the world's raycast sets this; here nothing stands between them)
	var host_hp: float = sim.players[0].stats.health
	for i in SimWorld.TICK_RATE * 6:
		sim.step()
	check(sim.players[1].stats.health < 100.0, "it reaches Kid, 2 m away (%.0f)" % sim.players[1].stats.health)
	near(sim.players[0].stats.health, host_hp, "the host, 30 m off, isn't touched")
	check(z.last_seen.distance_to(Vector3(30, 0, 0)) < 3.0, "it was hunting Kid (%s)" % z.last_seen)
	# With Kid dead, it turns to the host.
	sim.players[1].inventory.add("nails", 4)
	sim.players[1].stats.damage(1000.0, "shambler")
	check(sim.players[1].stats.dead, "Kid is down")
	check(not sim.bags.is_empty() and sim.bags[-1]["pos"].distance_to(Vector3(30, 0, 0)) < 1.0, "his bag lies where he fell (%s)" % [sim.bags])
	eq(int(sim.bags[-1]["items"].get("nails", 0)), 4, "with his nails in it")
	eq(sim.players[0].inventory.count("nails"), 0, "the host's pockets are untouched")
	var who := Horde.nearest_player(z.pos, {"players": [
			{"index": 0, "pos": Vector3(0, 0, 0), "dead": false, "lit": false},
			{"index": 1, "pos": Vector3(30, 0, 0), "dead": true, "lit": false}]})
	eq(int(who["index"]), 0, "the nearest LIVING player is the one zombies mind")
	who = Horde.nearest_player(z.pos, {"player_pos": Vector3(5, 0, 5), "player_dead": false, "player_lit": true})
	eq(int(who["index"]), 0, "without a roster the old keys describe the one player")
	check(bool(who["lit"]), "with their light")


func test_one_driver_per_car_and_a_search_per_player() -> void:
	var sim := _sim()
	_town(sim)
	var k := sim.add_player("Kid")
	eq(sim.vehicles.enter("car_0"), "", "the host gets in car_0")
	eq(sim.vehicles.driving, "car_0", "and is driving")
	sim.as_player(k, func() -> void:
		eq(sim.vehicles.driving, "", "Kid isn't")
		eq(sim.vehicles.enter("car_0"), "Someone's already in it", "and can't take the same seat"))
	eq(sim.vehicles.driver_of("car_0"), 0, "the car knows its driver")
	eq(sim.vehicles.car_of(1), "", "and that Kid has none")
	sim.vehicles.exit()
	eq(sim.vehicles.driver_of("car_0"), -1, "out: nobody's in it")


func test_the_save_carries_everyone_and_an_old_one_loads() -> void:
	var sim := _sim()
	_town(sim)
	var k := sim.add_player("Kid")
	sim.inventory.add("plank", 3)
	sim.as_player(k, func() -> void:
		sim.inventory.add("nails", 9)
		sim.player_pos = Vector3(12, 0, 34)
		sim.skills.perk_points = 2
		sim.skills.spend("heavy_swing")
		sim.player.food = 40.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(d["version"]), SaveGame.VERSION, "the new version")
	eq(d["players"].size(), 2, "two players in the save")
	eq(int(d["inventory"]["plank"]), 3, "the host's pockets still sit at the top level too (older readers)")
	var b := SimWorld.new(12.0, null, 6, "normal")
	_town(b)
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.players.size(), 2, "both players back")
	eq(b.players[1].name, "Kid", "by name")
	eq(b.players[0].inventory.count("plank"), 3, "the host's planks")
	eq(b.players[1].inventory.count("nails"), 9, "Kid's nails")
	eq(b.players[1].skills.rank("heavy_swing"), 1, "Kid's perk")
	near(b.players[1].stats.food, 40.0, "Kid's hunger")
	check(b.players[1].pos.distance_to(Vector3(12, 0, 34)) < 0.01, "where Kid stood")
	eq(b.active, 0, "the host is active after a load")
	# A save with one player at the top level and no players list (every save before co-op A).
	var old := d.duplicate(true)
	old.erase("players")
	old["version"] = 25
	var c := SimWorld.new(12.0, null, 6, "normal")
	_town(c)
	eq(SaveGame.apply(c, old), "", "an old save loads")
	eq(c.players.size(), 1, "as one player")
	eq(c.players[0].inventory.count("plank"), 3, "with their pockets")


func test_the_newest_old_fixture_loads_as_one_player() -> void:
	for v in [24, 25]:
		var d := SaveGame.read("res://test/fixtures/save_v%d.json" % v)
		check(not d.has("players"), "the version-%d save has no players list" % v)
		var sim := SimWorld.new(8.0, null, int(d["seed"]))
		_town(sim)
		var plan := TownPlan.generate(sim.seed_value)
		if not SaveGame.holds_town(d):
			sim.place_town(plan)
		if not SaveGame.holds_factory(d):
			sim.place_factory(plan)
		eq(SaveGame.apply(sim, d), "", "the version-%d save loads" % v)
		eq(sim.players.size(), 1, "as one player")
		eq(sim.active, 0, "the host")
