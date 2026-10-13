extends "res://test/base_test.gd"
## M17a: big projects (Projects, data/projects.json): the water tower's three phases. Delivering takes the
## items (pockets and crates within 30 m); work accrues only within 6 m and is a continuous noise source while
## it runs; phase 3 needs 60 W spare on a network the tower is on; the reward triples rain collectors and lets
## water taps run (and be built); save and load keep phases, progress and the reward; the project screen shows
## what the next phase needs.

const TICK := SimWorld.TICK
const ID := "water_tower"
var tower := ParkPlan.TOWER_POS


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0)
	sim.place_park(ParkPlan.generate(1))
	return sim


func _steps(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


func _project_noise(sim: SimWorld) -> Dictionary:
	for s: Dictionary in sim.noise.continuous:
		if s["key"] == "project:" + ID:
			return s
	return {}


## A storage crate on its own foundation at `cell`, holding `items`.
func _crate(sim: SimWorld, cell: Vector2i, items: Dictionary) -> String:
	var inv := Inventory.new()
	inv.give_all({"plank": 20, "nails": 20})
	sim.build.place("foundation", cell, BuildGrid.Side.NORTH, inv)
	sim.build.place("storage", cell, BuildGrid.Side.WEST, inv)
	var key := sim.build.key_for("storage", cell)
	sim.storages[key].give_all(items)
	return key


func test_data_is_checked() -> void:
	var data := GameData.load_default()
	eq(data.validate().size(), 0, "shipped data validates")
	var phases: Array = data.projects[ID]["phases"]
	eq(phases.size(), 3, "three phases")
	eq(int(phases[0]["needs"]["metal_plate"]), 10, "phase 1: 10 metal plates")
	eq([int(phases[1]["needs"]["wall_panel"]), int(phases[1]["needs"]["nails"])], [6, 20], "phase 2: 6 wall panels and 20 nails")
	eq([int(phases[0]["loudness"]), int(phases[1]["loudness"]), int(phases[2]["loudness"])], [70, 75, 85], "loudness 70, 75, 85")
	eq(int(phases[2]["watts"]), 60, "the pump needs 60 W")
	var bad := GameData.load_default()
	bad.projects = data.projects.duplicate(true)
	bad.projects[ID]["phases"][0]["needs"] = {"unobtainium": 3}
	bad.projects[ID]["reward"]["unlocks"] = ["nothing_real"]
	var errors := bad.validate()
	check(errors.size() >= 2, "a made-up item and unlock are flagged (%s)" % [errors])


func test_delivering_takes_the_items() -> void:
	var sim := _sim()
	sim.player_pos = tower + Vector3(-4, 0, 0)
	sim.inventory.give_all({"metal_plate": 6, "nails": 5})
	check(sim.projects.missing(ID) == {"metal_plate": 10}, "phase 1 needs 10 metal plates")
	check(sim.project_start(ID) != "", "work won't start before the items are in")
	var msg := sim.project_deliver(ID)
	check(msg.begins_with("Delivered 6"), "delivered from pockets (%s)" % msg)
	eq(sim.inventory.count("metal_plate"), 0, "the plates left your pockets")
	eq(sim.inventory.count("nails"), 5, "the nails stay (phase 1 doesn't need them)")
	eq(sim.projects.missing(ID), {"metal_plate": 4}, "4 still needed")
	var near := _crate(sim, Vector2i(4, -93), {"metal_plate": 9})  # about 9 m from the tower
	var far := _crate(sim, Vector2i(4, -70), {"metal_plate": 9})   # about 46 m away
	sim.project_deliver(ID)
	eq(sim.storages[near].count("metal_plate"), 5, "4 taken from the crate within 30 m")
	eq(sim.storages[far].count("metal_plate"), 9, "none from the crate 46 m away")
	check(sim.projects.missing(ID).is_empty(), "phase 1 has everything")
	eq(sim.project_deliver(ID), "It has everything this phase needs: start the work", "nothing more to deliver")
	eq(sim.projects.state[ID]["progress"], 0.0, "delivering isn't work")


func test_work_accrues_only_within_6_m_and_is_loud() -> void:
	var sim := _sim()
	sim.inventory.give_all({"metal_plate": 10})
	sim.player_pos = tower + Vector3(-5, 0, 0)
	sim.project_deliver(ID)
	sim.player_pos = tower + Vector3(-10, 0, 0)
	eq(sim.project_start(ID), "Work started: stand within 6 m of it to keep it going", "started from 10 m away")
	_steps(sim, 5.0)
	eq(sim.projects.state[ID]["progress"], 0.0, "no work 10 m away")
	check(_project_noise(sim).is_empty(), "and no noise")
	sim.player_pos = tower + Vector3(-5.5, 0, 0)
	_steps(sim, 5.0)
	var p1: float = sim.projects.state[ID]["progress"]
	check(p1 > 0.0, "work accrues 5.5 m away (%.3f)" % p1)
	near(p1, 5.0 / sim.clock.seconds_per_hour(), "one game-hour of work in all", 0.01)
	var src := _project_noise(sim)
	near(float(src.get("loudness", 0)), 70.0, "hammering: a continuous source at loudness 70")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].begins_with("You start patching the tank")), "the HUD says it started")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return e["text"] == "Water tower: phase 1 started (patch the tank)"), "and the base log")
	sim.player_pos = tower + Vector3(-7, 0, 0)
	_steps(sim, 3.0)
	near(sim.projects.state[ID]["progress"], p1, "it pauses when you walk off", 1e-6)
	check(_project_noise(sim).is_empty(), "and goes quiet")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].contains("paused")), "the HUD says it paused")
	sim.player_pos = tower + Vector3(0, 0, 4)
	sim.player.asleep = true
	_steps(sim, 2.0)
	near(sim.projects.state[ID]["progress"], p1, "no work while asleep", 1e-6)
	sim.player.asleep = false
	var z := sim.horde.spawn("shambler", tower + Vector3(-15, 0, 0))  # out on the park road
	_steps(sim, 2.0)
	check(z.state_name() in ["investigate", "chase", "attack"], "a zombie 15 m away on the road heard the hammering (%s)" % z.state_name())
	sim.horde.zombies.erase(z.id)  # (it would interrupt nothing, but it would hurt)
	_steps(sim, sim.clock.seconds_per_hour())
	eq(sim.projects.phase(ID), 1, "phase 1 done after a game-hour of work")
	eq(sim.projects.missing(ID), {"wall_panel": 6, "nails": 20}, "phase 2 needs wall panels and nails")
	check(not sim.projects.is_working(ID), "phase 2 waits to be started")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return e["text"] == "Water tower: phase 1 of 3 done (patch the tank)"), "the base log says phase 1 is done")


