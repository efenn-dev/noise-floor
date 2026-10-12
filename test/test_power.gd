extends "res://test/base_test.gd"
## Generators, solar, poles, networks, brownouts, fuel, siphoning, generator noise.

const TICK := SimWorld.TICK
const E := BuildGrid.Side.EAST


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _sim(hour := 10.0) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.inventory.give_all({"plank": 400, "nails": 400, "metal_plate": 200, "scrap_metal": 100, "gas_can": 10})
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func _put(sim: SimWorld, id: String, cell: Vector2i) -> String:
	if id != "power_pole":
		sim.build.place("foundation", cell, 0, sim.inventory)
	eq(sim.build.place(id, cell, E, sim.inventory), "", "place %s at %s" % [id, cell])
	return sim.build.key_for(id, cell)


func _smelter(sim: SimWorld, cell: Vector2i) -> Factory.Machine:
	_put(sim, "smelter", cell)
	var m: Factory.Machine = sim.factory.machines[cell]
	m.input["scrap_metal"] = 20
	return m


func test_machines_need_power() -> void:
	var sim := _sim()
	var m := _smelter(sim, Vector2i(0, 0))
	_run(sim, 3.0)
	eq(m.crafted, 0, "no power: the smelter sits idle")
	eq(m.status(), "no power", "and says so")
	var planter := _put(sim, "planter", Vector2i(5, 5))
	sim.factory.machines[Vector2i(5, 5)].input = {"seeds": 1, "dirty_water": 1}
	_run(sim, 0.2)
	check(sim.factory.machines[Vector2i(5, 5)].crafting, "a planter needs no power")
	check(planter != "", "planter placed")


func test_generator_powers_a_neighbour_and_burns_fuel() -> void:
	var sim := _sim()
	var m := _smelter(sim, Vector2i(0, 0))
	var gen := _put(sim, "generator", Vector2i(1, 0))  # next door: 2 m apart
	_run(sim, 1.0)
	eq(m.crafted, 0, "a generator with no fuel makes nothing")
	eq(sim.power.load_fuel(gen, sim.inventory), 10, "load 10 gas cans")
	eq(sim.inventory.count("gas_can"), 0, "from your pockets")
	_run(sim, 2.1)
	eq(m.crafted, 1, "powered: smelting")
	var net := sim.power.network_of(gen)
	near(net["demand"], 40.0, "the smelter draws 40 W")
	near(net["supply"], 100.0, "the generator makes 100 W")
	near(sim.power.generators[gen]["load"], 0.4, "40% load")
	var before := sim.power.fuel_seconds(gen)
	_run(sim, 10.0)
	near(before - sim.power.fuel_seconds(gen), 4.0, "burns 0.4 s of fuel per second at 40% load", 0.05)


func test_idle_generator_is_quiet_and_saves_fuel() -> void:
	var sim := _sim()
	var m := _smelter(sim, Vector2i(0, 0))
	var gen := _put(sim, "generator", Vector2i(1, 0))
	sim.power.load_fuel(gen, sim.inventory)
	_run(sim, 0.5)
	eq(sim.noise.continuous.size(), 2, "running: smelter and generator are both noise sources")
	var loudest := 0.0
	for s: Dictionary in sim.noise.continuous:
		loudest = maxf(loudest, s["loudness"])
	near(loudest, 80.0, "generator loudness 80")
	m.input.clear()
	_run(sim, 2.5)
	var fuel := sim.power.fuel_seconds(gen)
	_run(sim, 5.0)
	eq(sim.noise.continuous.size(), 0, "nothing to do: silent")
	near(sim.power.fuel_seconds(gen), fuel, "and burns nothing")
	eq(sim.fit_muffler(Vector2i(1, 0)), "", "generators take mufflers")
	m.input["scrap_metal"] = 5
	_run(sim, 0.5)
	var gen_noise := 0.0
	for s: Dictionary in sim.noise.continuous:
		if s["key"] == gen:
			gen_noise = s["loudness"]
	near(gen_noise, 65.0, "muffled generator: 65")


func test_poles_carry_power_across_the_base() -> void:
	var sim := _sim()
	var gen := _put(sim, "generator", Vector2i(0, 0))
	sim.power.load_fuel(gen, sim.inventory)
	var m := _smelter(sim, Vector2i(10, 0))  # 20 m away
	_run(sim, 2.5)
	eq(m.crafted, 0, "20 m away: not connected")
	_put(sim, "power_pole", Vector2i(1, 1))   # next to the generator
	_put(sim, "power_pole", Vector2i(6, 1))   # 10 m on
	_run(sim, 2.5)
	eq(m.crafted, 1, "two poles bridge the gap")
	eq(sim.power.network_of(gen)["keys"].size(), 4, "one network: generator, 2 poles, smelter")
	sim.build.remove(sim.build.key_for("power_pole", Vector2i(6, 1)), sim.inventory)
	_run(sim, 4.0)
	eq(m.crafted, 1, "take a pole away and the far smelter stops")
	eq(m.status(), "no power", "no power")


