extends "res://test/base_test.gd"
## F4 part 2 (the loop closes): belts feed the Hub's milestones; the rescue broadcast needs the mast powered and
## counts only powered hours; fences and the repair station draw power only when they have work; the dawn perk
## pick offers one perk per tree once a day, when it's safe.

const N := 0
const E := 1
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999, "gas_can": 99})
	return inv


func _run(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / TICK):
		sim.step()


## A world with a Hub at (40, 40) and a belt at (39, 40) running into it, no milestones done.
func _hub_world() -> SimWorld:
	var sim := SimWorld.new(12.0)
	sim.milestones.done.clear()
	eq(sim.build.place("hub", Vector2i(40, 40), N, _rich()), "", "a Hub")
	eq(sim.build.place("belt", Vector2i(39, 40), E, _rich()), "", "a belt running into it")
	return sim


func test_a_belt_into_the_hub_hands_in_milestone_parts() -> void:
	var sim := _hub_world()
	var belt: Factory.Belt = sim.factory.belts[Vector2i(39, 40)]
	belt.accept("plank")
	for i in roundi(1.5 / TICK):
		sim.factory.tick(TICK)
	eq(int(sim.milestones.delivered.get("salvage_rig", {}).get("plank", 0)), 1, "the plank went to the first open milestone")
	eq(belt.items.size(), 0, "and off the belt")
	eq(sim.stats.hub_belt, 1, "the session log counts it")
	belt.accept("radio")  # no open milestone wants one yet (the rescue's tier is locked)
	for i in roundi(1.5 / TICK):
		sim.factory.tick(TICK)
	eq(belt.items.size(), 1, "a part nobody needs stays on the belt")
	check(sim.stats.summary_lines().has("Belts handed the Hub 1 part."), "the session log says what the belts handed in")


func test_a_belt_can_finish_a_milestone() -> void:
	var sim := _hub_world()
	sim.milestones.delivered["salvage_rig"] = {"plank": 20, "scrap_metal": 20, "nails": 9}
	sim.messages.clear()
	sim.factory.belts[Vector2i(39, 40)].accept("nails")
	for i in roundi(1.5 / TICK):
		sim.factory.tick(TICK)
	check(sim.milestones.is_done("salvage_rig"), "the last nail by belt finishes it")
	check(sim.build.milestones.unlocked("salvager"), "and unlocks its machines")
	check(sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).begins_with("Salvage rig done!")), "with the usual message")
	eq(sim.milestones.take("nails"), "lumber_yard" if int(sim.milestones.missing("lumber_yard").get("nails", 0)) > 0 else "",
			"the next nail goes to the next open milestone that needs one, if any")
	sim.milestones.delivered.erase("sentry")
	eq(sim.milestones.take("metal_plate"), "lumber_yard", "plates: tier 1 first")


## A world at dusk with the rescue milestone done and a radio mast at (50, 50); `powered` adds a fuelled
## generator next to it.
func _mast_world(powered: bool, hour: float = 18.5) -> SimWorld:
	var sim := SimWorld.new(hour)
	sim.milestones.done.append(sim.milestones.final_id())
	eq(sim.build.place("radio_mast", Vector2i(50, 50), N, _rich()), "", "a radio mast")
	if powered:
		var stock := _rich()
		sim.build.place("foundation", Vector2i(51, 50), N, stock)
		eq(sim.build.place("generator", Vector2i(51, 50), N, stock), "", "a generator next door")
		sim.power.load_fuel(sim.build.key_for("generator", Vector2i(51, 50)), stock)
	sim.player_pos = Vector3(0, 0, 0)
	return sim


func test_the_broadcast_needs_power() -> void:
	var dark := _mast_world(false)
	_run(dark, 0.2)
	check(dark.start_broadcast(dark.mast_key()).begins_with("The mast needs"), "no power: it won't start")
	eq(dark.rescue_state, "", "still waiting")
	var sim := _mast_world(true)
	_run(sim, 0.2)
	check(sim.start_broadcast(sim.mast_key()).begins_with("Broadcasting!"), "with a generator beside it, it starts")
	_run(sim, 1.0)
	check(sim.broadcast_hours > 0.0, "the signal hours count up while it's powered")
	check(sim.power.network_of(sim.mast_key())["demand"] >= float(data.buildables["radio_mast"]["watts"]),
			"and the mast draws its watts from the generator")
	check(sim.noise.continuous.any(func(s: Dictionary) -> bool: return s["kind"] == "radio_mast"), "every zombie for miles hears it")