func test_phase_3_needs_60_spare_watts() -> void:
	var sim := _sim()
	sim.projects.state[ID]["phase"] = 2
	sim.player_pos = tower + Vector3(-4, 0, 0)
	check(sim.projects.missing(ID).is_empty(), "the pump needs no items")
	eq(sim.project_start(ID), "Work started: stay within 6 m. It's loud.", "started")
	_steps(sim, 2.0)
	eq(sim.projects.state[ID]["progress"], 0.0, "no power network: nothing")
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"].contains("60 W spare")), "the HUD says it needs 60 W spare")
	var inv := Inventory.new()
	inv.give_all({"plank": 40, "nails": 60, "metal_plate": 40, "gas_can": 5})
	# A generator (100 W) with two heaters (40 W each) on it, 12 m south-west; a pole by the tower links it.
	var gen_cell := Vector2i(1, -88)
	sim.build.place("foundation", gen_cell, 0, inv)
	sim.build.place("generator", gen_cell, BuildGrid.Side.NORTH, inv)
	sim.power.load_fuel(sim.build.key_for("generator", gen_cell), inv)
	for c: Vector2i in [Vector2i(2, -88), Vector2i(1, -87)]:
		sim.build.place("foundation", c, 0, inv)
		sim.build.place("electric_heater", c, BuildGrid.Side.NORTH, inv)
	eq(sim.build.place("power_pole", Vector2i(5, -92), BuildGrid.Side.NORTH, inv), "", "a pole by the tower")
	sim.messages.clear()
	_steps(sim, 2.0)
	near(float(sim.power.external_spare.get("project:" + ID, -1.0)), 20.0, "the network has 20 W spare", 0.01)
	eq(sim.projects.state[ID]["progress"], 0.0, "20 W spare isn't enough")
	check(_project_noise(sim).is_empty(), "the pump is silent")
	sim.build.remove(sim.build.key_for("electric_heater", Vector2i(1, -87)), inv)
	_steps(sim, 2.0)
	check(sim.projects.state[ID]["progress"] > 0.0, "with 60 W spare the pump runs")
	near(float(_project_noise(sim).get("loudness", 0)), 85.0, "loudness 85")
	var gen_noise := sim.noise.continuous.filter(func(s: Dictionary) -> bool: return s["kind"] == "generator")
	eq(gen_noise.size(), 1, "the generator runs for it, noise on top")
	var net := sim.power.network_of(sim.build.key_for("generator", gen_cell))
	near(float(net["demand"]), 100.0, "the pump's 60 W count in the network's demand", 0.01)
	check(sim.messages.any(func(m: Dictionary) -> bool: return m["text"] == "The tower pump is running. Everything can hear it."), "the HUD line")
	_steps(sim, sim.clock.seconds_per_hour())
	check(sim.projects.is_done(ID), "phase 3 done: the tower is running")
	eq(sim.projects.done, [ID], "projects_done has water_tower")
	check(not sim.power.external.has("project:" + ID), "the pump stops drawing power")


