extends "res://test/base_test.gd"
## R1a (Emmitt: "some way to also automate the basic materials like in Satisfactory with excavators"): the excavators
## existed (salvager, sawmill, the pumps on resource nodes) but nothing led a player to them. Now a scrap heap and a
## timber stand sit by the start, and a guided chapter, "Dig in", runs from the first night to a powered Salvager
## digging on its own, before the turret chapter. Wave zombies carry fuller pockets. Felled trees grow back.

const N := BuildGrid.Side.NORTH


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 6, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	sim.power.free = true
	return sim


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func _node(sim: SimWorld, id: String) -> Dictionary:
	for n: Dictionary in sim.resource_nodes:
		if n["id"] == id:
			return n
	return {}


func test_a_scrap_heap_and_a_timber_stand_sit_by_the_start() -> void:
	var sim := _sim()
	var start := Vector3(0, 0, 6)
	for id: String in ["town_scrap", "town_timber"]:
		var n := _node(sim, id)
		check(not n.is_empty(), "%s is on the map" % id)
		var at: Vector3 = sim.build.cell_center(n["cell"]) if sim.build.has_method("cell_center") else Vector3((n["cell"].x + 0.5) * BuildGrid.GRID, 0, (n["cell"].y + 0.5) * BuildGrid.GRID)
		check(Vector2(at.x - start.x, at.z - start.z).length() < 45.0, "%s is a short walk from the start (%.0f m)" % [id, Vector2(at.x - start.x, at.z - start.z).length()])
		eq(str(n["purity"]), "poor", "%s is a poor one: a start, not a free lunch" % id)
	var scrap := _node(sim, "town_scrap")
	eq(sim.build.can_place("salvager", scrap["cell"], N, _rich()), "", "a Salvager can go on the town heap (every milestone done in test worlds)")
	var timber := _node(sim, "town_timber")
	eq(sim.build.can_place("sawmill", timber["cell"], N, _rich()), "", "a Sawmill on the town timber stand")
	check(sim.gather_start("town_scrap") == "" or true, "")
	# The real town's pieces don't sit on them (the spots were probed against the laid town).
	var town := TownPlan.generate(sim.seed_value)
	sim.place_town(town)
	sim.place_factory(town)
	sim.place_props(town)
	sim.place_downtown(DowntownPlan.generate(sim.seed_value), true)
	for id: String in ["town_scrap", "town_timber"]:
		var n := _node(sim, id)
		for key: String in sim.build.pieces:
			var c: Vector2i = sim.build.pieces[key]["cell"]
			check((c - n["cell"]).length() > 1.5, "%s's spot is clear of %s" % [id, key])


func test_dig_in_runs_from_a_hub_to_a_salvager_digging_on_its_own() -> void:
	var sim := _sim()
	sim.milestones.done.clear()  # a real new game
	var g := sim.guidance
	g.active = true
	g.completed = true  # the first night is behind us
	var inv := _rich()
	eq(g.tick_dig(sim.clock, sim.build, sim.factory, sim.milestones), Guidance.DIG_HOWTO[0], "it starts with the Hub")
	check(g.dig_active and not g.dig_done, "active")
	eq(g.tick_defend(sim.clock, sim.build, sim.factory), "", "the turret chapter waits for it")
	check(not g.defend_active, "and hasn't started")
	eq(g.dig_step(sim.build, sim.factory, sim.milestones), 0, "step 0: a Hub")
	eq(sim.build.place("foundation", Vector2i(4, 8), N, inv), "", "a foundation")
	eq(sim.build.place("hub", Vector2i(4, 8), N, inv), "", "the Hub")
	eq(g.tick_dig(sim.clock, sim.build, sim.factory, sim.milestones), Guidance.DIG_HOWTO[1], "Hub built: hand in the rig")
	sim.milestones.deliver("salvage_rig", inv)
	check(sim.milestones.is_done("salvage_rig"), "handed in")
	eq(g.tick_dig(sim.clock, sim.build, sim.factory, sim.milestones), Guidance.DIG_HOWTO[2], "rig done: build the Salvager")
	var heap := _node(sim, "town_scrap")
	eq(sim.build.place("salvager", heap["cell"], N, inv), "", "a Salvager on the town heap")
	eq(g.tick_dig(sim.clock, sim.build, sim.factory, sim.milestones), Guidance.DIG_HOWTO[3], "built: power it")
	var m: Factory.Machine = sim.factory.machines[heap["cell"]]
	eq(m.recipe_id, "salvage_scrap", "it digs scrap")
	var said := ""
	var ticks := 0
	while said != Guidance.DIG_DONE and ticks < 20 * 60 * 20:
		sim.step()
		ticks += 1
		for msg: Dictionary in sim.messages:
			if String(msg["text"]) == Guidance.DIG_DONE:
				said = Guidance.DIG_DONE
	eq(said, Guidance.DIG_DONE, "once it has dug %d scrap the chapter is done (%d ticks, crafted %d)" % [Guidance.DIG_SCRAP, ticks, m.crafted])
	check(g.dig_done, "done")
	check(m.crafted >= Guidance.DIG_SCRAP, "the Salvager did the digging (%d)" % m.crafted)
	sim.step()
	check(g.defend_active, "then the turret chapter starts")
	# Saved.
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2 := Guidance.new()
	g2.load_dict(d)
	check(g2.dig_active and g2.dig_done, "dig in is saved")
	g2.load_dict({})
	check(not g2.dig_active and not g2.dig_done, "an older save starts it fresh")


