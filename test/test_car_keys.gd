extends "res://test/base_test.gd"
## Zomboid-style car keys and hotwiring: each car's key is somewhere (ignition, glovebox, a nearby
## house, or lost); without it the engine won't start unless you hotwire it, which needs Mechanics 2.


func _town() -> SimWorld:
	var sim := SimWorld.new(10.0)
	for i in 6:
		for side in ["e", "w"]:
			sim.loot.add("house_%d_%s" % [i, side], "kitchen", Vector3(6.6 if side == "e" else -6.6, 0.8, -10.0 - i * 16.0))
	for i in 8:
		var id := "car_%d" % i
		var pos := Vector3(0, 0.75, -15.0 - i * 11.0)
		sim.loot.add(id, "car_trunk", pos)
		sim.add_car(id, "sedan", pos, 0.0)
		sim.vehicles.cars[id]["wreck"] = ""  # these tests are about keys
	return sim


func _search(sim: SimWorld, id: String) -> void:
	sim.player_pos = sim.loot.containers[id]["pos"]
	eq(sim.search(id), "", "start searching %s" % id)
	for i in roundi(float(sim.data.survival["search_time"]) * SimWorld.TICK_RATE) + 2:
		sim.step()


func test_keys_are_somewhere() -> void:
	var a := _town()
	var b := _town()
	var places := {}
	for id: String in a.vehicles.cars:
		eq(a.vehicles.cars[id]["key_in"], b.vehicles.cars[id]["key_in"], "%s: same world, same key spot" % id)
		places[a.vehicles.cars[id]["key_in"]] = true
	eq(a.vehicles.cars["car_0"]["key_in"], "glovebox", "car_0's key is always in its glovebox")
	check(places.size() >= 3, "keys turn up in different places (%s)" % ", ".join(places.keys()))
	for id: String in a.vehicles.cars:
		if a.vehicles.cars[id]["key_in"] == "house":
			var found := false
			for cid: String in a.loot.containers:
				if cid.begins_with("house_") and a.loot.containers[cid]["extra"].has(Vehicles.key_item(id)):
					found = true
			check(found, "%s's key is waiting in a house" % id)


func test_no_key_no_engine_until_you_find_it() -> void:
	var sim := _town()
	eq(sim.enter_car("car_0"), "", "you can sit in it")
	check(not sim.vehicles.is_running("car_0"), "but without the key it won't start")
	sim.exit_car()
	_search(sim, "car_0")
	eq(sim.inventory.count(Vehicles.key_item("car_0")), 1, "searching the car finds its key in the glovebox")
	eq(sim.data.item_name(Vehicles.key_item("car_0")), "Car key", "it's a car key")
	eq(sim.enter_car("car_0"), "", "get back in")
	check(sim.vehicles.is_running("car_0"), "and now it starts")


func test_key_in_the_ignition() -> void:
	var sim := _town()
	for id: String in sim.vehicles.cars:
		if sim.vehicles.cars[id]["key_in"] == "ignition":
			sim.enter_car(id)
			check(sim.vehicles.is_running(id), "%s: the key's in it, so it starts" % id)
			return
	check(false, "some car has its key in the ignition")


func test_hotwiring_needs_mechanics() -> void:
	var sim := _town()
	sim.enter_car("car_0")
	eq(sim.hotwire(), "You don't know how to hotwire a car (needs Mechanics 2)", "level 0 can't")
	sim.skills.xp["mechanics"] = float(sim.data.skills["levels"][2])
	eq(sim.skills.level("mechanics"), 2, "Mechanics 2")
	var xp: float = sim.skills.xp["mechanics"]
	eq(sim.hotwire(), "", "now you can")
	sim.step()
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "hotwire"), "fiddling with wires makes a little noise")
	for i in roundi(float(sim.data.skills["hotwire_seconds"]) * SimWorld.TICK_RATE) - 2:
		sim.step()
	check(not sim.vehicles.is_running("car_0"), "it takes a while")
	for i in 4:
		sim.step()
	check(sim.vehicles.is_running("car_0"), "then the engine catches")
	check(sim.skills.xp["mechanics"] > xp, "and you learned something")
	sim.exit_car()
	sim.enter_car("car_0")
	check(sim.vehicles.is_running("car_0"), "a hotwired car starts again without a key")
	eq(sim.hotwire(), "You don't need to: you can start this one", "no need to do it twice")