func test_reward_triples_collectors_and_the_tap_runs_only_while_running() -> void:
	var sim := _sim()
	sim.player_pos = Vector3(0, 0, 0)
	var inv := Inventory.new()
	inv.give_all({"plank": 40, "nails": 40, "metal_plate": 20, "scrap_metal": 20})
	sim.build.place("foundation", Vector2i(3, 0), 0, inv)
	sim.build.place("rain_collector", Vector2i(3, 0), BuildGrid.Side.NORTH, inv)
	sim.build.place("foundation", Vector2i(5, 0), 0, inv)
	eq(sim.build.place("water_tap", Vector2i(5, 0), BuildGrid.Side.NORTH, inv), "Needs the water tower running", "no tap before the tower runs")
	sim.build.restore(sim.build.key_for("water_tap", Vector2i(5, 0)), {"id": "water_tap", "cell": Vector2i(5, 0),
			"side": BuildGrid.Side.NORTH, "hp": 60})  # one standing anyway (as if from a save): it stays dry
	_steps(sim, 7.0)
	var rc: Factory.Machine = sim.factory.machines[Vector2i(3, 0)]
	var tap: Factory.Machine = sim.factory.machines[Vector2i(5, 0)]
	eq(rc.output.get("dirty_water", 0), 0, "a rain collector takes 20 s before the tower runs")
	_steps(sim, 50.0)
	eq(tap.output.get("clean_water", 0), 0, "the tap is dry before the tower runs")
	eq(tap.status(), "Dry: the water tower isn't running", "and says so")
	check(not sim.noise.continuous.any(func(s: Dictionary) -> bool: return s["key"] == sim.build.key_for("water_tap", Vector2i(5, 0))), "a dry tap is silent")
	sim.projects.done.append(ID)
	rc.output.clear()
	rc.progress = 0.0
	rc.crafting = false
	_steps(sim, 7.0)
	eq(rc.output.get("dirty_water", 0), 1, "with the tower running: a rain collector fills in 6.7 s (3x)")
	near(sim.factory.season_speed(rc), 3.0, "three times its rate")
	_steps(sim, 31.0)
	check(int(tap.output.get("clean_water", 0)) >= 1, "the tap gives clean water")
	eq(sim.build.place("water_tap", Vector2i(3, 2), BuildGrid.Side.NORTH, inv), "Needs a foundation", "and a tap can be built now")
	sim.build.place("foundation", Vector2i(3, 2), 0, inv)
	eq(sim.build.place("water_tap", Vector2i(3, 2), BuildGrid.Side.NORTH, inv), "", "built: 4 scrap and 6 nails")
	sim.clock.day = 16  # winter: half-speed rain, still three times that
	_steps(sim, 0.1)
	near(sim.factory.season_speed(rc), 1.5, "in winter the boost stacks on the half rate")