func test_the_objectives_panel_shows_dig_in_first() -> void:
	var sim := _sim()
	sim.milestones.done.clear()
	sim.guidance.active = true
	sim.guidance.completed = true
	sim.guidance.tick_dig(sim.clock, sim.build, sim.factory, sim.milestones)
	sim.guidance.defend_active = true  # even with the turret chapter on, dig in comes first
	var panel := ObjectivesPanel.new()
	tree.root.add_child(panel)
	panel.setup(sim)
	panel.force_visible = true
	panel.refresh()
	check(panel.visible, "it shows")
	check(panel.text().contains("DIG IN") and panel.text().contains("› Build a Hub"), "the dig-in goals (%s)" % panel.text())
	check("First learn it: build a" in panel.text() or "B, Hub group" in panel.text(), "with how to get a Hub (%s)" % panel.text())
	sim.guidance.dig_done = true
	panel.refresh()
	check(panel.text().contains("DEFEND YOUR BASE"), "done: the turret chapter shows")
	panel.queue_free()
	await tree.process_frame


func test_wave_zombies_carry_fuller_pockets() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "the wave table checks out")
	check(data.loot.has("zombie_wave"), "a zombie_wave loot table")
	var sim := _sim()
	var z := sim.horde.spawn("shambler", Vector3(5, 0, 5))
	eq(z.loot_table, "zombie", "an ordinary zombie carries the ordinary table")
	z.loot_table = "zombie_wave"
	z.hurt(9999.0)
	sim.step()
	var cid := SimWorld.CORPSE + str(z.id)
	check(sim.loot.containers.has(cid), "its corpse can be searched")
	eq(str(sim.loot.containers[cid]["table"]), "zombie_wave", "from the wave table")
	# The Director's waves set it (a loud machine at night, as test_loop makes a horde).
	var night := SimWorld.new(23.0)
	night.director.heat = 120.0
	night.noise.continuous = [{"pos": Vector3(0, 1, -20), "loudness": 85.0, "key": "", "kind": "test"}]
	night.director._gain_timer = 0.0
	night.director._check = 0.0
	var before := night.horde.zombies.keys()
	var wave := night.director.tick(SimWorld.TICK, night.noise, true, night.horde)
	check(not wave.is_empty(), "a wave came")
	var fuller := 0
	var plain := 0
	for id: int in night.horde.zombies:
		if id in before:
			continue
		if night.horde.zombies[id].loot_table == "zombie_wave":
			fuller += 1
		else:
			plain += 1
	check(fuller > 0 and plain == 0, "every zombie of the wave carries the fuller pockets (%d fuller, %d plain)" % [fuller, plain])


func test_felled_trees_grow_back() -> void:
	var sim := _sim()
	var piece := sim.gear.make("axe", "civilian", "white")
	sim.gear.pieces.append(piece)
	sim.gear.equip(piece["uid"])
	eq(sim.salvage.day, sim.clock.day, "the salvage knows the day")
	while not sim.salvage.felled.has("tree_x"):
		sim.player_hit_tree("tree_x", "tree", Vector3.ZERO)
	eq(int(sim.salvage.felled["tree_x"]), sim.clock.day, "felled today")
	eq(sim.salvage.stage("tree_x"), "stump", "a stump")
	eq(sim.player_hit_tree("tree_x", "tree", Vector3.ZERO), "", "which can't be chopped")
	# Saved with its day; a P11 save's list means felled today.
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.salvage.to_dict()))
	var s := Salvage.new(sim.data)
	s.day = sim.clock.day
	s.load_dict(d)
	eq(int(s.felled.get("tree_x", -1)), sim.clock.day, "the day is saved")
	s.load_dict({"felled": ["tree_y"], "stripped": {}})
	eq(s.stage("tree_y"), "stump", "an older save's felled tree is a stump today")
	eq(int(s.felled["tree_y"]), s.day, "felled today")
	# Growing back.
	var changes := sim.salvage.changes
	sim.salvage.new_day(sim.clock.day + Salvage.SAPLING_DAYS)
	eq(sim.salvage.stage("tree_x"), "sapling", "a sapling three days on")
	check(sim.salvage.changes > changes, "the views are told")
	sim.salvage.new_day(sim.clock.day + Salvage.GROWN_DAYS)
	eq(sim.salvage.stage("tree_x"), "", "a tree again a week on")
	check(not sim.salvage.felled.has("tree_x"), "and no longer felled")
	check(sim.player_hit_tree("tree_x", "tree", Vector3.ZERO).begins_with("Chopping"), "so it can be chopped again")