func test_better_mechanics_hotwire_faster() -> void:
	var sim := _town()
	sim.skills.xp["mechanics"] = float(sim.data.skills["levels"][4])
	sim.enter_car("car_0")
	sim.hotwire()
	near(sim.vehicles.hotwire_left, float(sim.data.skills["hotwire_seconds"]) - 2.0 * float(sim.data.skills["hotwire_seconds_per_level"]),
			"Mechanics 4 is two levels quicker")
	sim.exit_car()
	eq(sim.vehicles.hotwire_left, 0.0, "getting out stops it")


func test_mechanics_levels_by_doing() -> void:
	var sim := _town()
	eq(sim.skills.level("mechanics"), 0, "start at 0")
	sim.inventory.give_all({"metal_plate": 10, "nails": 40})
	sim.vehicles.damage("car_0", 1000.0)
	for i in 2:
		eq(sim.repair_car("car_0"), "", "repair the car")
	near(sim.skills.xp["mechanics"], 2.0 * float(sim.data.skills["skills"]["mechanics"]["xp"]["repair_car"]), "car repairs teach Mechanics")
	eq(sim.skills.level("mechanics"), 1, "level 1 after two")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"] == "Mechanics is now level 1"), "it says so")


func test_skills_and_hotwiring_are_saved() -> void:
	var sim := _town()
	sim.skills.xp["mechanics"] = 95.0
	sim.vehicles.cars["car_3"]["hotwired"] = true
	var path := "user://test_car_keys_save.json"
	eq(SaveGame.write(sim, path), "", "save")
	var b := _town()
	eq(SaveGame.apply(b, SaveGame.read(path)), "", "load")
	near(b.skills.xp.get("mechanics", 0.0), 95.0, "Mechanics xp kept")
	check(b.vehicles.cars["car_3"]["hotwired"], "the hotwired car stays hotwired")
	eq(b.vehicles.cars["car_0"]["key_in"], "glovebox", "and keys stay where they were")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_start_hint_says_why_a_car_wont_go() -> void:
	var sim := _town()
	var v := sim.vehicles
	eq(v.cars["car_0"]["key_in"], "glovebox", "car_0's key starts in its glovebox")
	eq(v.start_hint("car_0", sim.inventory), Vehicles.NO_KEY_HINT, "no key: where to look")
	eq(Vehicles.NO_KEY_HINT, "No key: search the trunk (E at the back) or the nearest house", "in plain words")
	sim.inventory.add(Vehicles.key_item("car_0"), 1)
	eq(v.start_hint("car_0", sim.inventory), "", "key in your pockets: nothing to explain")
	sim.inventory.remove(Vehicles.key_item("car_0"), 1)
	v.cars["car_0"]["hotwired"] = true
	eq(v.start_hint("car_0", sim.inventory), "", "hotwired: nothing to explain")
	v.cars["car_0"]["hotwired"] = false
	v.cars["car_0"]["key_in"] = "ignition"
	eq(v.start_hint("car_0", sim.inventory), "", "key in the ignition: nothing to explain")
	v.cars["car_1"]["wreck"] = "Flat tyres"
	var wreck := v.start_hint("car_1", sim.inventory)
	check(wreck.begins_with("Flat tyres. "), "a wreck says what's wrong (%s)" % wreck)
	check("search the trunk" in wreck and "siphon" in wreck, "and that it can still be searched and siphoned")
	sim.inventory.add(Vehicles.key_item("car_1"), 1)
	check(v.start_hint("car_1", sim.inventory).begins_with("Flat tyres. "), "even with its key, a wreck is a wreck")


func test_no_key_message_once_per_car() -> void:
	var sim := _town()
	var told := func() -> int:
		return sim.messages.filter(func(m: Dictionary) -> bool: return m["text"] == SimWorld.NO_KEY_MESSAGE).size()
	eq(sim.enter_car("car_0"), "", "sit in car_0 without its key")
	eq(told.call(), 1, "the HUD says there's no key and where to look")
	eq(SimWorld.NO_KEY_MESSAGE, "No key. The glovebox is searched from the trunk, or try the nearest house", "in plain words")
	sim.exit_car()
	sim.enter_car("car_0")
	eq(told.call(), 1, "only once per car")
	sim.exit_car()
	sim.vehicles.cars["car_1"]["key_in"] = "house"
	sim.enter_car("car_1")
	eq(told.call(), 2, "a different keyless car says it again")
	sim.exit_car()
	sim.vehicles.cars["car_2"]["key_in"] = "ignition"
	sim.enter_car("car_2")
	eq(told.call(), 2, "a car you can start says nothing")
