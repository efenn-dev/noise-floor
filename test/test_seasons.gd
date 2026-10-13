extends "res://test/base_test.gd"
## M16: the calendar, sun hours by season, crops and rain by season, warmth (cold, roofs, stoves, heaters,
## the jacket, sleeping), sound carrying on cold nights, and saving warmth and stoves.

const TICK := SimWorld.TICK
const E := BuildGrid.Side.EAST
const OUT := Vector3(0, 0, 500)  # far from the town: outdoors, nothing around

var data := GameData.load_default()


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## A sim on `day` at `hour`, you standing outdoors at OUT with plenty of materials, no zombies.
func _sim(day: int, hour: float) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.clock.day = day
	sim.player_pos = OUT
	sim.inventory.give_all({"plank": 50, "nails": 100, "metal_plate": 50, "scrap_metal": 50, "gas_can": 5})
	return sim


func _put(sim: SimWorld, id: String, cell: Vector2i) -> String:
	sim.build.place("foundation", cell, 0, sim.inventory)
	eq(sim.build.place(id, cell, E, sim.inventory), "", "place %s at %s" % [id, cell])
	return sim.build.key_for(id, cell)


func _clock(day: int, hour: float) -> GameClock:
	var c := GameClock.new(hour)
	c.set_calendar(data.seasons)
	c.day = day
	return c


# --- Calendar and sun ---------------------------------------------------------------

func test_season_from_day_and_the_year_wraps() -> void:
	var want := {1: ["summer", 1], 7: ["summer", 7], 8: ["autumn", 1], 9: ["autumn", 2], 14: ["autumn", 7],
			15: ["winter", 1], 16: ["winter", 2], 21: ["winter", 7], 22: ["spring", 1], 28: ["spring", 7],
			29: ["summer", 1], 36: ["autumn", 1], 43: ["winter", 1], 57: ["summer", 1]}
	for d: int in want:
		var c := _clock(d, 12.0)
		eq(c.season(), want[d][0], "day %d is %s" % [d, want[d][0]])
		eq(c.season_day(), want[d][1], "day %d is day %d of its season" % [d, want[d][1]])
	eq(_clock(16, 12.0).season_name(), "Winter", "season name for the HUD")
	var plain := GameClock.new(12.0)
	plain.day = 16
	eq(plain.season(), "summer", "a clock with no calendar is always summer")
	var sim := SimWorld.new(8.0)
	eq(sim.clock.day, 1, "a new game starts on day 1...")
	eq(sim.clock.season(), "summer", "...in summer")
	sim.clock.day = 14
	sim.clock.time_of_day = 23.5
	_run(sim, 31.0)  # past midnight
	eq(sim.clock.day, 15, "midnight")
	eq(sim.clock.season(), "winter", "day 15 is the first day of winter")
	near(sim.clock.sunrise_hour, 7.5, "and the winter sun comes up at 07:30")


func test_sunrise_and_sunset_by_season() -> void:
	var hours := {1: [5.0, 21.0], 9: [6.0, 19.0], 16: [7.5, 17.5], 23: [6.0, 20.0]}
	for d: int in hours:
		var c := _clock(d, 12.0)
		near(c.sunrise_hour, hours[d][0], "%s sunrise" % c.season())
		near(c.sunset_hour, hours[d][1], "%s sunset" % c.season())
		c.time_of_day = (hours[d][0] + hours[d][1]) / 2.0
		near(c.daylight(), 1.0, "%s: the sun is highest halfway through its day" % c.season(), 0.001)
		c.time_of_day = hours[d][0] - 0.25
		check(c.is_night() and c.daylight() == 0.0, "%s: dark a quarter-hour before sunrise" % c.season())
		c.time_of_day = hours[d][1] - 0.25
		check(not c.is_night() and c.daylight() > 0.0, "%s: still light a quarter-hour before sunset" % c.season())
	var winter := _clock(16, 7.0)
	var summer := _clock(2, 7.0)
	check(winter.is_night() and not summer.is_night(), "07:00 is dark in winter, light in summer")
	winter.time_of_day = 18.0
	summer.time_of_day = 18.0
	check(winter.is_night() and not summer.is_night(), "18:00 is dark in winter, light in summer")


