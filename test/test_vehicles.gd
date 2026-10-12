extends "res://test/base_test.gd"
## The rules for cars: wrecks, getting in and out, fuel (shared with siphoning), engine noise,
## running zombies over, zombies hitting the car instead of you, refuelling, repair, and saving.


func _sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.loot.add("car_0", "car_trunk", Vector3(0, 0.75, 0))
	sim.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	sim.vehicles.cars["car_0"]["fuel"] = 2.0
	sim.inventory.add(Vehicles.key_item("car_0"), 1)  # these tests are about driving, not keys
	sim.player_pos = Vector3(-2, 0, 0)
	return sim


func test_wrecks_are_fixed_by_the_world() -> void:
	var a := SimWorld.new(10.0)
	var b := SimWorld.new(10.0)
	var wrecks := 0
	for i in 12:
		a.add_car("car_%d" % i, "sedan")
		b.add_car("car_%d" % i, "sedan")
		eq(a.vehicles.cars["car_%d" % i]["wreck"], b.vehicles.cars["car_%d" % i]["wreck"], "car_%d: same world, same car" % i)
		if a.vehicles.cars["car_%d" % i]["wreck"] != "":
			wrecks += 1
	eq(a.vehicles.cars["car_0"]["wreck"], "", "car_0 always drives")
	check(wrecks > 0 and wrecks < 12, "some cars are wrecks, not all (%d of 12)" % wrecks)


func test_get_in_drive_and_get_out() -> void:
	var sim := _sim()
	eq(sim.enter_car("car_0"), "", "get in")
	eq(sim.vehicles.driving, "car_0", "now driving")
	check(sim.vehicles.is_running("car_0"), "the engine starts with gas in it")
	eq(sim.enter_car("car_0"), "Already driving", "can't get in twice")
	sim.car_moved(Vector3(0, 0.75, -400), 0.0, 10.0)
	near(sim.vehicles.cars["car_0"]["fuel"], 2.0 - 400.0 / 800.0, "400 m burns half a can", 0.001)
	eq(sim.player_pos, Vector3(0, 0.75, -400), "you're where the car is (zombies come for it)")
	eq(sim.loot.containers["car_0"]["pos"], sim.vehicles.trunk_pos("car_0"), "the trunk comes along")
	check(sim.vehicles.trunk_pos("car_0").distance_to(Vector3(0, 0.75, -400)) > 2.0, "at the back of the car")
	var out := sim.exit_car()
	check(out.x < -0.9, "you get out on the driver's side (%s)" % out)
	check(not sim.vehicles.is_running("car_0") and sim.vehicles.driving == "", "the engine stops when you get out")


func test_engine_noise_and_horn() -> void:
	var sim := _sim()
	sim.step()
	eq(sim.noise.continuous.size(), 0, "a parked car is quiet")
	sim.enter_car("car_0")
	sim.step()
	var engine := sim.noise.continuous.filter(func(s: Dictionary) -> bool: return s["kind"] == "car")
	eq(engine.size(), 1, "a running engine is a noise source")
	near(engine[0]["loudness"] if engine.size() > 0 else 0.0, float(sim.data.vehicles["sedan"]["loudness"]), "as loud as the sedan")
	sim.honk()
	sim.step()
	check(sim.noise.recent.any(func(s: Dictionary) -> bool: return s["kind"] == "horn"), "the horn is heard")


func test_running_out_of_gas() -> void:
	var sim := _sim()
	sim.vehicles.cars["car_0"]["fuel"] = 0.01
	sim.enter_car("car_0")
	sim.car_moved(Vector3(0, 0.75, -100), 0.0, 10.0)
	check(not sim.vehicles.is_running("car_0"), "the engine dies when the tank runs dry")
	eq(sim.vehicles.cars["car_0"]["fuel"], 0.0, "empty, not negative")
	sim.exit_car()
	sim.vehicles.cars["car_0"]["fuel"] = 0.0
	eq(sim.enter_car("car_0"), "", "you can still sit in it")
	check(not sim.vehicles.is_running("car_0"), "but it won't start")


func test_idling_burns_a_little() -> void:
	var sim := _sim()
	sim.enter_car("car_0")
	for i in SimWorld.TICK_RATE * 60:
		sim.step()
	near(sim.vehicles.cars["car_0"]["fuel"], 2.0 - float(sim.data.vehicles["sedan"]["idle_cans_per_minute"]), "a minute idling", 0.001)


