extends "res://test/base_test.gd"
## P10 (playtest: a new player faced fifty pieces at once, and a six-year-old who can't read yet couldn't find the
## machines): pieces you learn by building (data/learning.json, Learning), and the picture build menu that shows them.

const N := BuildGrid.Side.NORTH
const MAIN := "res://scenes/main.tscn"
const STARTERS := ["foundation", "wall", "door", "bed", "storage"]


func _sim() -> SimWorld:
	var sim := SimWorld.new(12.0, null, 6, "normal")
	sim.director.first_night_warning_sent = true
	sim.director.first_night_wave_sent = true
	sim.director.first_morning_sent = true
	sim.milestones.done.clear()
	sim.learning.start_new_game()  # a real new game (test worlds know every piece)
	return sim


func _rich() -> Inventory:
	var inv := Inventory.new()
	inv.give_all({"plank": 999, "scrap_metal": 999, "nails": 999, "metal_plate": 999})
	return inv


func test_the_data_checks_out() -> void:
	var data := GameData.load_default()
	eq(data.validate(), PackedStringArray(), "learning.json checks out (real pieces, no loops)")
	var after: Dictionary = data.learning["after"]
	for id: String in after:
		check(id in BuildController.PIECES and str(after[id]) in BuildController.PIECES, "%s after %s: both can be built" % [id, after[id]])
	var l := Learning.new(data)
	l.start_new_game()
	var m := Milestones.new(data)
	var open := BuildController.PIECES.filter(func(id: String) -> bool:
		return l.knows(id) and m.unlocked_by(id) == "" and str(data.buildables[id].get("needs_project", "")) == "")
	for id: String in STARTERS:
		check(l.knows(id), "%s is open from the start" % id)
	check(open.size() <= 6, "a new game opens only a handful of pieces (%s)" % ", ".join(open))
	# Everything can be reached: follow every chain down to an open piece.
	for id: String in BuildController.PIECES:
		var at: String = id
		var steps := 0
		while l.after(at) != "" and steps < 20:
			at = l.after(at)
			steps += 1
		check(l.after(at) == "" and steps < 20, "%s is learnable (its chain ends at %s)" % [id, at])


func test_building_a_piece_teaches_the_next() -> void:
	var sim := _sim()
	var inv := _rich()
	check(sim.build.can_place("workbench", Vector2i(0, 0), N, inv).begins_with("Build a door first"),
			"a workbench waits for a door (%s)" % sim.build.can_place("workbench", Vector2i(0, 0), N, inv))
	eq(sim.build.place("foundation", Vector2i(0, 0), N, inv), "", "a foundation")
	eq(sim.build.place("door", Vector2i(0, 0), N, inv), "", "a door on it")
	check(sim.learning.knows("workbench") and sim.learning.knows("rain_collector") == false, "the door taught the workbench only")
	check(sim.learning.fresh.has("workbench"), "it's NEW in the menu")
	sim.step()
	check("New to build: Workbench" in String(sim.messages[-1]["text"]), "and the HUD says so (%s)" % sim.messages[-1]["text"])
	var before := sim.messages.size()
	sim.step()
	eq(sim.messages.size(), before, "once")
	eq(sim.build.remove(sim.build.key_for("door", Vector2i(0, 0), N), inv), "", "taking the door down")
	check(sim.learning.knows("workbench"), "doesn't forget the workbench")
	eq(sim.build.place("workbench", Vector2i(0, 0), N, inv), "", "so it can be built")
	for id: String in ["generator", "hub", "nail_turret", "rain_collector"]:
		check(sim.learning.knows(id), "the workbench taught the %s" % id)
	check(not sim.learning.knows("smelter"), "a smelter still waits for a power pole")


func test_the_path_to_a_piece_and_the_goal_hint() -> void:
	var sim := _sim()
	eq(sim.learning.path_to("press"), ["door", "workbench", "generator", "power_pole", "smelter"], "the way to a Press")
	eq(sim.learning.path_to("wall"), [], "a wall is known")
	sim.build.place("foundation", Vector2i(0, 0), N, _rich())
	sim.build.place("door", Vector2i(0, 0), N, _rich())
	eq(sim.learning.path_to("press"), ["workbench", "generator", "power_pole", "smelter"], "one step shorter after a door")
	sim.guidance.defend_active = true
	var panel := ObjectivesPanel.new()
	panel.force_visible = true
	panel.setup(sim)
	panel.refresh()
	check("First learn it: build a Workbench, then the Nail turret" in panel.text(), "the defend goal says how to learn the turret (%s)" % panel.text())
	sim.build.place("workbench", Vector2i(0, 0), N, _rich())
	panel.refresh()
	check(not "First learn it" in panel.text(), "and stops once it's known")
	panel.free()