func test_solar_follows_the_season() -> void:
	for d: int in [2, 16]:
		var sim := _sim(d, 7.0)
		var panel := _put(sim, "solar_panel", Vector2i(0, 250))
		_put(sim, "electric_heater", Vector2i(1, 250))
		_run(sim, TICK)
		var supply: float = sim.power.network_of(panel)["supply"]
		if d == 2:
			check(supply > 0.0, "summer 07:00: the panel makes power (%.1f W)" % supply)
		else:
			near(supply, 0.0, "winter 07:00: still dark, no solar")


# --- Crops and rain -------------------------------------------------------------------

func _planter(sim: SimWorld) -> Factory.Machine:
	_put(sim, "planter", Vector2i(0, 250))
	var m: Factory.Machine = sim.factory.machines[Vector2i(0, 250)]
	m.input = {"seeds": 5, "dirty_water": 5}
	return m


func test_planters_freeze_in_winter_and_grow_faster_in_summer() -> void:
	var grow := float(data.recipes["grow_vegetables"]["time"])
	var winter := _sim(16, 12.0)
	var w := _planter(winter)
	_run(winter, grow * 2.0)
	eq(w.crafted, 0, "winter: nothing grows")
	check(w.frozen, "winter: the planter is frozen")
	check(w.status().begins_with("Frozen"), "it says Frozen (%s)" % w.status())
	for s: Dictionary in winter.noise.continuous:
		check(s["kind"] != "planter", "a frozen planter is silent")
	var progress := w.progress
	winter.clock.day = 22  # spring: it picks up where it stopped
	_run(winter, TICK)
	check(not w.frozen and w.progress > progress, "spring: it thaws and the timer runs on")
	var summer := _sim(2, 12.0)
	var s := _planter(summer)
	_run(summer, grow / 1.25 - 1.0)
	eq(s.crafted, 0, "summer: not quite yet")
	_run(summer, 1.2)
	eq(s.crafted, 1, "summer: a crop in %d s instead of %d (25%% faster)" % [roundi(grow / 1.25), roundi(grow)])
	var autumn := _sim(9, 12.0)
	var a := _planter(autumn)
	_run(autumn, grow / 1.25 + 0.2)
	eq(a.crafted, 0, "autumn: normal speed")
	_run(autumn, grow - grow / 1.25)
	eq(a.crafted, 1, "autumn: a crop in %d s" % roundi(grow))


func test_rain_collectors_by_season() -> void:
	var t := float(data.recipes["collect_rain"]["time"])
	var cases := {16: 0.5, 23: 1.5, 2: 1.0, 9: 1.0}
	for d: int in cases:
		var sim := _sim(d, 12.0)
		_put(sim, "rain_collector", Vector2i(0, 250))
		var m: Factory.Machine = sim.factory.machines[Vector2i(0, 250)]
		var each: float = t / cases[d]
		_run(sim, each - 0.5)
		eq(m.crafted, 0, "%s: not yet at %.1f s" % [sim.clock.season(), each - 0.5])
		_run(sim, 0.6)
		eq(m.crafted, 1, "%s: rainwater every %.1f s (x%.1f)" % [sim.clock.season(), each, cases[d]])


# --- Warmth -----------------------------------------------------------------------

func test_warmth_drains_outdoors_by_season() -> void:
	var want := {2: [0.0, 0.0], 9: [3.0, 5.0], 16: [12.0, 20.0], 23: [1.0, 2.0]}
	for d: int in want:
		for night: int in [0, 1]:
			var sim := _sim(d, 22.5 if night == 1 else 12.0)
			_run(sim, 60.0)  # one game-hour
			near(sim.player.warmth, 100.0 - want[d][night], "%s %s: -%d warmth a game-hour outdoors" % [
					sim.clock.season(), "night" if night == 1 else "day", want[d][night]], 0.05)


func test_warmth_refills_under_a_roof() -> void:
	var sim := _sim(16, 22.5)
	var plan := TownPlan.generate(1)
	sim.place_town(plan)
	var floor_key := ""
	for key: String in sim.build.pieces:
		if sim.build.pieces[key]["id"] == "town_floor":
			floor_key = key
			break
	sim.player_pos = sim.build.piece_center(floor_key) * Vector3(1, 0, 1)
	check(sim.is_indoors(sim.player_pos), "on a house floor counts as under a roof")
	check(not sim.is_indoors(OUT), "out in the open doesn't")
	sim.player.warmth = 50.0
	_run(sim, 60.0)
	near(sim.player.warmth, 70.0, "a winter night indoors: +20 a game-hour", 0.05)


