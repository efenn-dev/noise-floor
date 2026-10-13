extends "res://test/base_test.gd"
## The real game scene: save, rebuild the scene from the save, and find everything where it was.
## Also: Esc pauses and resumes.

const MAIN := "res://scenes/main.tscn"


func test_save_and_reload_the_game_scene() -> void:
	GameSession.skip_menu = true
	GameSession.skip_hints = true
	GameSession.save_path = "user://test_world_save.json"
	var main: Node3D = load(MAIN).instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	var sim: SimWorld = main.sim
	var stock := sim.stock_at(Vector3(0, 0, 6))
	eq(sim.build.place("foundation", Vector2i(-3, -2), 0, stock), "", "build a floor")
	eq(sim.build.place("wall", Vector2i(-3, -2), BuildGrid.Side.NORTH, stock), "", "and a wall")
	var wall := sim.build.key_for("wall", Vector2i(-3, -2), BuildGrid.Side.NORTH)
	main.player.position = Vector3(3, 0, 2)
	main.player.set_look(45, -10)
	sim.player.water = 42.0
	await tree.physics_frame
	eq(main.save_game(), "", "save")
	main.queue_free()
	await tree.process_frame

	GameSession.pending_load = GameSession.save_path
	var again: Node3D = load(MAIN).instantiate()
	tree.root.add_child(again)
	for i in 5:
		await tree.process_frame
	var sim2: SimWorld = again.sim
	check(sim2.build.pieces.has(wall), "the wall is back in the sim")
	check(again.build_view.body_for(wall) != null, "and in the world")
	check(Vector2(again.player.position.x, again.player.position.z).distance_to(Vector2(3, 2)) < 0.3,
			"you're where you saved (%s)" % again.player.position)
	near(again.player.rotation_degrees.y, 45.0, "facing the same way", 0.5)
	near(sim2.player.water, 42.0, "same thirst", 0.5)
	eq(sim2.horde.zombies.size(), sim.horde.zombies.size(), "same zombies, no fresh batch on top")

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	again.get_viewport().push_input(esc)
	check(tree.paused, "Esc pauses")
	check(again.menus.is_open(), "and shows the pause menu")
	var t := sim2.ticks
	await tree.process_frame
	await tree.process_frame
	eq(sim2.ticks, t, "time stands still while paused")
	esc.pressed = false
	again.get_viewport().push_input(esc)
	esc.pressed = true
	again.get_viewport().push_input(esc)
	check(not tree.paused, "Esc again resumes")
	again.queue_free()
	tree.paused = false
	GameSession.skip_menu = false
	GameSession.skip_hints = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSession.save_path))
	GameSession.save_path = GameSession.SAVE_PATH
	await tree.process_frame
