extends "res://test/base_test.gd"
## M11, the world gets worse: loot never comes back, fresh food rots, the town's gas goes stale,
## infamy builds from every noise and lets in runners and screamers, and the stats add up.

const N := BuildGrid.Side.NORTH
const E := BuildGrid.Side.EAST


func _next_day(sim: SimWorld) -> void:
	sim.clock.time_of_day = 23.9999
	sim.step()


func _smelter_sim() -> SimWorld:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	sim.give_debug_kit()
	sim.inventory.add("plank", 200)
	sim.inventory.add("nails", 200)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("smelter", Vector2i(0, 0), E, sim.inventory)
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 200
	sim.player_pos = Vector3(0, 0, 500)
	return sim


func test_loot_never_comes_back() -> void:
	var sim := SimWorld.new(10.0)
	sim.loot.add("box", "kitchen", Vector3.ZERO)
	sim.player_pos = Vector3.ZERO
	eq(sim.search("box"), "", "search it")
	for i in roundi(float(sim.data.survival["search_time"]) * SimWorld.TICK_RATE) + 2:
		sim.step()
	for d in 30:
		_next_day(sim)
	eq(sim.search("box"), "Already searched", "a month later it is still searched")


func test_fresh_food_rots_canned_keeps() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.give_all({"vegetable": 10, "canned_food": 5, "chips": 3})
	_next_day(sim)
	check(sim.inventory.count("vegetable") < 10, "a day later some vegetables have rotted (%d left)" % sim.inventory.count("vegetable"))
	eq(sim.inventory.count("rotten_food"), 10 - sim.inventory.count("vegetable"), "into rotten food")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].ends_with("vegetables rotted")), "it tells you")
	for d in 20:
		_next_day(sim)
	check(sim.inventory.count("vegetable") <= 1, "three weeks on they're (nearly) all gone (%d)" % sim.inventory.count("vegetable"))
	eq(sim.inventory.count("canned_food"), 5, "canned food keeps (that's what the canner is for)")
	eq(sim.inventory.count("chips"), 3, "so do chips")
	check(not sim.can_use("rotten_food"), "you can't eat rotten food")


func test_one_vegetable_lasts_a_few_days() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.add("vegetable", 1)
	var days := 0
	while sim.inventory.count("vegetable") > 0 and days < 30:
		_next_day(sim)
		days += 1
	eq(days, int(sim.data.items["vegetable"]["spoil_days"]), "a single vegetable keeps about spoil_days days")


func test_food_rots_in_crates_too() -> void:
	var sim := SimWorld.new(10.0)
	sim.inventory.add("plank", 40)
	sim.inventory.add("nails", 40)
	sim.build.place("foundation", Vector2i(0, 0), N, sim.inventory)
	sim.build.place("storage", Vector2i(0, 0), BuildGrid.Side.WEST, sim.inventory)
	var crate: Inventory = sim.storages[sim.build.key_for("storage", Vector2i(0, 0))]
	crate.add("vegetable", 10)
	for d in 3:
		_next_day(sim)
	check(crate.count("vegetable") < 10 and crate.count("rotten_food") > 0, "a crate doesn't keep food fresh")


func test_food_found_late_is_rotten() -> void:
	var sim := SimWorld.new(10.0)
	eq(sim._rot_old_food({"vegetable": 3, "soda": 2}), {"vegetable": 3, "soda": 2}, "early on, fridge food is fine")
	sim.clock.day = int(sim.data.survival["found_food_rots_day"])
	eq(sim._rot_old_food({"vegetable": 3, "soda": 2}), {"rotten_food": 3, "soda": 2}, "a week in, it's rotten (soda keeps)")


func test_the_towns_gas_goes_stale() -> void:
	var sim := SimWorld.new(10.0)
	sim.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	sim.add_car("car_1", "sedan", Vector3(0, 0.75, -10), 0.0)
	sim.vehicles.cars["car_0"]["fuel"] = 2.0
	sim.vehicles.cars["car_1"]["fuel"] = 1.0
	sim.inventory.add("gas_can", 1)
	eq(sim.refuel_car("car_0"), "Poured in 1 gas can", "pour your own gas in")
	sim.clock.day = int(sim.data.survival["gas_stale_day"]) - 1
	_next_day(sim)
	near(sim.vehicles.cars["car_0"]["fuel"], 1.0, "only the gas you poured in is still good")
	near(sim.vehicles.cars["car_1"]["fuel"], 0.0, "the town's own gas is stale")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].contains("stale")), "it tells you")
	sim.player_pos = Vector3(-2, 0, -10)
	eq(sim.siphon("car_1"), "The tank is dry", "nothing worth siphoning")