func test_no_power_no_signal_and_rescue_after_the_hours() -> void:
	var sim := _mast_world(false)
	sim.power.free = true
	sim.start_broadcast(sim.mast_key())
	_run(sim, 1.0)
	var before := sim.broadcast_hours
	sim.power.free = false  # the generator ran dry
	sim.messages.clear()
	_run(sim, 2.0)
	near(sim.broadcast_hours, before, "no power: the hours wait", 1e-6)
	check(not sim.noise.continuous.any(func(s: Dictionary) -> bool: return s["kind"] == "radio_mast"), "and it's silent")
	check(sim.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).contains("lost power")), "you're told the signal dropped")
	check(sim.broadcast_status().contains("NO POWER"), "the mast says so too")
	sim.power.free = true
	sim.broadcast_hours = float(data.milestones["broadcast_hours"]) - 0.01
	_run(sim, 2.0)
	check(sim.rescue_due >= 0.0, "enough hours: they heard you")
	eq(sim.rescue_state, "broadcasting", "but help comes at dawn, not now")
	near(fmod(sim.rescue_due, 24.0), float(data.milestones["rescue_hour"]), "at the next rescue hour", 1e-6)
	check(sim.rescue_due > sim.clock.day * 24.0 + sim.clock.time_of_day, "which is still ahead")
	sim.power.free = false  # power going after they answered doesn't matter
	sim.clock.time_of_day = 5.99
	sim.clock.day += 1
	_run(sim, 1.0)
	eq(sim.rescue_state, "rescued", "dawn: rescued")


func test_signal_hours_survive_saving_and_a_fallen_mast_loses_them() -> void:
	var sim := _mast_world(false)
	sim.power.free = true
	sim.start_broadcast(sim.mast_key())
	sim.broadcast_hours = 3.5
	var d := SaveGame.to_dict(sim)
	var back := SimWorld.new(12.0)
	SaveGame.apply(back, d)
	near(back.broadcast_hours, 3.5, "the signal hours load back", 1e-6)
	eq(back.rescue_state, "broadcasting", "still broadcasting")
	sim.build.remove(sim.mast_key(), Inventory.new())
	_run(sim, 0.2)
	eq(sim.rescue_state, "", "the mast fell: the broadcast is lost")
	eq(sim.broadcast_hours, 0.0, "and its hours with it")


func test_an_idle_mast_draws_nothing() -> void:
	var sim := _mast_world(true, 12.0)
	_run(sim, 1.0)
	eq(sim.power.network_of(sim.mast_key())["demand"], 0.0, "not broadcasting: no load on the generator")


func test_fences_draw_power_at_night_or_with_a_zombie_near() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_pos = Vector3(0, 0, 0)
	var stock := _rich()
	eq(sim.build.place("electric_fence", Vector2i(60, 60), N, stock), "", "a fence")
	var key := sim.build.key_for("electric_fence", Vector2i(60, 60), N)
	_run(sim, 0.2)
	eq(sim.power.wants.get(key, true), false, "by day with no zombie near, it wants no power")
	var z := sim.horde.spawn("shambler", Vector3(121, 0, 124))
	z.state = ZombieBrain.State.IDLE
	_run(sim, 0.1)
	eq(sim.power.wants.get(key, false), true, "a zombie within %d m arms it" % int(data.defense["fence"]["arm"]))
	z.pos = Vector3(160, 0, 160)
	_run(sim, 0.1)
	eq(sim.power.wants.get(key, true), false, "it went away: off again")
	sim.clock.time_of_day = 23.0
	_run(sim, 0.1)
	eq(sim.power.wants.get(key, false), true, "at night it's armed all the time")


func test_the_repair_station_draws_power_only_with_work() -> void:
	var sim := SimWorld.new(12.0)
	sim.player_pos = Vector3(0, 0, 0)
	var stock := _rich()
	sim.build.place("foundation", Vector2i(70, 70), N, stock)
	eq(sim.build.place("repair_station", Vector2i(70, 70), N, stock), "", "a repair station")
	sim.build.place("foundation", Vector2i(71, 70), N, stock)
	eq(sim.build.place("wall", Vector2i(71, 70), N, stock), "", "a wall beside it")
	var key := sim.build.key_for("repair_station", Vector2i(70, 70))
	var bin: Factory.Bin = sim.factory.bins[Vector2i(70, 70)]
	bin.put("wall_panel", 5)
	sim.power.free = true
	_run(sim, float(data.buildables["repair_station"]["interval"]) + 0.5)
	eq(sim.power.wants.get(key, true), false, "panels but nothing to fix: no power wanted")
	eq(bin.count, 5, "and no panel spent")
	var wall := sim.build.key_for("wall", Vector2i(71, 70), N)
	sim.build.pieces[wall]["hp"] = 100
	_run(sim, float(data.buildables["repair_station"]["interval"]) + 0.5)
	eq(int(sim.build.pieces[wall]["hp"]), 100 + int(data.defense["repair_station"]["hp_per_panel"]), "a damaged wall: it mends it")
	eq(bin.count, 4, "with one panel")