func test_a_lit_stove_warms_you_and_burns_planks() -> void:
	var sim := _sim(16, 22.5)
	var key := _put(sim, "stove", Vector2i(2, 250))
	sim.inventory.remove("plank", sim.inventory.count("plank"))
	eq(sim.stove_interact(key), "No planks to burn", "nothing to burn yet")
	sim.inventory.add("plank", 1)
	eq(sim.stove_interact(key), "Loaded 1 plank", "E loads planks")
	sim.player.warmth = 20.0
	check(Climate._flat(sim.build.piece_center(key), OUT) <= 6.0, "you stand within 6 m of it")
	_run(sim, 30.0)
	check(sim.climate.stoves[key]["lit"], "it's burning")
	near(sim.player.warmth, 50.0, "by a lit stove: +60 a game-hour, even outdoors on a winter night", 0.1)
	var heard := false
	for s: Dictionary in sim.noise.continuous:
		if s["key"] == key:
			heard = true
			near(s["loudness"], 15.0, "a lit stove crackles at loudness 15")
	check(heard, "it's a continuous noise source")
	_run(sim, 89.0)  # 119 s: just under two game-hours on one plank
	check(sim.climate.stoves[key]["lit"], "one plank burns for two game-hours")
	_run(sim, 1.5)
	check(not sim.climate.stoves[key]["lit"], "then it goes out")
	near(sim.climate.hours_left(key), 0.0, "empty")
	for s: Dictionary in sim.noise.continuous:
		check(s["key"] != key, "a cold stove is silent")
	var w := sim.player.warmth
	_run(sim, 6.0)
	check(sim.player.warmth < w, "with the stove out the cold comes back")
	sim.inventory.add("plank", 20)
	eq(sim.stove_interact(key), "Loaded 10 planks", "it holds 10")
	eq(sim.stove_interact(key), "The stove is full", "and no more")
	_run(sim, 60.0 * 5.0)
	near(sim.climate.hours_left(key), 15.0, "five game-hours later: 15 of its 20 hours left", 0.05)
	sim.build.remove(key, sim.inventory)
	var far := _sim(16, 22.5)
	far.player_pos = OUT + Vector3(30, 0, 0)
	var k2 := _put(far, "stove", Vector2i(2, 250))
	far.stove_interact(k2)
	_run(far, 60.0)
	near(far.player.warmth, 80.0, "30 m from a lit stove the winter night still takes 20", 0.05)


func test_removing_a_stove_gives_its_planks_back() -> void:
	var sim := _sim(16, 12.0)
	var key := _put(sim, "stove", Vector2i(2, 250))
	sim.stove_interact(key)
	_run(sim, TICK)
	var before := sim.inventory.count("plank")
	var waiting: int = sim.climate.stoves[key]["planks"]
	sim.build.remove(key, sim.inventory)
	eq(sim.inventory.count("plank") - before, waiting + int(data.buildables["stove"]["cost"].get("plank", 0)),
			"the planks still waiting come back (the burning one doesn't)")


func test_the_electric_heater_needs_power() -> void:
	var sim := _sim(16, 22.5)
	var heater := _put(sim, "electric_heater", Vector2i(2, 250))
	sim.player_pos = OUT + Vector3(2, 0, 0)  # 3 m from it
	sim.player.warmth = 50.0
	_run(sim, 6.0)
	check(not sim.climate.heater_on(heater), "no power: off")
	check(sim.player.warmth < 50.0, "and no help against the cold")
	var gen := _put(sim, "generator", Vector2i(3, 250))
	sim.power.load_fuel(gen, sim.inventory)
	var w := sim.player.warmth
	_run(sim, 6.0)
	check(sim.climate.heater_on(heater), "on a generator's network: on")
	near(sim.player.warmth, w + 6.0, "within 5 m of it: +60 a game-hour", 0.1)
	near(sim.power.network_of(heater)["demand"], 40.0, "it draws 40 W")
	for s: Dictionary in sim.noise.continuous:
		check(s["key"] != heater, "the heater itself is silent")
	sim.player_pos = OUT + Vector3(-1, 0, 0)  # 6 m away
	var w2 := sim.player.warmth
	_run(sim, 6.0)
	check(sim.player.warmth < w2, "6 m away it doesn't reach you")


