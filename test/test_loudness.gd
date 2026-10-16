extends "res://test/base_test.gd"
## F5 (loudness as a puzzle, part 1): how far a sound carries each way round, walls included (the build ghost's
## rings); a soundproof wall stops twice the sound of a plain one; U fits a muffler and then a sound box over it;
## the dusk timer switches the machines on its power line off from dusk to dawn.

const N := 0
const E := 1
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999, "wall_panel": 99, "gas_can": 20})
	return inv


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## The radius pointing east (+X) and west (-X) in a heard_radii result.
func _east(radii: PackedFloat32Array) -> float:
	return radii[0]


func _west(radii: PackedFloat32Array) -> float:
	return radii[NoiseField.RADII / 2]


func test_open_air_radius_is_the_formula_turned_round() -> void:
	var sim := SimWorld.new(12.0)
	var radii := sim.noise.heard_radii(Vector3(101, 1, 101), 60.0, 14.0)
	eq(radii.size(), NoiseField.RADII, "one radius per direction")
	for r: float in radii:
		near(r, pow(10.0, 46.0 / 20.0), "60 loud, heard from 14: about 200 m every way", 0.01)
	check(NoiseField.heard_level(60.0, radii[3], 0) - 14.0 < 0.01, "at that distance it's right at the threshold")
	var loud := sim.noise.heard_radii(Vector3(101, 1, 101), 95.0, 14.0)
	near(loud[0], NoiseField.HEARD_MAX, "past HEARD_MAX it stops there (heard across the map)", 0.01)
	near(sim.noise.heard_radii(Vector3(101, 1, 101), 10.0, 14.0)[0], 0.0, "too quiet to hear at all: 0", 0.001)


func test_a_wall_dents_the_ring_and_a_soundproof_wall_twice() -> void:
	var sim := SimWorld.new(12.0)
	var at := Vector3(101, 1, 101)  # the middle of cell (50, 50)
	sim.build.place("foundation", Vector2i(50, 50), N, _rich())
	eq(sim.build.place("wall", Vector2i(50, 50), E, _rich()), "", "a wall on the east side")
	var walled := sim.noise.heard_radii(at, 60.0, 14.0)
	near(_east(walled), pow(10.0, 36.0 / 20.0), "east: one wall takes 10 off: about 63 m", 0.05)
	near(_west(walled), pow(10.0, 46.0 / 20.0), "west, nothing in the way: 200 m", 0.05)
	eq(sim.noise.walls_between(at, at + Vector3(10, 0, 0)), 1, "one wall for sound")
	sim.build.remove(sim.build.key_for("wall", Vector2i(50, 50), E), Inventory.new())
	eq(sim.build.place("soundproof_wall", Vector2i(50, 50), E, _rich()), "", "a soundproof wall instead")
	var proofed := sim.noise.heard_radii(at, 60.0, 14.0)
	near(_east(proofed), pow(10.0, 26.0 / 20.0), "it counts as two walls: 20 m", 0.05)
	eq(sim.noise.walls_between(at, at + Vector3(10, 0, 0)), 2, "two walls' worth for sound")
	eq(sim.noise.walls_between(at, at + Vector3(10, 0, 0), true), 1, "but one for sight")


func test_a_quiet_sound_stops_at_the_wall() -> void:
	var sim := SimWorld.new(12.0)
	var at := Vector3(101, 1, 101)
	sim.build.place("foundation", Vector2i(50, 50), N, _rich())
	sim.build.place("wall", Vector2i(50, 50), E, _rich())
	var r := sim.noise.heard_radii(at, 25.0, 20.0)  # open air: 1.8 m; the wall is 1 m away
	near(_east(r), 1.0, "it reaches the wall but nothing is heard past it", 0.01)
	var crossings := sim.noise.sound_crossings(at, at + Vector3(10, 0, 0))
	eq(crossings.size(), 1, "one wall on the way")
	near(crossings[0].x, 1.0, "1 m out", 0.01)


func test_the_heard_preview_night_day_and_cache() -> void:
	var sim := SimWorld.new(12.0)
	var at := Vector3(141, 1, 141)
	var pv := sim.heard_preview(at, 60.0)
	check(SimWorld.heard_far(pv["night"]) > SimWorld.heard_far(pv["day"]), "zombies hear it further at night")
	near(SimWorld.heard_far(pv["day"]), pow(10.0, (60.0 - sim.hearing_threshold(false)) / 20.0), "day: a shambler's day hearing", 0.05)
	check(is_same(sim.heard_preview(at, 60.0), pv), "asked again on the same spot: the cached answer")
	sim.build.place("foundation", Vector2i(70, 70), N, _rich())
	check(not is_same(sim.heard_preview(at, 60.0), pv), "a new piece: worked out again")
	sim.clock.day = 16  # winter: cold, still nights carry sound
	var winter := sim.heard_preview(at, 60.0)
	check(SimWorld.heard_far(winter["night"]) > SimWorld.heard_far(pv["night"]), "a winter night carries it further")
	near(SimWorld.heard_far(winter["day"]), SimWorld.heard_far(pv["day"]), "by day the season doesn't matter", 0.01)