func test_siphon_and_refuel_share_the_tank() -> void:
	var sim := _sim()
	sim.vehicles.cars["car_0"]["fuel"] = 2.6
	check(sim.siphon("car_0").begins_with("Siphoned 2"), "siphon takes the whole cans")
	near(sim.vehicles.cars["car_0"]["fuel"], 0.6, "the part-can stays in the tank")
	eq(sim.refuel_car("car_0"), "Poured in 2 gas cans", "pour them back")
	near(sim.vehicles.cars["car_0"]["fuel"], 2.6, "back where it was")
	sim.inventory.add("gas_can", 5)
	eq(sim.refuel_car("car_0"), "Poured in 1 gas can", "only whole cans that fit (4-can tank)")
	eq(sim.inventory.count("gas_can"), 4, "the rest stay in your pockets")
	eq(sim.refuel_car("car_0"), "The tank is full", "full")


func test_zombies_hit_the_car_not_you() -> void:
	var sim := _sim()
	sim.enter_car("car_0")
	var z := sim.horde.spawn("shambler", Vector3(0.8, 0, 0.5))
	z.facing = Vector3(-0.8, 0, -0.5).normalized()
	z.los_clear = true  # in the game its body reports this; here there is no body
	z.state = ZombieBrain.State.CHASE
	var hp: float = sim.vehicles.cars["car_0"]["hp"]
	for i in SimWorld.TICK_RATE * 4:
		sim.step()
	eq(sim.player.health, 100.0, "you're safe inside")
	check(sim.vehicles.cars["car_0"]["hp"] < hp, "the car takes the hits (%.0f -> %.0f)" % [hp, sim.vehicles.cars["car_0"]["hp"]])


func test_running_zombies_over() -> void:
	var sim := _sim()
	sim.enter_car("car_0")
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -3))
	var hp: float = sim.vehicles.cars["car_0"]["hp"]
	check(sim.car_hits_zombie(z.id, 15.0), "15 m/s kills a shambler")
	check(sim.vehicles.cars["car_0"]["hp"] < hp, "and dents the car")
	var slow := sim.horde.spawn("shambler", Vector3(0, 0, -6))
	check(not sim.car_hits_zombie(slow.id, 3.0), "a slow bump only hurts")
	check(slow.hp < float(sim.data.zombies["shambler"]["hp"]), "but it does hurt")


func test_wrecks_and_repair() -> void:
	var sim := _sim()
	sim.vehicles.cars["car_0"]["wreck"] = "Flat tyres"
	eq(sim.enter_car("car_0"), "Flat tyres", "a wreck won't go")
	sim.vehicles.cars["car_0"]["wreck"] = ""
	sim.vehicles.damage("car_0", 1000.0)
	eq(sim.enter_car("car_0"), "Too smashed up to drive", "neither will a smashed car")
	eq(sim.repair_car("car_0"), "Needs a metal plate and 4 nails", "repair needs parts")
	sim.inventory.give_all({"metal_plate": 4, "nails": 16})
	for i in 4:
		eq(sim.repair_car("car_0"), "", "repair %d" % (i + 1))
	near(sim.vehicles.cars["car_0"]["hp"], float(sim.data.vehicles["sedan"]["hp"]), "four repairs fix it")
	eq(sim.repair_car("car_0"), "Not damaged", "nothing left to fix")
	eq(sim.enter_car("car_0"), "", "and it drives again")


func test_saved_where_you_parked() -> void:
	var sim := _sim()
	sim.enter_car("car_0")
	sim.car_moved(Vector3(12, 0.75, -40), 1.2, 5.0)
	var path := "user://test_vehicles_save.json"
	eq(SaveGame.write(sim, path), "", "save while driving")
	var b := SimWorld.new(10.0)
	b.loot.add("car_0", "car_trunk", Vector3(0, 0.75, 0))
	b.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	eq(SaveGame.apply(b, SaveGame.read(path)), "", "load")
	var c: Dictionary = b.vehicles.cars["car_0"]
	eq(c["pos"], Vector3(12, 0.75, -40), "the car is where you left it")
	near(c["yaw"], 1.2, "facing the same way")
	near(c["fuel"], sim.vehicles.cars["car_0"]["fuel"], "with the same gas")
	eq(b.vehicles.driving, "", "nobody is driving after a load")
	check(b.player_pos.distance_to(Vector3(12, 0.75, -40)) > 1.0, "you load beside the car, not inside it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