func test_the_perk_pick_waits_for_points_calm_and_safety() -> void:
	# P12: not once at dawn with nothing within 25 m (which, in a town full of zombies, never came: 24 points unspent
	# between Emmitt and Kaleb), but at any quiet moment.
	var sim := SimWorld.new(9.0)
	sim.player_pos = Vector3(0, 0, 0)
	check(not sim.perk_offer_ready(), "no points: nothing to offer")
	sim.skills.perk_points = 2
	check(sim.perk_offer_ready(), "points in daylight: offer it")
	var z := sim.horde.spawn("shambler", Vector3(10, 0, 0))
	check(not sim.perk_offer_ready(), "not with a zombie 10 m off")
	z.pos = Vector3(14, 0, 0)
	check(sim.perk_offer_ready(), "14 m off is far enough (it was 25)")
	z.pos = Vector3(10, 0, 0)
	z.hurt(9999.0)
	check(sim.perk_offer_ready(), "a dead one doesn't count")
	sim.swing()
	check(not sim.perk_offer_ready(), "not right after a swing")
	sim.clock.time_of_day += SimWorld.PERK_OFFER_CALM + 0.01
	check(sim.perk_offer_ready(), "a few seconds of calm later: yes")
	sim.perk_snooze(SimWorld.PERK_SNOOZE_LATER)
	check(not sim.perk_offer_ready(), "Later puts it off")
	eq(sim.stats.perk_picks_later, 1, "and the log counts it")
	sim.clock.time_of_day += SimWorld.PERK_SNOOZE_LATER - 1.0
	check(not sim.perk_offer_ready(), "still off an hour before")
	sim.clock.time_of_day += 1.01
	check(sim.perk_offer_ready(), "then back (%.2f h)" % sim.clock.time_of_day)
	sim.perk_snooze(SimWorld.PERK_SNOOZE_CLOSED, "zombie")
	eq(sim.stats.perk_picks_closed, 1, "a zombie closing it is counted apart")
	sim.clock.time_of_day += SimWorld.PERK_SNOOZE_CLOSED + 0.01
	check(sim.perk_offer_ready(), "and it comes back sooner")
	sim.clock.time_of_day = 23.0
	check(not sim.perk_offer_ready(), "not at night out in the open")
	sim.inventory.give_all({"plank": 100, "nails": 100})
	var N := BuildGrid.Side.NORTH
	for cell: Vector2i in [Vector2i(20, 20)]:
		eq(sim.build.place("foundation", cell, N, sim.inventory), "", "a shelter floor")
		eq(sim.build.place("bed", cell, N, sim.inventory), "", "a bed")
		for side: int in [BuildGrid.Side.NORTH, BuildGrid.Side.EAST, BuildGrid.Side.SOUTH]:
			eq(sim.build.place("wall", cell, side, sim.inventory), "", "a wall")
		eq(sim.build.place("door", cell, BuildGrid.Side.WEST, sim.inventory), "", "a door")
	sim.player_pos = Vector3(41, 0, 41)
	check(sim.guidance.is_sheltered(sim.build, sim.player_pos), "inside the shelter")
	check(sim.perk_offer_ready(), "at night indoors is a quiet moment too")
	sim.note_perk_offered()
	eq(sim.stats.perk_picks_offered, 1, "an offer is counted")
	# The snooze survives a save.
	sim.perk_snooze(3.0)
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	near(float(d["perk_snooze"]), sim.perk_snooze_until, "the snooze is saved")
	var b := SimWorld.new(9.0)
	b.loot.add("car_0", "car_trunk", Vector3(0, 0, -15))
	b.add_car("car_0")
	eq(SaveGame.apply(b, d), "", "loads")
	near(b.perk_snooze_until, sim.perk_snooze_until, "and comes back")


func test_the_prompted_tree_spends_points_and_snoozes() -> void:
	# P13: the quiet-moment pick opens the skill tree (SkillsScreen.open_prompt), not three cards.
	var sim := SimWorld.new(9.0)
	sim.skills.perk_points = 2
	var screen := SkillsScreen.new()
	tree.root.add_child(screen)
	screen.setup(sim)
	screen.open_prompt()
	check(screen.is_open() and screen.prompted, "open, prompted")
	var first := screen.hovered
	check(first != "" and sim.skills.can_spend(first) == "", "it points at a perk you can take (%s)" % first)
	screen.spend(first)
	eq(sim.skills.rank(first), 1, "a click buys that perk")
	eq(sim.skills.perk_points, 1, "with a point left")
	check(screen.is_open(), "points left: still open")
	screen.later()
	check(not screen.is_open(), "Later closes it")
	eq(sim.stats.perk_picks_later, 1, "and is counted")
	check(sim.perk_snooze_until > sim.clock_hours() + 1.0, "and puts it off a while")
	screen.free()
