extends "res://test/base_test.gd"
## First-game hints: they move on when the sim shows you did the thing (or time out), and they only
## appear in a new game, not after loading a save.

const MAIN := "res://scenes/main.tscn"


func test_hints_follow_what_you_do() -> void:
	var sim := SimWorld.new(10.0)
	var stash := sim.place_start_stash(Vector2i(1, 3))
	var hints := Hints.new()
	hints.setup(sim)
	eq(hints.advance(0.1), 0, "starts on the crate hint")
	check(hints.visible and hints.text.contains("crate"), "showing it (%s)" % hints.text)
	sim.deposit(stash)
	eq(hints.advance(0.1), 1, "using the crate moves on")
	check(hints.text.contains("Houses have food"), "to the houses (%s)" % hints.text)
	sim.loot.add("house_0_e_fridge", "fridge", Vector3(9, 0.9, -10))
	sim.loot.containers["house_0_e_fridge"]["searched"] = true
	eq(hints.advance(0.1), 2, "searching a house moves on")
	check(hints.text.contains("smelter"), "to building a smelter")
	var stock := sim.stock_at(sim.build.piece_center(stash))
	eq(sim.build.place("foundation", Vector2i(0, 0), 0, stock), "", "a floor")
	eq(hints.advance(10.0), 2, "a floor isn't enough")
	eq(sim.build.place("smelter", Vector2i(0, 0), BuildGrid.Side.EAST, stock), "", "a smelter")
	eq(hints.advance(0.1), 3, "building a smelter moves on")
	check(hints.text.contains("Press N"), "to the noise hint")
	eq(hints.advance(Hints.NOISE_SECONDS - 1.0), 3, "the noise hint stays a while")
	eq(hints.advance(1.5), 4, "then moves on by itself")
	check(hints.text.contains("muffler"), "to walls or a muffler")
	sim.inventory.give_all(sim.data.noise["muffler"]["cost"])
	eq(sim.fit_muffler(Vector2i(0, 0)), "", "fit a muffler")
	eq(hints.advance(0.1), 5, "a muffler finishes the hints")
	check(not hints.visible, "and they're gone")
	hints.free()


func test_hints_time_out() -> void:
	var sim := SimWorld.new(10.0)
	var hints := Hints.new()
	hints.setup(sim)
	eq(hints.advance(Hints.TIMEOUT - 1.0), 0, "a hint waits")
	eq(hints.advance(1.5), 1, "but not forever")
	eq(hints.advance(Hints.NOISE_SECONDS + 0.5), 2, "the house tip goes by itself")
	var walls := 0
	sim.give_debug_kit()
	sim.build.place("foundation", Vector2i(0, 0), 0, sim.inventory)
	for side in [BuildGrid.Side.NORTH, BuildGrid.Side.EAST, BuildGrid.Side.SOUTH, BuildGrid.Side.WEST]:
		if sim.build.place("wall", Vector2i(0, 0), side, sim.inventory) == "":
			walls += 1
	eq(walls, 4, "four walls")
	hints.advance(Hints.TIMEOUT)
	hints.advance(Hints.TIMEOUT)
	eq(hints.advance(0.1), 5, "four walls count for the last hint")
	hints.free()


func test_new_game_shows_hints_but_a_loaded_one_does_not() -> void:
	GameSession.skip_menu = true
	GameSession.save_path = "user://test_hints_save.json"
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	check(main.hints != null and main.hints.visible, "a new game shows the hints")
	check(main.hints != null and main.hints.text.contains("crate"), "starting with the crate")
	eq(main.save_game(), "", "save")
	main.queue_free()
	await tree.process_frame
	GameSession.pending_load = GameSession.save_path
	var again: Node3D = load(MAIN).instantiate()
	tree.root.add_child(again)
	for i in 3:
		await tree.process_frame
	check(again._loaded, "the save loaded")
	check(again.hints == null, "no hints after loading a save")
	again.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(GameSession.save_path)
	GameSession.save_path = GameSession.SAVE_PATH
	GameSession.skip_menu = false