func test_infamy_builds_and_never_cools() -> void:
	var sim := _smelter_sim()
	for i in SimWorld.TICK_RATE * 30:
		sim.step()
	var after_running := sim.director.infamy
	check(after_running > 0.0, "a running smelter adds infamy (%.0f)" % after_running)
	sim.factory.machines[Vector2i(0, 0)].input.clear()
	sim.director.heat = 0.0
	for i in SimWorld.TICK_RATE * 60:
		sim.step()
	check(sim.director.infamy >= after_running, "it never cools off, unlike heat")
	var before := sim.director.infamy
	sim.noise.emit(Vector3.ZERO, 95.0, "horn")
	sim.step()
	check(sim.director.infamy > before, "loud one-offs (a horn) add infamy too")
	before = sim.director.infamy
	sim.noise.emit(Vector3.ZERO, 65.0, "wreck")
	sim.step()
	near(sim.director.infamy, before, "zombies smashing things isn't your noise")


func test_infamy_lets_in_runners_then_screamers() -> void:
	var sim := _smelter_sim()
	var none := 0
	for i in 200:
		if sim.director.pick_type() != "shambler":
			none += 1
	eq(none, 0, "at first, only shamblers")
	sim.director.infamy = 2999.0
	for i in SimWorld.TICK_RATE * 2:
		sim.step()
	check(sim.director.unlocked.has("runner"), "past 3000: runners")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].contains("fast")), "with a warning")
	check(not sim.director.unlocked.has("screamer"), "not screamers yet")
	var runners := 0
	for i in 400:
		if sim.director.pick_type() == "runner":
			runners += 1
	check(runners > 60 and runners < 140, "about a quarter of a wave are runners (%d / 400)" % runners)
	sim.director.infamy = 8000.0
	sim.step()
	check(sim.director.unlocked.has("screamer"), "past 8000: screamers")


func test_runners_are_fast_and_fragile() -> void:
	var data := GameData.load_default()
	check(float(data.zombies["runner"]["chase_speed"]) > 2.0 * float(data.zombies["shambler"]["chase_speed"]), "runners are much faster")
	check(float(data.zombies["runner"]["hp"]) < float(data.zombies["shambler"]["hp"]), "and easier to put down")


func test_a_screamer_pulls_in_the_others() -> void:
	var sim := SimWorld.new(10.0)
	sim.player_pos = Vector3(0, 0, 0)
	var screamer := sim.horde.spawn("screamer", Vector3(0, 0, -8))
	screamer.facing = Vector3(0, 0, 1)
	screamer.los_clear = true
	var other := sim.horde.spawn("shambler", Vector3(20, 0, -20))
	other.facing = Vector3(1, 0, 0)  # looking away: it can't see you
	sim.step()
	sim.step()  # a noise made this tick is heard from the next
	eq(sim.noise.recent.filter(func(s: Dictionary) -> bool: return s["kind"] == "scream").size(), 1, "it screams (once) when it sees you")
	check(screamer.screaming > 0.0 and screamer.move_speed() == 0.0, "standing still while it shrieks")
	for i in SimWorld.TICK_RATE * 2:
		sim.step()
	eq(other.state, ZombieBrain.State.INVESTIGATE, "the scream draws the one that couldn't see you")
	for i in SimWorld.TICK_RATE * 5:
		sim.step()
	eq(sim.noise.recent.filter(func(s: Dictionary) -> bool: return s["kind"] == "scream").size(), 0, "then it doesn't scream again for a while")


func test_stats_add_up_and_are_saved() -> void:
	var sim := SimWorld.new(10.0)
	var z := sim.horde.spawn("shambler", Vector3(0, 0, -1))
	z.take_hit(1000.0, Vector3.ZERO, 0.0)
	sim.step()
	sim.step()
	eq(sim.tally["kills"], 1, "a kill counts once")
	sim.player.damage(1000.0)
	eq(sim.tally["deaths"], 1, "a death counts")
	sim.director.infamy = 1234.0
	check(sim.stats_text().contains("Zombies killed 1") and sim.stats_text().contains("Noise made 1234"), "the stats line")
	var path := "user://test_world_worse_save.json"
	eq(SaveGame.write(sim, path), "", "save")
	var b := SimWorld.new(10.0)
	eq(SaveGame.apply(b, SaveGame.read(path)), "", "load")
	eq([b.tally["kills"], b.tally["deaths"]], [1, 1], "kills and deaths kept")
	near(b.director.infamy, 1234.0, "infamy kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_saves_from_before_m11_still_load() -> void:
	var sim := SimWorld.new(10.0)
	sim.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	var d := SaveGame.to_dict(sim)
	d["version"] = 1  # what M9-M10c wrote: none of M11's fields
	for key in ["stats", "infamy", "unlocked"]:
		d.erase(key)
	for id: String in d["vehicles"]:
		d["vehicles"][id].erase("fresh")
		d["vehicles"][id].erase("stale")
	var b := SimWorld.new(10.0)
	b.add_car("car_0", "sedan", Vector3(0, 0.75, 0), 0.0)
	eq(SaveGame.apply(b, JSON.parse_string(JSON.stringify(d))), "", "an M10 save loads")
	eq([b.tally["kills"], b.tally["deaths"]], [0, 0], "with no stats yet")
	near(b.director.infamy, 0.0, "and no infamy")
	check(not b.vehicles.cars["car_0"]["stale"], "the car's gas isn't stale")
	check(SaveGame.apply(SimWorld.new(10.0), {"version": SaveGame.VERSION + 1}) != "", "a save from a newer game is refused")