func test_loudness_of_new_and_built_pieces() -> void:
	var sim := SimWorld.new(12.0)
	near(sim.loudness_of("smelter"), 60.0, "a new smelter: 60")
	near(sim.loudness_of("generator"), 80.0, "a new generator: 80")
	near(sim.loudness_of("nail_turret"), 35.0, "a turret: its shot")
	sim.skills.perks["dampened_gears"] = 1
	near(sim.loudness_of("smelter"), 60.0 - sim.skills.bonus("machine_quiet"), "Dampened Gears makes new machines quieter")
	sim.skills.perks.erase("dampened_gears")
	var stock := _rich()
	sim.build.place("foundation", Vector2i(60, 60), N, stock)
	sim.build.place("generator", Vector2i(60, 60), N, stock)
	var gen := sim.build.key_for("generator", Vector2i(60, 60))
	sim.inventory.give_all({"metal_plate": 50, "nails": 50, "wall_panel": 5})
	sim.fit_muffler(Vector2i(60, 60))
	near(sim.loudness_of("generator", gen), 65.0, "a muffled generator: 65")
	sim.fit_muffler(Vector2i(60, 60))
	near(sim.loudness_of("generator", gen), 80.0 - 15.0 - 12.0, "boxed in too: 53")


func test_the_sound_box_is_the_second_muffler() -> void:
	var sim := SimWorld.new(10.0)
	sim.power.free = true
	var stock := _rich()
	sim.build.place("foundation", Vector2i(0, 0), N, stock)
	sim.build.place("smelter", Vector2i(0, 0), E, stock)
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 0)]
	sim.inventory.give_all({"metal_plate": 50, "nails": 50, "wall_panel": 5})
	eq(sim.fit_muffler(Vector2i(0, 0)), "", "U: a muffler")
	near(sim.noise.machine_loudness(m), 45.0, "60 - 15")
	var panels := sim.inventory.count("wall_panel")
	eq(sim.fit_muffler(Vector2i(0, 0)), "", "U again: a sound box over it")
	check(m.boxed, "boxed in")
	near(sim.noise.machine_loudness(m), 33.0, "45 - 12 = 33")
	eq(sim.inventory.count("wall_panel"), panels - 2, "it costs two wall panels")
	near(m.time_scale, 1.15, "and slows it 5% more")
	eq(sim.fit_muffler(Vector2i(0, 0)), "Already muffled and boxed in", "nothing more to fit")
	var d := SaveGame.to_dict(sim)
	var back := SimWorld.new(10.0)
	SaveGame.apply(back, d)
	check(back.factory.machines[Vector2i(0, 0)].boxed, "the sound box saves and loads")
	var before := sim.inventory.count("wall_panel")
	sim.build.remove(sim.build.key_for("smelter", Vector2i(0, 0)), sim.inventory)
	eq(sim.inventory.count("wall_panel"), before + 2, "pulling the machine down gives the sound box back")


func test_a_boxed_generator_is_quieter_and_saves() -> void:
	var sim := SimWorld.new(10.0)
	var stock := _rich()
	sim.build.place("foundation", Vector2i(0, 0), N, stock)
	sim.build.place("generator", Vector2i(0, 0), N, stock)
	var gen := sim.build.key_for("generator", Vector2i(0, 0))
	sim.inventory.give_all({"metal_plate": 50, "nails": 50, "wall_panel": 5})
	sim.fit_muffler(Vector2i(0, 0))
	sim.fit_muffler(Vector2i(0, 0))
	check(sim.power.generators[gen]["boxed"], "the generator is boxed in")
	sim.power.generators[gen]["running"] = true
	var out := sim.power.noise_sources()
	near(float(out[0]["loudness"]), 53.0, "80 - 15 - 12 while it runs")
	var back := SimWorld.new(10.0)
	SaveGame.apply(back, SaveGame.to_dict(sim))
	check(bool(back.power.generators[gen]["boxed"]), "and loads boxed")