func test_the_start_stash_teaches_nothing_and_saves_keep_it() -> void:
	var sim := _sim()
	sim.place_start_stash(Vector2i(40, 40))
	check(sim.learning.built.is_empty(), "the game's own crate isn't the player building")
	sim.build.place("foundation", Vector2i(0, 0), N, _rich())
	sim.build.place("wall", Vector2i(0, 0), N, _rich())
	sim.learning.seen("barricade")
	var d: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.to_dict(sim)))
	var l := Learning.new(sim.data)
	l.load_dict(d["learning"])
	check(not l.knows_all and l.knows("barricade") and not l.knows("spikes"), "a save keeps what you learned")
	check(not l.fresh.has("barricade"), "and what you've looked at")
	l.load_dict({})
	check(l.knows_all and l.knows("radio_mast") and l.knows("smelter"), "a save from before P10 knows every piece")
	var fresh_world := SimWorld.new(12.0, null, 6, "normal")
	check(fresh_world.learning.knows("smelter"), "test worlds know every piece")


func test_the_picture_menu_shows_locks_costs_and_new() -> void:
	InputSetup.assume_captured = true
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var menu: BuildMenu = main.build_menu
	check(not sim.learning.knows_all, "the main scene with no demo flag is a real new game: learning from scratch")
	main._open_build_menu()
	check(menu.is_open(), "open")
	eq(menu.group, "Base", "on the Base pictures")
	await tree.process_frame
	eq(menu.tile_order("Base").slice(0, 5), STARTERS, "the five you can build come first")
	check(menu.lock_text("workbench").begins_with("Build a door first"), "a locked one says what to build first")
	eq(menu.first_piece("workbench"), "door", "and shows the door's picture")
	eq(menu.first_piece("splitter"), "hub", "a milestone piece shows the Hub's")
	var tile: Dictionary = menu._tiles["workbench"]
	check((tile["lock"] as Control).visible and (tile["first"] as Control).visible, "the workbench tile has a padlock and the door")
	check(not (menu._tiles["wall"]["lock"] as Control).visible, "the wall tile doesn't")
	check(menu._buttons["workbench"].get_index() > menu._buttons["storage"].get_index(), "locked tiles come after open ones")
	menu.show_group("Factory")
	check(menu._grids["Factory"].visible and not menu._grids["Base"].visible, "the sidebar switches the pictures")
	menu.highlight("smelter")
	check("Build a power pole first" in menu.details_text("smelter"), "the words say it too")
	eq(menu.recipes_of("smelter"), ["smelt_plate"], "what the smelter makes, as pictures")
	check(menu.recipes_of("press").size() > 3, "the press shows several")
	menu.pick("smelter")
	check(menu.is_open() and not main.builder.active, "clicking a locked piece doesn't start building")
	check("Build a power pole first" in String(sim.messages[-1]["text"]), "it says why (%s)" % sim.messages[-1]["text"])
	# Learning something: NEW on its tile and on its group in the sidebar, gone once you point at it.
	var stash: Inventory = sim.stock_at(sim.player_pos)
	sim.build.place("foundation", Vector2i(-30, 30), N, _rich())
	sim.build.place("door", Vector2i(-30, 30), N, _rich())
	menu.show_group("Base")
	menu.refresh()
	check((menu._tiles["workbench"]["new"] as Control).visible, "the workbench says NEW")
	check((menu._side_new["Base"] as Control).visible, "so does the Base picture in the sidebar")
	check(not (menu._tiles["workbench"]["lock"] as Control).visible, "and its padlock is gone")
	menu.highlight("workbench")
	check(not (menu._tiles["workbench"]["new"] as Control).visible, "pointing at it clears NEW")
	check(stash != null, "the crates near you pay (%s)" % stash)
	menu.close()
	main.queue_free()
	InputSetup.assume_captured = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	await tree.process_frame
