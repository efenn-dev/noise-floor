extends "res://test/base_test.gd"
## F4 (the loop closes): a louder base draws bigger waves; the Press makes every turret's ammo (rifle rounds too);
## turrets count what fed them and what they killed; the nail turret is there from the start; "Defend your base"
## leads from a turret to a factory that feeds it, and the session log says what the turrets did.

const N := 0
const E := 1
const TICK := SimWorld.TICK
var data := GameData.load_default()


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func _wave(loudness: float) -> Dictionary:
	var sim := SimWorld.new(23.0)  # night: hordes
	sim.director.heat = 120.0
	sim.noise.continuous = [{"pos": Vector3(0, 1, -20), "loudness": loudness, "key": "", "kind": "test"}]
	sim.director._gain_timer = 0.0
	sim.director._check = 0.0
	return sim.director.tick(TICK, sim.noise, true, sim.horde)


func test_a_louder_base_draws_bigger_waves() -> void:
	var d := Director.new(data, 1)
	d.gain = 0.0
	near(d.loud_multiplier(), 1.0, "a quiet base: waves as before")
	d.gain = float(data.noise["director"]["loud_wave_gain"])
	near(d.loud_multiplier(), 2.0, "loud enough: twice the size")
	d.gain = 99.0
	near(d.loud_multiplier(), float(data.noise["director"]["loud_wave_max"]), "but never more than loud_wave_max")
	var quiet := _wave(40.0)
	var loud := _wave(85.0)
	check(not quiet.is_empty() and not loud.is_empty(), "both send a horde")
	near(float(quiet["loud"]), 1.0, "a quiet machine adds nothing")
	check(float(loud["loud"]) > 1.5, "an unwalled loud one makes the horde much bigger (x%.2f)" % float(loud["loud"]))
	check(int(loud["size"]) > int(quiet["size"]), "%d zombies instead of %d" % [loud["size"], quiet["size"]])


func test_the_press_makes_every_turrets_ammo() -> void:
	var press: Dictionary = data.buildables["press"]
	for t: String in ["nail_turret", "crossbow_turret", "rifle_turret"]:
		var ammo: String = data.buildables[t]["ammo"]
		var made := false
		for r: String in press["recipes"]:
			made = made or (data.recipes[r]["out"] as Dictionary).has(ammo)
		check(made, "a Press can make %s for the %s" % [ammo, t])
	var f := Factory.new(data)
	var m := f.add_machine("press", Vector2i(0, 0), E)
	f.set_recipe(m, "press_rounds")
	m.input["ammo_casing"] = 10
	m.input["scrap_metal"] = 1
	for i in roundi(4.2 / TICK):
		f.tick(TICK)
	eq(m.output.get("ammo_standard", 0), 10, "ten casings and some scrap make ten rifle rounds")


func test_turrets_count_what_fed_them_and_their_kills() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	sim.build.place("foundation", Vector2i(30, 30), N, _rich())
	eq(sim.build.place("nail_turret", Vector2i(30, 30), N, _rich()), "", "a nail turret")
	sim.build.place("belt", Vector2i(29, 30), E, _rich())
	var t: Factory.Turret = sim.factory.turrets[Vector2i(30, 30)]
	sim.factory.belts[Vector2i(29, 30)].accept("nails")
	for i in roundi(1.5 / TICK):
		sim.factory.tick(TICK)
	eq(t.fed, 1, "a belt fed it a nail")
	sim.factory.hand_interact(Vector2i(30, 30), _rich())
	eq(t.fed, 1, "your hands don't count")
	var z := sim.horde.spawn("shambler", Vector3(61, 0, 56))
	z.hp = 10.0
	sim.player_pos = Vector3(0, 0, 0)
	for i in 40:
		sim.step()
	check(z.is_dead(), "the turret shot the zombie in front of it")
	eq(t.kills, 1, "and counts the kill")
	check(sim.stats.turret_shots >= 1 and sim.stats.turret_kills == 1, "so does the session log (%d shots)" % sim.stats.turret_shots)
	check(sim.stats.turret_fed, "which knows a belt fed one")
	var lines := "\n".join(sim.stats.summary_lines())
	check(lines.contains("Turrets fired") and lines.contains("fed one"), "the session log says so")