func test_the_jacket_slows_the_cold() -> void:
	var sim := _sim(16, 12.0)
	var jacket := sim.gear.make("jacket", "civilian", "white")
	sim.gear.pieces.append(jacket)
	eq(sim.equip_gear(jacket["uid"]), "Equipped Jacket", "wear a jacket")
	var bonus := sim.skills.bonus("warmth")
	check(bonus > 0.0, "it gives warmth (%.2f)" % bonus)
	_run(sim, 60.0)
	near(sim.player.warmth, 100.0 - 12.0 * (1.0 - bonus), "a winter hour outdoors takes %.1f, not 12" % (12.0 * (1.0 - bonus)), 0.05)
	check("cold gets to you 30% slower" in "
".join(sim.gear.stat_lines(jacket)), "its card says so")
	var c := Climate.new(data, BuildGrid.new(data), null)
	near(c.warmth_rate(data.seasons["seasons"]["winter"], true, false, false, false, 5.0), -20.0 * (1.0 - 0.8),
			"gear can cut the cold by at most 80%")


func test_cold_effects_at_30_and_10() -> void:
	var warm := _sim(2, 12.0)
	var cold := _sim(2, 12.0)
	cold.player.warmth = 25.0
	for sim: SimWorld in [warm, cold]:
		sim.player.stamina = 50.0
	_run(warm, 3.0)
	_run(cold, 3.0)
	near(cold.player.stamina - 50.0, (warm.player.stamina - 50.0) * 0.5, "below 30: stamina comes back at half speed", 0.2)
	near(cold.player.warmth, 25.0, "(summer: no drain outdoors)")
	near(cold.player.health, 100.0, "cold, not freezing: no damage")
	check(_said(cold, "You're cold"), "\"You're cold\"")
	check(not _said(warm, "cold"), "nothing said when warm")
	cold.messages.clear()
	_run(cold, 30.0)
	check(not _said(cold, "cold"), "said at most once a game-hour")
	_run(cold, 31.0)
	check(_said(cold, "You're cold"), "and again the next game-hour")
	var freezing := _sim(2, 12.0)
	freezing.player.warmth = 5.0
	_run(freezing, 0.1)
	check(_said(freezing, "You're freezing"), "\"You're freezing\"")
	_run(freezing, 19.8)
	near(freezing.player.health, 100.0, "below 10: not yet at 19.9 s")
	_run(freezing, 0.2)
	near(freezing.player.health, 99.0, "1 health every 20 s")
	_run(freezing, 20.0)
	near(freezing.player.health, 98.0, "and again")
	eq(freezing.player.last_cause, "cold", "the cold is what hurt you")
	eq(RunStats.cause_text("cold"), "froze to death", "the session log says so")


func _said(sim: SimWorld, text: String) -> bool:
	for m: Dictionary in sim.messages:
		if text in m["text"]:
			return true
	return false


func test_sleeping_holds_warmth() -> void:
	var sim := _sim(16, 22.5)
	sim.player.energy = 10.0
	sim.player.warmth = 60.0
	sim.player.sleep()
	_run(sim, 60.0)
	check(sim.player.asleep, "still asleep")
	near(sim.player.warmth, 60.0, "asleep in a bed on a winter night: warmth doesn't fall")
	sim.player.wake()
	_run(sim, 60.0)
	near(sim.player.warmth, 40.0, "awake, it does")


# --- Sound on cold nights ---------------------------------------------------------

func test_sound_carries_farther_on_cold_nights() -> void:
	var want := {[16, 22.5]: 6.0, [9, 22.5]: 3.0, [2, 22.5]: 0.0, [16, 12.0]: 0.0, [23, 22.5]: 0.0, [2, 12.0]: 0.0}
	for k: Array in want:
		var sim := _sim(k[0], k[1])
		_run(sim, TICK)
		near(sim.noise.carry_bonus, want[k], "%s %s: +%d dB" % [sim.clock.season(), "night" if k[1] > 20.0 else "day", want[k]])
		near(sim.noise.level(60.0, 10.0, 1), NoiseField.heard_level(60.0, 10.0, 1) + want[k], "level() adds it")
	# A zombie on a night: a sound 3 dB under its hearing at its spot is heard in winter, not in summer.
	for d: int in [2, 16]:
		var sim := _sim(d, 22.5)
		_run(sim, TICK)
		var z := sim.horde.spawn("shambler", Vector3(0, 0, -300))
		var threshold := z.hearing(true)
		var dist := 20.0
		var loud := threshold - 3.0 + 20.0 * log(dist) / log(10.0)
		sim.noise.emit(z.pos + Vector3(dist, 0, 0), loud, "test")
		_run(sim, 0.6)
		if d == 16:
			eq(z.state, ZombieBrain.State.INVESTIGATE, "winter night: the zombie hears it")
		else:
			check(z.state != ZombieBrain.State.INVESTIGATE, "summer night: it doesn't")
	# The Director's heat from the same machine is higher on a winter night.
	var gains := []
	for d: int in [2, 16]:
		var sim := _sim(d, 22.5)
		sim.power.free = true
		var m := _put(sim, "smelter", Vector2i(0, 250))
		sim.factory.machines[Vector2i(0, 250)].input["scrap_metal"] = 20
		_run(sim, 2.0)
		gains.append(sim.director.gain_now(sim.noise, true))
	check(gains[1] > gains[0], "the Director hears more on a winter night (%.2f > %.2f)" % [gains[1], gains[0]])


# --- Saves ------------------------------------------------------------------------

func test_save_keeps_warmth_and_stove_fuel() -> void:
	var sim := _sim(16, 20.0)
	var key := _put(sim, "stove", Vector2i(2, 250))
	sim.stove_interact(key)
	_run(sim, 45.0)
	sim.player.warmth = 42.5
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	eq(int(d["version"]), 11, "saves are version 11")
	var b := SimWorld.new(8.0)
	eq(SaveGame.apply(b, d), "", "loads")
	near(b.player.warmth, 42.5, "warmth kept")
	eq(b.climate.stoves[key]["planks"], sim.climate.stoves[key]["planks"], "planks waiting kept")
	near(b.climate.stoves[key]["fuel"], sim.climate.stoves[key]["fuel"], "the burning plank's time kept", 0.001)
	eq(b.clock.season(), "winter", "the day comes back, and the season with it")
	near(b.clock.sunrise_hour, 7.5, "winter sun hours")


func test_version_10_save_loads_warm_with_empty_stoves() -> void:
	var d := SaveGame.read("res://test/fixtures/save_v10.json")
	eq(int(d.get("version", 0)), 10, "the fixture is a version-10 save (written by the Q2 code)")
	var sim := SimWorld.new(8.0, null, int(d["seed"]))
	eq(SaveGame.apply(sim, d), "", "loads cleanly")
	near(sim.player.warmth, 100.0, "full warmth")
	eq(sim.climate.stoves.size(), 0, "no stoves (it had none)")
	eq(sim.build.pieces.size(), d["pieces"].size(), "every piece")
	eq(sim.clock.day, 3, "day 3")
	eq(sim.power.generators.size(), 1, "its generator")
	for v in range(2, 11):
		var old := SaveGame.read("res://test/fixtures/save_v%d.json" % v)
		var s := SimWorld.new(8.0, null, int(old.get("seed", 1)))
		eq(SaveGame.apply(s, old), "", "the version-%d fixture still loads" % v)
		near(s.player.warmth, 100.0, "v%d: full warmth" % v)


# --- Data -------------------------------------------------------------------------

func test_seasons_data_is_checked() -> void:
	eq(data.validate().size(), 0, "shipped data validates")
	eq(data.seasons["order"], ["summer", "autumn", "winter", "spring"], "the year's order")
	eq(int(data.seasons["days_per_season"]), 7, "7 days a season")
	var bad := GameData.load_default()
	bad.seasons = data.seasons.duplicate(true)
	bad.seasons["seasons"]["winter"]["sunrise"] = 19.0
	bad.seasons["seasons"]["autumn"]["crop_speed"] = -1.0
	bad.seasons["warmth"]["freezing_at"] = 40
	bad.seasons["stove"]["radius"] = 0
	bad.seasons["order"] = ["summer", "autumn", "winter"]
	var text := " | ".join(bad.validate())
	check("sunrise < sunset" in text, "flags winter's sun hours")
	check("'crop_speed' of 0 or more" in text, "flags a negative crop speed")
	check("freezing_at must be below cold_at" in text, "flags warmth thresholds out of order")
	check("stove needs a positive 'radius'" in text, "flags the stove radius")
	check("four seasons" in text, "flags a missing season")
	var none := GameData.load_default()
	none.seasons = {}
	check("no seasons data" in " | ".join(none.validate()), "flags missing seasons.json")
