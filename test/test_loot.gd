extends "res://test/base_test.gd"
## Loot tables and searching containers.

const TICK := SimWorld.TICK


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func test_rolls_stay_in_range_and_repeat_with_the_seed() -> void:
	var data := GameData.load_default()
	var t: Dictionary = data.loot["kitchen"]
	var ok := true
	for s in 50:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var got := Loot.roll(t, rng)
		var picks := 0
		for item: String in got:
			var allowed := false
			for e: Dictionary in t["items"]:
				allowed = allowed or e["item"] == item
			ok = ok and allowed and got[item] >= 1
			picks += 1
		ok = ok and picks >= 1 and picks <= int(t["rolls"][1])
	check(ok, "50 rolls: only table items, 1..max picks")
	var a := RandomNumberGenerator.new()
	a.seed = 9
	var b := RandomNumberGenerator.new()
	b.seed = 9
	eq(Loot.roll(t, a), Loot.roll(t, b), "same seed, same loot")


func test_search_takes_time_and_gives_loot_once() -> void:
	var sim := SimWorld.new(10.0)
	sim.loot.add("car_0", "car_trunk", Vector3(0, 0, 0))
	sim.player_pos = Vector3(1, 0, 1)
	eq(sim.search("car_0"), "", "start searching")
	_run(sim, 0.2)
	eq(sim.noise.recent.size(), 1, "searching makes a little noise")
	near(sim.noise.recent[0]["loudness"], 30.0, "loudness 30")
	_run(sim, 2.0)
	eq(sim.inventory.items().size(), 0, "nothing yet at 2.2 s")
	_run(sim, 0.4)
	check(sim.inventory.items().size() > 0, "loot in pockets at 2.5 s: %s" % str(sim.inventory.items()))
	check(not sim.messages.is_empty(), "a 'Found ...' message")
	eq(sim.search("car_0"), "Already searched", "no second helping")


func test_walking_away_stops_the_search() -> void:
	var sim := SimWorld.new(10.0)
	sim.loot.add("fridge_1", "fridge", Vector3.ZERO)
	sim.player_pos = Vector3(10, 0, 0)
	eq(sim.search("fridge_1"), "Too far away", "must stand next to it")
	sim.player_pos = Vector3(1, 0, 0)
	sim.search("fridge_1")
	_run(sim, 1.5)
	sim.player_pos = Vector3(8, 0, 0)
	_run(sim, 2.0)
	eq(sim.inventory.items().size(), 0, "walked off: no loot")
	sim.player_pos = Vector3(1, 0, 0)
	eq(sim.search("fridge_1"), "", "can try again")
	_run(sim, 2.6)
	check(sim.inventory.items().size() > 0, "and finish it this time")


func test_same_world_same_loot() -> void:
	var a := SimWorld.new(10.0)
	var b := SimWorld.new(10.0)
	for sim: SimWorld in [a, b]:
		sim.loot.add("crate_2", "factory_crate", Vector3.ZERO)
		sim.player_pos = Vector3.ZERO
		sim.search("crate_2")
		_run(sim, 3.0)
	eq(a.inventory.items(), b.inventory.items(), "same seed and id: same items")
	var c := SimWorld.new(10.0, null, 99)
	c.loot.add("crate_2", "factory_crate", Vector3.ZERO)
	c.player_pos = Vector3.ZERO
	c.search("crate_2")
	_run(c, 3.0)
	check(c.inventory.items().size() > 0, "another world seed still finds loot")