func test_brownout_stops_everything() -> void:
	var sim := _sim()
	var gen := _put(sim, "generator", Vector2i(0, 0))
	sim.power.load_fuel(gen, sim.inventory)
	_put(sim, "power_pole", Vector2i(0, 2))
	var a := _smelter(sim, Vector2i(1, 2))
	var b := _smelter(sim, Vector2i(-1, 2))
	_put(sim, "press", Vector2i(0, 3))
	sim.factory.machines[Vector2i(0, 3)].input["metal_plate"] = 10
	_run(sim, 3.0)
	var net := sim.power.network_of(gen)
	near(net["demand"], 110.0, "40 + 40 + 30 = 110 W wanted")
	check(net["brownout"], "more than the 100 W generator: brownout")
	eq(a.crafted + b.crafted, 0, "nothing works in a brownout")
	var fuel := sim.power.fuel_seconds(gen)
	_run(sim, 1.0)
	near(sim.power.fuel_seconds(gen), fuel, "a browned-out generator burns nothing")
	sim.build.remove(sim.build.key_for("press", Vector2i(0, 3)), sim.inventory)
	_run(sim, 2.1)
	eq(a.crafted + b.crafted, 2, "drop the press: both smelters run on 80 W")


func test_solar_is_silent_and_daylight_only() -> void:
	var day := _sim(12.0)
	var m := _smelter(day, Vector2i(0, 0))
	var panel := _put(day, "solar_panel", Vector2i(1, 0))
	_run(day, 2.1)
	eq(m.crafted, 1, "noon sun runs a smelter")
	near(day.power.network_of(panel)["supply"], 60.0 * day.clock.daylight(), "60 W x daylight", 0.5)
	for s: Dictionary in day.noise.continuous:
		check(s["key"] != panel, "the panel makes no noise")
	var night := _sim(23.0)
	var m2 := _smelter(night, Vector2i(0, 0))
	_put(night, "solar_panel", Vector2i(1, 0))
	_run(night, 3.0)
	eq(m2.crafted, 0, "no sun, no power")
	var dusk := _sim(19.5)
	var m3 := _smelter(dusk, Vector2i(0, 0))
	_put(dusk, "solar_panel", Vector2i(1, 0))
	var gen := _put(dusk, "generator", Vector2i(-1, 0))
	dusk.power.load_fuel(gen, dusk.inventory)
	_run(dusk, 2.1)
	eq(m3.crafted, 1, "solar + generator together")
	var g: Dictionary = dusk.power.generators[gen]
	check(g["load"] < 0.4, "solar takes some of the load first (generator at %d%%)" % roundi(g["load"] * 100))


func test_siphoning_cars() -> void:
	var sim := _sim()
	sim.inventory.remove("gas_can", 10)
	sim.loot.add("car_0", "car_trunk", Vector3.ZERO)
	sim.add_car("car_0")
	var cans: int = sim.car_fuel["car_0"]
	check(cans >= 1 and cans <= 3, "a car holds 1-3 cans (%d)" % cans)
	sim.player_pos = Vector3(30, 0, 0)
	eq(sim.siphon("car_0"), "Too far away", "stand by the car")
	sim.player_pos = Vector3(1.5, 0, 0)
	check(sim.siphon("car_0").begins_with("Siphoned"), "siphon it")
	eq(sim.inventory.count("gas_can"), cans, "gas cans in pockets")
	eq(sim.siphon("car_0"), "The tank is dry", "only once")
	sim.step()
	eq(sim.noise.recent.size(), 1, "siphoning makes a little noise")
	var again := SimWorld.new(10.0)
	again.add_car("car_0")
	eq(again.car_fuel["car_0"], cans, "same world, same fuel in the same car")


func test_removing_a_generator_returns_full_cans() -> void:
	var sim := _sim()
	var gen := _put(sim, "generator", Vector2i(0, 0))
	sim.power.load_fuel(gen, sim.inventory)
	sim.build.remove(gen, sim.inventory)
	eq(sim.inventory.count("gas_can"), 10, "all 10 cans back")
	check(not sim.power.generators.has(gen), "generator gone from the grid")


func test_poles_need_no_foundation() -> void:
	var sim := _sim()
	eq(sim.build.place("power_pole", Vector2i(20, 20), E, sim.inventory), "", "a pole stands on bare ground")
	eq(sim.build.place("generator", Vector2i(21, 20), E, sim.inventory), "Needs a foundation", "a generator doesn't")