## A smelter next to a generator, with a dusk timer next to the smelter: one power network.
func _timer_world(hour: float) -> SimWorld:
	var sim := SimWorld.new(hour)
	var stock := _rich()
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
		sim.build.place("foundation", c, N, stock)
	eq(sim.build.place("generator", Vector2i(1, 0), N, stock), "", "a generator")
	sim.power.load_fuel(sim.build.key_for("generator", Vector2i(1, 0)), stock)
	eq(sim.build.place("smelter", Vector2i(0, 0), E, stock), "", "a smelter beside it")
	sim.factory.machines[Vector2i(0, 0)].input["scrap_metal"] = 99
	eq(sim.build.place("dusk_timer", Vector2i(-1, 0), N, stock), "", "a dusk timer (no milestone needed)")
	return sim


func test_the_dusk_timer_rests_the_factory_at_night() -> void:
	var sim := _timer_world(20.5)
	var timer := sim.build.key_for("dusk_timer", Vector2i(-1, 0))
	eq(sim.automation.sensors[timer]["action"], "machines_off", "it's built set to Machines off")
	_run(sim, 1.0)
	var smelter := sim.build.key_for("smelter", Vector2i(0, 0))
	check(not sim.power.switched_off.has(smelter), "before dusk the smelter runs")
	check(sim.noise.continuous.any(func(s: Dictionary) -> bool: return s["key"] == smelter), "and is heard")
	sim.clock.time_of_day = 22.0
	_run(sim, 1.0)
	check(sim.power.switched_off.has(smelter), "night: the smelter is switched off")
	check(not sim.power.switched_off.has(sim.build.key_for("generator", Vector2i(1, 0))), "the generator isn't (lights and turrets)")
	check(not sim.noise.continuous.any(func(s: Dictionary) -> bool: return s["key"] == smelter), "the smelter is silent")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("night, machines off")), "the base log says so")
	sim.clock.day += 1
	sim.clock.time_of_day = 6.0
	_run(sim, 1.0)
	check(not sim.power.switched_off.has(smelter), "morning: running again")
	check(sim.base_log.entries.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("morning, machines back on")), "and it says so")


func test_the_ghost_shows_the_heard_rings() -> void:
	var sim := SimWorld.new(12.0)
	var cam := Camera3D.new()
	var bc := BuildController.new()
	tree.root.add_child(cam)
	tree.root.add_child(bc)
	bc.setup(sim, cam, [])
	await tree.process_frame
	bc.active = true
	bc.select_id("smelter")
	bc.aim_cell = Vector2i(80, 80)
	bc._show_ghost("smelter")
	check(not bc.heard.is_empty(), "a smelter makes noise: rings")
	near(float(bc.heard["loudness"]), 60.0, "for loudness 60")
	check(bc.status_text().contains("Loudness 60: zombies hear it"), "the HUD says how far")
	bc.select_id("wall")
	bc._show_ghost("wall")
	check(bc.heard.is_empty(), "a wall is silent: no rings")
	check(not bc.status_text().contains("Loudness"), "and no line")
	bc.free()
	cam.free()


func test_heard_words() -> void:
	eq(Interactor.heard_words(199.6, 99.8), "zombies hear it 200 m off at night, 100 m by day", "metres, rounded")
	eq(Interactor.heard_words(NoiseField.HEARD_MAX, 250.0), "zombies hear it across the map at night, 250 m by day", "past the cap: across the map")
	eq(Interactor.heard_words(NoiseField.HEARD_MAX, NoiseField.HEARD_MAX), "zombies hear it across the map, day and night", "both: said once")


func test_the_new_pieces_are_in_the_data_and_menus() -> void:
	check(data.buildables.has("soundproof_wall") and data.buildables["soundproof_wall"]["kind"] == "wall", "a soundproof wall")
	eq(int(data.buildables["soundproof_wall"]["sound"]), 2, "worth two walls for sound")
	eq(int(data.buildables["wall"]["sound"]), 1, "a plain wall: one")
	eq(data.buildables["dusk_timer"]["sense"], "night", "the dusk timer senses the night")
	check(BuildController.PIECES.has("soundproof_wall") and BuildController.PIECES.has("dusk_timer"), "both can be built")
	check(data.defense["action_order"].has("machines_off"), "Machines off is a sensor action")
	eq(data.load_errors.size(), 0, "the data loads clean")


func test_the_heard_map_draws_the_rings_north_up() -> void:
	var pts := HeardMap.ring_points(PackedFloat32Array([1.0, 1.0, 1.0, 1.0]), Vector2(100, 100), 10.0)
	eq(pts.size(), 5, "four corners and back to the start")
	check(pts[0].is_equal_approx(Vector2(110, 100)), "east (+X) is to the right")
	check(pts[1].is_equal_approx(Vector2(100, 110)), "south (+Z) is down, so north is up")
	check(pts[4].is_equal_approx(pts[0]), "closed")