func test_the_nail_turret_is_there_from_the_start() -> void:
	var sim := SimWorld.new(12.0)
	sim.milestones.done.clear()  # a real new game
	sim.build.place("foundation", Vector2i(30, 30), N, _rich())
	eq(sim.build.can_place("nail_turret", Vector2i(30, 30), N, _rich()), "", "no milestone needed for a nail turret")
	check(sim.build.can_place("hopper", Vector2i(31, 30), N, _rich()).begins_with("Unlock it at the Hub"), "the hopper still comes with Sentry")


func test_defend_your_base_leads_from_a_turret_to_a_fed_one() -> void:
	var sim := SimWorld.new(12.0)
	sim.power.free = true
	var g := sim.guidance
	g.active = true
	g.completed = false
	eq(g.tick_defend(sim.clock, sim.build, sim.factory), "", "not before the first night's goals are done")
	g.completed = true
	var msg := g.tick_defend(sim.clock, sim.build, sim.factory)
	check(g.defend_active and msg.begins_with("New goal: defend your base"), "then it starts (%s)" % msg)
	eq(g.defend_step(sim.build), 0, "first: build a turret")
	sim.build.place("foundation", Vector2i(30, 30), N, _rich())
	sim.build.place("nail_turret", Vector2i(30, 30), N, _rich())
	msg = g.tick_defend(sim.clock, sim.build, sim.factory)
	check(msg.begins_with("Turret built"), "built: next, ammo from a Press (%s)" % msg)
	sim.build.place("foundation", Vector2i(32, 30), N, _rich())
	sim.build.place("press", Vector2i(32, 30), E, _rich())
	sim.factory.machines[Vector2i(32, 30)].crafted = 1  # it made a batch of nails
	msg = g.tick_defend(sim.clock, sim.build, sim.factory)
	check(msg.begins_with("Ammo made"), "nails made: next, a belt (%s)" % msg)
	sim.factory.turrets[Vector2i(30, 30)].fed = 3
	msg = g.tick_defend(sim.clock, sim.build, sim.factory)
	check(msg.begins_with("Fed by belt"), "fed: next, a night (%s)" % msg)
	eq(g.defend_step(sim.build), 3, "on the last goal")
	var d := g.to_dict()
	var back := Guidance.new()
	back.load_dict(JSON.parse_string(JSON.stringify(d)))
	eq(back.defend_step(sim.build), 3, "saved and loaded, still on the last goal")
	sim.clock.time_of_day = 22.0
	eq(g.tick_defend(sim.clock, sim.build, sim.factory), "", "night falls")
	sim.factory.turrets[Vector2i(30, 30)].kills += 1
	sim.clock.time_of_day = 7.0
	msg = g.tick_defend(sim.clock, sim.build, sim.factory)
	check(g.defend_done and msg.begins_with("Your base defends itself"), "a kill in the dark and the turret at dawn: done (%s)" % msg)
	eq(g.tick_defend(sim.clock, sim.build, sim.factory), "", "and it stays done")
	var old := Guidance.new()  # a game from before the guidance
	var sim2 := SimWorld.new(12.0)
	eq(old.tick_defend(sim2.clock, sim2.build, sim2.factory), "", "an old game on day 1: not yet")
	sim2.clock.day = 2
	check(old.tick_defend(sim2.clock, sim2.build, sim2.factory) != "" and old.defend_active, "from day 2 it starts there too")


func test_the_objectives_panel_shows_defend_your_base() -> void:
	var sim := SimWorld.new(12.0)
	sim.guidance.active = true
	sim.guidance.completed = true
	sim.guidance.tick_defend(sim.clock, sim.build, sim.factory)
	var panel := ObjectivesPanel.new()
	tree.root.add_child(panel)
	panel.setup(sim)
	panel.force_visible = true
	panel.refresh()
	check(panel.visible, "it shows")
	check(panel.text().contains("DEFEND YOUR BASE") and panel.text().contains("Build a nail turret"), "the second chapter's goals")
	panel.queue_free()
	await tree.process_frame