func test_save_and_load_keep_phases_progress_and_reward() -> void:
	var sim := _sim()
	sim.projects.state[ID]["phase"] = 1
	sim.inventory.give_all({"wall_panel": 6, "nails": 8})
	sim.player_pos = tower + Vector3(-3, 0, 0)
	sim.project_deliver(ID)
	eq(sim.projects.missing(ID), {"nails": 12}, "part of phase 2 delivered")
	var d := SaveGame.to_dict(sim)
	eq(int(d["version"]), SaveGame.VERSION, "saved as the current version")
	var b := SimWorld.new(8.0)
	b.place_park(ParkPlan.generate(1), false)
	eq(SaveGame.apply(b, d), "", "loads")
	eq(b.projects.phase(ID), 1, "phase 2 still the one to do")
	eq(b.projects.missing(ID), {"nails": 12}, "the delivered panels and nails kept")
	# Mid-work, then finished.
	sim.inventory.give_all({"nails": 12})
	sim.project_deliver(ID)
	sim.project_start(ID)
	_steps(sim, sim.clock.seconds_per_hour() * 0.4)
	var c := SimWorld.new(8.0)
	c.place_park(ParkPlan.generate(1), false)
	SaveGame.apply(c, SaveGame.to_dict(sim))
	near(c.projects.state[ID]["progress"], sim.projects.state[ID]["progress"], "work progress kept", 1e-6)
	check(c.projects.is_working(ID), "still started: it carries on when you come back")
	c.player_pos = tower + Vector3(-3, 0, 0)
	_steps(c, sim.clock.seconds_per_hour() * 0.7)
	eq(c.projects.phase(ID), 2, "and finishes after loading")
	c.projects.state[ID]["phase"] = 3
	c.projects.done.append(ID)
	var e := SimWorld.new(8.0)
	e.place_park(ParkPlan.generate(1), false)
	SaveGame.apply(e, SaveGame.to_dict(c))
	check(e.projects.is_done(ID), "the reward is saved")
	_steps(e, 0.1)
	near(e.factory.rain_boost, 3.0, "rain collectors stay three times as fast after a load")
	check(e.factory.tap_on, "and taps run")


func test_project_screen_shows_the_next_phase() -> void:
	var sim := _sim()
	sim.inventory.give_all({"metal_plate": 3})
	sim.player_pos = tower + Vector3(-4, 0, 0)
	var screen := ProjectScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open(ID)
	check(screen.needs_text().contains("10 Metal plate"), "it shows phase 1's needs (%s)" % screen.needs_text())
	check(screen.needs_text().contains("you have 3"), "and what you have")
	check(screen._phases.text.contains("Phase 3: Run the pump") and screen._phases.text.contains("60 W"), "every phase listed")
	check(screen.button("Deliver") != null and screen.button("StartWork") != null, "Deliver and Start Work buttons")
	check(screen.button("StartWork").disabled, "Start Work waits for the items")
	screen.deliver()
	eq(sim.projects.missing(ID), {"metal_plate": 7}, "Deliver delivered")
	sim.projects.state[ID] = {"phase": 1, "delivered": {}, "progress": 0.0, "working": false}
	screen.refresh()
	check(screen.needs_text().contains("6 Wall panel") and screen.needs_text().contains("20 Nails"), "phase 2's needs (%s)" % screen.needs_text())
	sim.projects.state[ID]["delivered"] = {"wall_panel": 6, "nails": 20}
	screen.refresh()
	check(not screen.button("StartWork").disabled, "Start Work once it's all in")
	screen.start_work()
	check(sim.projects.is_working(ID), "Start Work started it")
	screen.close()
	screen.queue_free()
	await tree.process_frame
